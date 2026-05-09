package com.example.bagdar

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.RingtoneManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SmsMessage
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var hardwareDepthSession: HardwareDepthSession? = null
    private var hardwareDepthEventSink: EventChannel.EventSink? = null

    private var incomingSmsSink: EventChannel.EventSink? = null
    private var incomingSmsReceiver: BroadcastReceiver? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var lastPingTime: Long = 0
    private val watchdogHandler = Handler(Looper.getMainLooper())
    private val watchdogRunnable = object : Runnable {
        override fun run() {
            if (lastPingTime > 0) {
                val diff = System.currentTimeMillis() - lastPingTime
                if (diff > 6000) {
                    // 6 seconds without ping -> trigger fallback alarm
                    triggerHardwareAlarm()
                }
            }
            watchdogHandler.postDelayed(this, 2000)
        }
    }

    private fun triggerHardwareAlarm() {
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 200, 500, 200, 1000), intArrayOf(0, 255, 0, 255, 0, 255), -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(longArrayOf(0, 500, 200, 500, 200, 1000), -1)
            }
            val notification = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            val r = RingtoneManager.getRingtone(applicationContext, notification)
            r.play()
        } catch (e: Exception) {}
    }

    override fun onDestroy() {
        super.onDestroy()
        watchdogHandler.removeCallbacks(watchdogRunnable)
        unregisterIncomingSmsReceiver()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bagdar/device_info",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                "getFreeBytesAtPath" -> {
                    val path = call.argument<String>("path") ?: filesDir.absolutePath
                    try {
                        val stat = StatFs(path)
                        result.success(stat.availableBlocksLong * stat.blockSizeLong)
                    } catch (e: Exception) {
                        result.error("STAT_FAILED", e.message, null)
                    }
                }
                "getThermalReadings" -> {
                    val batteryTempC = readBatteryTemperatureC()
                    val thermalStatus = readThermalStatus()
                    result.success(
                        mapOf(
                            "batteryTempC" to batteryTempC,
                            "thermalStatus" to thermalStatus,
                        ),
                    )
                }
                "getMemoryInfo" -> {
                    try {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val info = ActivityManager.MemoryInfo()
                        am.getMemoryInfo(info)
                        result.success(
                            mapOf(
                                "availMB" to (info.availMem / (1024L * 1024L)).toInt(),
                                "totalMB" to (info.totalMem / (1024L * 1024L)).toInt(),
                                "lowMemory" to info.lowMemory,
                                "thresholdMB" to (info.threshold / (1024L * 1024L)).toInt(),
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("MEMINFO_FAILED", e.message, null)
                    }
                }
                "getDeviceInfo" -> {
                    result.success(
                        mapOf(
                            "manufacturer" to (Build.MANUFACTURER ?: ""),
                            "model" to (Build.MODEL ?: ""),
                            "device" to (Build.DEVICE ?: ""),
                            "brand" to (Build.BRAND ?: ""),
                            "hardware" to (Build.HARDWARE ?: ""),
                            "sdkInt" to Build.VERSION.SDK_INT,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bagdar/watchdog",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ping" -> {
                    if (lastPingTime == 0L) {
                        watchdogHandler.post(watchdogRunnable)
                    }
                    lastPingTime = System.currentTimeMillis()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bagdar/sms",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSms" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")?.trim().orEmpty()
                    val message = call.argument<String>("message").orEmpty()
                    if (phoneNumber.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "phoneNumber is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val smsManager = SmsManager.getDefault()
                        val parts = smsManager.divideMessage(message)
                        if (parts.size > 1) {
                            smsManager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
                        } else {
                            smsManager.sendTextMessage(phoneNumber, null, message, null, null)
                        }
                        result.success(true)
                    } catch (e: SecurityException) {
                        result.error("SMS_PERMISSION_DENIED", e.message, null)
                    } catch (e: Exception) {
                        result.error("SMS_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bagdar/hardware_depth",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(HardwareDepthSession.isSupported(this))
                "startSession" -> {
                    val mapSize = call.argument<Int>("mapSize") ?: 256
                    val session = hardwareDepthSession ?: HardwareDepthSession(this, mapSize)
                    hardwareDepthSession = session
                    session.setEventSink(hardwareDepthEventSink)
                    session.start { started ->
                        result.success(started)
                        if (!started) {
                            hardwareDepthSession = null
                        }
                    }
                }
                "stopSession" -> {
                    hardwareDepthSession?.stop()
                    hardwareDepthSession = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bagdar/hardware_depth_frames",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                hardwareDepthEventSink = events
                hardwareDepthSession?.setEventSink(events)
            }

            override fun onCancel(arguments: Any?) {
                hardwareDepthEventSink = null
                hardwareDepthSession?.setEventSink(null)
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bagdar/incoming_sms",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                incomingSmsSink = events
                registerIncomingSmsReceiver()
            }

            override fun onCancel(arguments: Any?) {
                unregisterIncomingSmsReceiver()
                incomingSmsSink = null
            }
        })
    }

    private fun registerIncomingSmsReceiver() {
        if (incomingSmsReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
                try {
                    val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                    if (messages.isNullOrEmpty()) return
                    val grouped = LinkedHashMap<String, StringBuilder>()
                    var latestTs = 0L
                    for (msg in messages) {
                        val addr = msg.originatingAddress ?: continue
                        val body = msg.messageBody ?: ""
                        val buf = grouped.getOrPut(addr) { StringBuilder() }
                        buf.append(body)
                        if (msg.timestampMillis > latestTs) latestTs = msg.timestampMillis
                    }
                    if (grouped.isEmpty()) return
                    val tsMillis = if (latestTs > 0) latestTs else System.currentTimeMillis()
                    for ((addr, buf) in grouped) {
                        val payload = mapOf(
                            "sender" to addr,
                            "body" to buf.toString(),
                            "timestamp" to tsMillis,
                        )
                        mainHandler.post {
                            try {
                                incomingSmsSink?.success(payload)
                            } catch (_: Exception) {
                            }
                        }
                    }
                } catch (_: Exception) {
                }
            }
        }
        val filter = IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION).apply {
            priority = 999
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(receiver, filter)
            }
            incomingSmsReceiver = receiver
        } catch (_: Exception) {
            incomingSmsReceiver = null
        }
    }

    private fun unregisterIncomingSmsReceiver() {
        val r = incomingSmsReceiver ?: return
        try {
            unregisterReceiver(r)
        } catch (_: Exception) {
        }
        incomingSmsReceiver = null
    }

    private fun readBatteryTemperatureC(): Double? {
        return try {
            val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val tempTenths = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
            if (tempTenths == null || tempTenths == Int.MIN_VALUE) return null
            tempTenths / 10.0
        } catch (e: Exception) {
            null
        }
    }

    private fun readThermalStatus(): Int? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                powerManager.currentThermalStatus
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }
}
