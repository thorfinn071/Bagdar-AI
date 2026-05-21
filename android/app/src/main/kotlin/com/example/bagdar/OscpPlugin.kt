package com.example.bagdar

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/// GATT plugin for the Open Smart-Cane Sensor Pod (OSCP).
///
/// Phase 2 — Direction 7.
/// Channel: bagdar/oscp_pod
/// Methods in  → connectOscp() → Bool, disconnectOscp()
/// Callbacks out →
///   onOscpConnected({firmware: String})
///   onOscpDisconnected
///   onOscpRange(Double meters)
///   onOscpImu({accel: Double m/s², gyro: Double rad/s})
///   onOscpButton
///   onOscpBattery(Int percent)
///   onOscpError(String)
///
/// The plugin scans for a BLE peripheral advertising the OSCP service UUID,
/// connects, enables notifications on range/IMU/button characteristics,
/// and reads battery + firmware version on connection.
///
/// Risk gate: app remains fully usable without the pod. Fall detection
/// never depends on cane IMU as the primary trigger.
class OscpPlugin(private val context: Context) {

    companion object {
        private val SERVICE_UUID = UUID.fromString("00001810-0000-1000-8000-00805f9b34fb")
        private val RANGE_CHAR_UUID = UUID.fromString("00002a6e-0000-1000-8000-00805f9b34fb")
        private val IMU_CHAR_UUID = UUID.fromString("00002a6f-0000-1000-8000-00805f9b34fb")
        private val BUTTON_CHAR_UUID = UUID.fromString("00002a70-0000-1000-8000-00805f9b34fb")
        private val BATTERY_CHAR_UUID = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")
        private val FIRMWARE_CHAR_UUID = UUID.fromString("00002a26-0000-1000-8000-00805f9b34fb")
        private val CLIENT_CONFIG_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        private const val SCAN_TIMEOUT_MS = 30000L
    }

    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var scanning = false
    @Volatile private var connected = false
    private var connectedGatt: BluetoothGatt? = null
    private var scanCallback: ScanCallback? = null
    private var firmwareVersion = ""

    fun register(channel: MethodChannel) {
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "connectOscp" -> result.success(startConnect())
                "disconnectOscp" -> {
                    doDisconnect()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasBlePermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) ==
                PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun getAdapter(): BluetoothAdapter? {
        val bm = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return bm?.adapter
    }

    private fun startConnect(): Boolean {
        if (connected || scanning) return connected || scanning
        if (!hasBlePermission()) {
            sendCallback("onOscpError", "permission_denied")
            return false
        }
        val adapter = getAdapter() ?: run {
            sendCallback("onOscpError", "ble_not_available")
            return false
        }
        if (!adapter.isEnabled) {
            sendCallback("onOscpError", "ble_disabled")
            return false
        }

        scanning = true
        val scanner = adapter.bluetoothLeScanner ?: run {
            scanning = false
            sendCallback("onOscpError", "scanner_unavailable")
            return false
        }

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_BALANCED)
            .build()

        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                if (!scanning) return
                stopScan()
                connectGatt(result.device)
            }

