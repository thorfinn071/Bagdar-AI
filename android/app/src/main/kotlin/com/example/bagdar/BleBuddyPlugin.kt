package com.example.bagdar

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
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
import java.util.concurrent.ConcurrentHashMap

/// BLE central + peripheral plugin for mesh-net buddy alerts.
///
/// Phase 2 — Direction 3.
/// Channel: bagdar/ble_buddy
/// Methods in  → startBuddyMesh() → Bool, stopBuddyMesh()
/// Callbacks out → onBuddyPayload(Uint8List), onBuddyError(String)
///
/// Central role: scans for Bagdar peers advertising BAGDAR_SERVICE_UUID,
/// connects via GATT, reads/subscribes to the hazard characteristic,
/// and forwards the raw JSON payload bytes to Dart.
///
/// Peripheral role: advertises the service UUID and serves a readable
/// hazard characteristic so peers can read locally pending payloads.
/// Peripheral is skipped gracefully if the device chipset does not
/// support multi-advertisement.
///
/// PII-free: no device identity in payloads. Anonymous rotating keys
/// are a future hardening step; current payload is plaintext JSON
/// matching `MeshBuddyPayload.toBytes()`.
class BleBuddyPlugin(private val context: Context) {

    companion object {
        val BAGDAR_SERVICE_UUID: UUID = UUID.fromString("0000ba64-0000-1000-8000-00805f9b34fb")
        val HAZARD_CHAR_UUID: UUID = UUID.fromString("0000ba65-0000-1000-8000-00805f9b34fb")
        val CLIENT_CONFIG_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        private const val SCAN_WINDOW_MS = 15000L
        private const val RESCAN_INTERVAL_MS = 45000L
        private const val PEER_REVISIT_MS = 120000L
    }

    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var running = false
    private var bleAdapter: BluetoothAdapter? = null
    private var gattServer: BluetoothGattServer? = null
    private var scanCallback: ScanCallback? = null
    private var advertiseCallback: AdvertiseCallback? = null

    private val connectedGatts = ConcurrentHashMap<String, BluetoothGatt>()
    private val seenDevices = ConcurrentHashMap<String, Long>()

    private val rescanRunnable = object : Runnable {
        override fun run() {
            if (running) {
                stopScanning()
                startScanning()
                rescanHandler.postDelayed(this, RESCAN_INTERVAL_MS)
            }
        }
    }
    private val rescanHandler = Handler(Looper.getMainLooper())

    fun register(channel: MethodChannel) {
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBuddyMesh" -> result.success(startBuddyMesh())
                "stopBuddyMesh" -> {
                    stopBuddyMesh()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasScanPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) ==
                PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun hasAdvertisePermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADVERTISE) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun getAdapter(): BluetoothAdapter? {
        val bm = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return bm?.adapter
    }

    private fun startBuddyMesh(): Boolean {
        if (running) return true
        if (!hasScanPermission()) {
            sendError("permission_denied")
            return false
        }
        val adapter = getAdapter() ?: run {
            sendError("ble_not_available")
            return false
        }
        if (!adapter.isEnabled) {
            sendError("ble_disabled")
            return false
        }
        bleAdapter = adapter
        running = true
        startPeripheral(adapter)
        startScanning()
        rescanHandler.postDelayed(rescanRunnable, RESCAN_INTERVAL_MS)
        return true
    }

    private fun stopBuddyMesh() {
        running = false
        rescanHandler.removeCallbacks(rescanRunnable)
        stopScanning()
        stopAdvertising()
        closeAllGatts()
        try { gattServer?.close() } catch (_: Exception) {}
        gattServer = null
        bleAdapter = null
    }

    private fun startScanning() {
        val scanner = bleAdapter?.bluetoothLeScanner ?: return
        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(BAGDAR_SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER)
            .build()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val address = result.device?.address ?: return
                val now = System.currentTimeMillis()
                if ((now - (seenDevices[address] ?: 0L)) < PEER_REVISIT_MS) return
                seenDevices[address] = now
                connectPeer(result.device)
            }