            override fun onScanFailed(errorCode: Int) {
                scanning = false
                sendCallback("onOscpError", "scan_failed:$errorCode")
            }
        }
        scanCallback = cb

        try {
            @Suppress("MissingPermission")
            scanner.startScan(listOf(filter), settings, cb)
            mainHandler.postDelayed({
                if (scanning) {
                    stopScan()
                    sendCallback("onOscpError", "scan_timeout")
                }
            }, SCAN_TIMEOUT_MS)
        } catch (e: Exception) {
            scanning = false
            sendCallback("onOscpError", "scan_start_failed: ${e.message}")
            return false
        }
        return true
    }

    private fun stopScan() {
        scanning = false
        val cb = scanCallback ?: return
        scanCallback = null
        val adapter = getAdapter() ?: return
        try {
            @Suppress("MissingPermission")
            adapter.bluetoothLeScanner?.stopScan(cb)
        } catch (_: Exception) {}
    }

    private fun connectGatt(device: BluetoothDevice) {
        val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        connected = true
                        try { @Suppress("MissingPermission") gatt.discoverServices() } catch (_: Exception) {}
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        connected = false
                        connectedGatt = null
                        try { @Suppress("MissingPermission") gatt.close() } catch (_: Exception) {}
                        sendCallback("onOscpDisconnected", null)
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    doDisconnect()
                    sendCallback("onOscpError", "service_discovery_failed")
                    return
                }
                val svc = gatt.getService(SERVICE_UUID) ?: run {
                    doDisconnect()
                    sendCallback("onOscpError", "oscp_service_not_found")
                    return
                }

                // Read firmware version — fires onOscpConnected when done.
                svc.getCharacteristic(FIRMWARE_CHAR_UUID)?.let { fw ->
                    try { @Suppress("MissingPermission") gatt.readCharacteristic(fw) } catch (_: Exception) {}
                }

                // Enable notifications for streaming characteristics.
                listOf(RANGE_CHAR_UUID, IMU_CHAR_UUID, BUTTON_CHAR_UUID).forEach { uuid ->
                    svc.getCharacteristic(uuid)?.let { char ->
                        enableNotification(gatt, char)
                    }
                }

                // Read initial battery level.
                svc.getCharacteristic(BATTERY_CHAR_UUID)?.let { bat ->
                    try { @Suppress("MissingPermission") gatt.readCharacteristic(bat) } catch (_: Exception) {}
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                if (status != BluetoothGatt.GATT_SUCCESS) return
                if (characteristic.uuid == FIRMWARE_CHAR_UUID) {
                    firmwareVersion = characteristic.getStringValue(0) ?: ""
                    sendCallbackMap("onOscpConnected", mapOf("firmware" to firmwareVersion))
                } else {
                    dispatchCharacteristic(characteristic)
                }
            }

            @Deprecated("Deprecated in API 33")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                dispatchCharacteristic(characteristic)
            }
        }

        try {
            val gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                @Suppress("MissingPermission")
                device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            } else {
                @Suppress("MissingPermission")
                device.connectGatt(context, false, gattCallback)
            }
            connectedGatt = gatt
        } catch (e: Exception) {
            connected = false
            sendCallback("onOscpError", "connect_failed: ${e.message}")
        }
    }

    private fun enableNotification(gatt: BluetoothGatt, char: BluetoothGattCharacteristic) {
        try {
            @Suppress("MissingPermission")
            gatt.setCharacteristicNotification(char, true)
            char.getDescriptor(CLIENT_CONFIG_UUID)?.let { desc ->
                desc.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("MissingPermission")
                gatt.writeDescriptor(desc)
            }
        } catch (_: Exception) {}
    }

    private fun dispatchCharacteristic(char: BluetoothGattCharacteristic) {
        val value = char.value ?: return
        when (char.uuid) {
            RANGE_CHAR_UUID -> {
                // 2-byte uint16 little-endian millimetres
                if (value.size >= 2) {
                    val mm = ((value[1].toInt() and 0xFF) shl 8) or (value[0].toInt() and 0xFF)
                    sendCallback("onOscpRange", mm / 1000.0)
                }
            }
            IMU_CHAR_UUID -> {
                // 4 bytes: accel uint16 × 0.01 m/s², gyro uint16 × 0.01 rad/s, little-endian
                if (value.size >= 4) {
                    val accelRaw = ((value[1].toInt() and 0xFF) shl 8) or (value[0].toInt() and 0xFF)
                    val gyroRaw = ((value[3].toInt() and 0xFF) shl 8) or (value[2].toInt() and 0xFF)
                    sendCallbackMap(
                        "onOscpImu",
                        mapOf("accel" to accelRaw / 100.0, "gyro" to gyroRaw / 100.0),
                    )
                }
            }
            BUTTON_CHAR_UUID -> sendCallback("onOscpButton", null)
            BATTERY_CHAR_UUID -> {
                if (value.isNotEmpty()) sendCallback("onOscpBattery", value[0].toInt() and 0xFF)
            }
        }
    }

    private fun doDisconnect() {
        stopScan()
        connected = false
        try { @Suppress("MissingPermission") connectedGatt?.disconnect() } catch (_: Exception) {}
        try { @Suppress("MissingPermission") connectedGatt?.close() } catch (_: Exception) {}
        connectedGatt = null
    }

    private fun sendCallback(method: String, arg: Any?) {
        mainHandler.post {
            try { methodChannel?.invokeMethod(method, arg) } catch (_: Exception) {}
        }
    }

    private fun sendCallbackMap(method: String, args: Map<String, Any?>) {
        mainHandler.post {
            try { methodChannel?.invokeMethod(method, args) } catch (_: Exception) {}
        }
    }

    fun dispose() {
        doDisconnect()
        methodChannel = null
    }
}