            override fun onScanFailed(errorCode: Int) {
                if (errorCode == SCAN_FAILED_APPLICATION_REGISTRATION_FAILED ||
                    errorCode == SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES) {
                    sendError("scan_throttled:$errorCode")
                    stopBuddyMesh()
                }
            }
        }
        scanCallback = cb
        try {
            @Suppress("MissingPermission")
            scanner.startScan(listOf(filter), settings, cb)
            mainHandler.postDelayed({ if (running) stopScanning() }, SCAN_WINDOW_MS)
        } catch (e: Exception) {
            sendError("scan_start_failed: ${e.message}")
        }
    }

    private fun stopScanning() {
        val scanner = bleAdapter?.bluetoothLeScanner ?: return
        val cb = scanCallback ?: return
        scanCallback = null
        try {
            @Suppress("MissingPermission")
            scanner.stopScan(cb)
        } catch (_: Exception) {}
    }

    private fun connectPeer(device: BluetoothDevice) {
        val address = device.address
        if (connectedGatts.containsKey(address)) return
        val cb = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        try { @Suppress("MissingPermission") gatt.discoverServices() } catch (_: Exception) {}
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        connectedGatts.remove(address)
                        try { @Suppress("MissingPermission") gatt.close() } catch (_: Exception) {}
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    disconnectGatt(gatt)
                    return
                }
                val svc = gatt.getService(BAGDAR_SERVICE_UUID) ?: run { disconnectGatt(gatt); return }
                val char = svc.getCharacteristic(HAZARD_CHAR_UUID) ?: run { disconnectGatt(gatt); return }
                try {
                    @Suppress("MissingPermission")
                    gatt.setCharacteristicNotification(char, true)
                    char.getDescriptor(CLIENT_CONFIG_UUID)?.let { desc ->
                        desc.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        @Suppress("MissingPermission")
                        gatt.writeDescriptor(desc)
                    }
                    @Suppress("MissingPermission")
                    gatt.readCharacteristic(char)
                } catch (_: Exception) {}
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS &&
                    characteristic.uuid == HAZARD_CHAR_UUID) {
                    val data = characteristic.value
                    if (!data.isNullOrEmpty()) sendPayload(data)
                    mainHandler.postDelayed({ disconnectGatt(gatt) }, 500)
                }
            }

            @Deprecated("Deprecated in API 33")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                if (characteristic.uuid == HAZARD_CHAR_UUID) {
                    val data = characteristic.value
                    if (!data.isNullOrEmpty()) sendPayload(data)
                }
            }
        }
        try {
            val gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                @Suppress("MissingPermission")
                device.connectGatt(context, false, cb, BluetoothDevice.TRANSPORT_LE)
            } else {
                @Suppress("MissingPermission")
                device.connectGatt(context, false, cb)
            }
            connectedGatts[address] = gatt
        } catch (_: Exception) {}
    }

    private fun disconnectGatt(gatt: BluetoothGatt) {
        val address = gatt.device?.address ?: return
        connectedGatts.remove(address)
        try { @Suppress("MissingPermission") gatt.disconnect() } catch (_: Exception) {}
        try { @Suppress("MissingPermission") gatt.close() } catch (_: Exception) {}
    }

    private fun closeAllGatts() {
        for ((_, gatt) in connectedGatts) {
            try { @Suppress("MissingPermission") gatt.disconnect() } catch (_: Exception) {}
            try { @Suppress("MissingPermission") gatt.close() } catch (_: Exception) {}
        }
        connectedGatts.clear()
    }

    private fun startPeripheral(adapter: BluetoothAdapter) {
        if (!adapter.isMultipleAdvertisementSupported) return
        if (!hasAdvertisePermission()) return
        val bm = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return

        val server = try {
            bm.openGattServer(context, object : BluetoothGattServerCallback() {})
        } catch (_: Exception) { return }
        gattServer = server

        val svc = BluetoothGattService(BAGDAR_SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val char = BluetoothGattCharacteristic(
            HAZARD_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ,
        )
        val cccd = BluetoothGattDescriptor(
            CLIENT_CONFIG_UUID,
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
        )
        char.addDescriptor(cccd)
        svc.addCharacteristic(char)
        try {
            @Suppress("MissingPermission")
            server.addService(svc)
        } catch (_: Exception) { return }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_LOW)
            .setConnectable(true)
            .build()
        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(BAGDAR_SERVICE_UUID))
            .setIncludeDeviceName(false)
            .build()
        val advCb = object : AdvertiseCallback() {
            override fun onStartFailure(errorCode: Int) {}
        }
        advertiseCallback = advCb
        try {
            @Suppress("MissingPermission")
            adapter.bluetoothLeAdvertiser?.startAdvertising(settings, data, advCb)
        } catch (_: Exception) {}
    }

    private fun stopAdvertising() {
        val cb = advertiseCallback ?: return
        advertiseCallback = null
        try {
            @Suppress("MissingPermission")
            bleAdapter?.bluetoothLeAdvertiser?.stopAdvertising(cb)
        } catch (_: Exception) {}
    }

    private fun sendPayload(data: ByteArray) {
        mainHandler.post {
            try { methodChannel?.invokeMethod("onBuddyPayload", data) } catch (_: Exception) {}
        }
    }

    private fun sendError(msg: String) {
        mainHandler.post {
            try { methodChannel?.invokeMethod("onBuddyError", msg) } catch (_: Exception) {}
        }
    }

    fun dispose() {
        stopBuddyMesh()
        methodChannel = null
    }
}
