package com.example.bagdar

import android.Manifest
import android.app.ActivityManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.RingtoneManager
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Telephony
import android.provider.Settings
import android.telephony.CellInfo
import android.telephony.CellInfoCdma
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoWcdma
import android.app.Activity
import android.app.PendingIntent
import android.telephony.SmsManager
import android.telephony.SmsMessage
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private fun isResearchBuild(): Boolean =
        BuildConfig.FLAVOR.equals("research", ignoreCase = true)

    private var hardwareDepthSession: HardwareDepthSession? = null
    private var hardwareDepthEventSink: EventChannel.EventSink? = null
    private var nativeTtsPlugin: NativeTtsPlugin? = null
    private var onboardingVoicePlugin: OnboardingVoicePlugin? = null
    private var wakeWordPlugin: VoskWakeWordPlugin? = null
    private val voiceCaptureGate = VoiceCaptureGate()

    private var audioCapturePlugin: AudioCapturePlugin? = null
    private var sonarPlugin: SonarPlugin? = null
    private var bleBuddyPlugin: BleBuddyPlugin? = null
    private var oscpPlugin: OscpPlugin? = null
    private var onDeviceModelPlugin: OnDeviceModelPlugin? = null

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

    override fun onResume() {
        super.onResume()
        wakeWordPlugin?.resumeForeground()
    }

    override fun onPause() {
        wakeWordPlugin?.suspend()
        onboardingVoicePlugin?.cancel()
        super.onPause()
        watchdogHandler.removeCallbacks(watchdogRunnable)
        lastPingTime = 0L
    }

    override fun onDestroy() {
        wakeWordPlugin?.dispose()
        wakeWordPlugin = null
        onboardingVoicePlugin?.dispose()
        onboardingVoicePlugin = null
        super.onDestroy()
        nativeTtsPlugin?.dispose()
        nativeTtsPlugin = null
        watchdogHandler.removeCallbacks(watchdogRunnable)
        unregisterIncomingSmsReceiver()
        try {
            audioCapturePlugin?.dispose()
        } catch (_: Exception) {
        }
        audioCapturePlugin = null
        try { sonarPlugin?.dispose() } catch (_: Exception) {}
        sonarPlugin = null
        try { bleBuddyPlugin?.dispose() } catch (_: Exception) {}
        bleBuddyPlugin = null
        try { oscpPlugin?.dispose() } catch (_: Exception) {}
        oscpPlugin = null
        onDeviceModelPlugin = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        onboardingVoicePlugin?.dispose()
        onboardingVoicePlugin = OnboardingVoicePlugin(
            applicationContext,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bagdar/onboarding_voice"),
            voiceCaptureGate,
        )
        wakeWordPlugin?.dispose()
        val wakeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bagdar/wake_word")
        if (isResearchBuild()) {
            wakeWordPlugin = VoskWakeWordPlugin(applicationContext, wakeChannel, voiceCaptureGate)
        } else {
            wakeChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "availability", "prepare" -> result.success("disabled")
                    "cancel" -> result.success(null)
                    else -> result.error("disabled", "Wake candidate is research-only", null)
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bagdar/onboarding")
            .setMethodCallHandler { call, result ->
                if (call.method != "openSpeechSettings") {
                    result.notImplemented()
                } else {
                    var opened = false
                    // OEMs can omit the TTS page; accessibility settings remain a fallback.
                    for (action in listOf("com.android.settings.TTS_SETTINGS", Settings.ACTION_ACCESSIBILITY_SETTINGS)) {
                        try {
                            startActivity(Intent(action))
                            opened = true
                            break
                        } catch (_: android.content.ActivityNotFoundException) {
                        } catch (_: SecurityException) {
                        }
                    }
                    result.success(opened)
                }
            }
        // Phase 2 — Kazakh-only native TTS bridge (RHVoice + espeak-ng).
        // Registered first so any bridge probe issued from Dart during
        // `NativeTtsBridge.init()` lands on a live channel.
        run {
            val plugin = NativeTtsPlugin(applicationContext)
            nativeTtsPlugin?.dispose()
            nativeTtsPlugin = plugin
            val method = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "bagdar/native_tts",
            )
            val event = EventChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "bagdar/native_tts_events",
            )
            plugin.register(method, event)
        }

        // Phase 3 — multilingual OCR via PaddleOCR. Reports
        // `available = false` until PaddleLite.aar + model artifacts
        // ship; OcrService falls back to ML Kit until then.
        run {
            val plugin = PaddleOcrPlugin(applicationContext)
            val method = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                PaddleOcrPlugin.METHOD_CHANNEL,
            )
            plugin.register(method)
        }

        // Phase 0 foundations — register the AudioCapturePlugin so the
        // Dart `AudioCaptureBroker` (bagdar/audio_capture +
        // bagdar/audio_frames) is reachable. AWM, reverb classifier,
        // ambient classifier, and future ASR backends all depend on
        // this channel; without registration they silently fail to
        // observe the mic. Plugin honours mic permission internally.
        run {
            val plugin = AudioCapturePlugin(applicationContext)
            val method = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "bagdar/audio_capture",
            )
            val event = EventChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "bagdar/audio_frames",
            )
            plugin.setupChannels(method, event)
            audioCapturePlugin = plugin
        }

        if (isResearchBuild()) {
            // Phase 2 — BLE mesh-net buddy alerts (Direction 3).
            run {
                val plugin = BleBuddyPlugin(applicationContext)
                val channel = MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    "bagdar/ble_buddy",
                )
                plugin.register(channel)
                bleBuddyPlugin = plugin
            }

            // Phase 2 — Open Smart-Cane Sensor Pod GATT bridge (Direction 7).
            run {
                val plugin = OscpPlugin(applicationContext)
                val channel = MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    "bagdar/oscp_pod",
                )
                plugin.register(channel)
                oscpPlugin = plugin
            }

            // Phase 5 — FMCW sonar chirp echolocation (Direction 1).
            run {
                val plugin = SonarPlugin(applicationContext)
                val channel = MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    "bagdar/sonar",
                )
                plugin.register(channel)
                sonarPlugin = plugin
            }

            // Phase 4 — On-device VLM companion stub (Direction 11).
            // Returns false for loadVlmModel until a model pack is installed.
            run {
                val plugin = OnDeviceModelPlugin(applicationContext)
                val channel = MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    "bagdar/vlm_engine",
                )
                plugin.register(channel)
                onDeviceModelPlugin = plugin
            }
        }

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
                "getNetworkContext" -> {
                    result.success(readNetworkContext())
                }
                "getHardwareCapabilities" -> {
                    result.success(readHardwareCapabilities())
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
                "stop" -> {
                    watchdogHandler.removeCallbacks(watchdogRunnable)
                    lastPingTime = 0L
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
                        val sentAction = "com.example.bagdar.SMS_SENT_${System.nanoTime()}"
                        val done = BooleanArray(1)

                        val receiver = object : BroadcastReceiver() {
                            override fun onReceive(ctx: Context, intent: Intent) {
                                if (done[0]) return
                                done[0] = true
                                try { this@MainActivity.unregisterReceiver(this) } catch (_: Exception) {}
                                result.success(resultCode == Activity.RESULT_OK)
                            }
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            registerReceiver(receiver, IntentFilter(sentAction), Context.RECEIVER_NOT_EXPORTED)
                        } else {
                            @Suppress("UnspecifiedRegisterReceiverFlag")
                            registerReceiver(receiver, IntentFilter(sentAction))
                        }

                        mainHandler.postDelayed({
                            if (!done[0]) {
                                done[0] = true
                                try { unregisterReceiver(receiver) } catch (_: Exception) {}
                                result.success(false)
                            }
                        }, 10_000L)

                        val flags = PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
                        val sentPi = PendingIntent.getBroadcast(this, 0, Intent(sentAction), flags)

                        if (parts.size > 1) {
                            val sentIntents = ArrayList<PendingIntent?>(parts.size)
                            repeat(parts.size - 1) { sentIntents.add(null) }
                            sentIntents.add(sentPi)
                            smsManager.sendMultipartTextMessage(phoneNumber, null, parts, sentIntents, null)
                        } else {
                            smsManager.sendTextMessage(phoneNumber, null, message, sentPi, null)
                        }
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

        if (isResearchBuild()) {
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

    /// Collect optional non-camera hardware capability flags consumed by
    /// `DeviceCapabilityProbe.readHardwareCapabilities()`. Conservative
    /// defaults: every flag is `false` until the underlying probe
    /// confirms support, so a probe failure never claims a capability
    /// the device does not have.
    private fun readHardwareCapabilities(): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()

        // BLE roles. Central is widely supported on API 26+; peripheral
        // is gated by chipset firmware and is checked via the Android
        // adapter helper. Both can be false on emulators.
        try {
            val pm = applicationContext.packageManager
            val hasBle = pm.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
            var central = false
            var peripheral = false
            if (hasBle) {
                val bm = applicationContext.getSystemService(Context.BLUETOOTH_SERVICE)
                    as? BluetoothManager
                val adapter: BluetoothAdapter? = bm?.adapter
                if (adapter != null) {
                    central = true
                    peripheral = try {
                        adapter.isMultipleAdvertisementSupported
                    } catch (_: Exception) {
                        false
                    }
                }
            }
            out["bleCentral"] = central
            out["blePeripheral"] = peripheral
        } catch (_: Exception) {
            out["bleCentral"] = false
            out["blePeripheral"] = false
        }

        // 48 kHz mic capture support. AudioRecord.getMinBufferSize is
        // the canonical way to ask the platform whether a (rate,
        // channel, encoding) tuple is realisable. Negative return ⇒
        // unsupported. Mono PCM-16 is the only combination the sonar
        // prototype needs.
        try {
            val minBuf = AudioRecord.getMinBufferSize(
                48000,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            out["micSupports48kHz"] = minBuf > 0
        } catch (_: Exception) {
            out["micSupports48kHz"] = false
        }

        // Speaker high-freq capability cannot be reliably probed from
        // SDK metadata; advertise `null` so Dart records "unknown".
        out["speakerSupportsHighFreq"] = null

        // Charging state. Battery service surfaces this without
        // requiring permissions. Conservative default is false.
        try {
            val intent = registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            )
            val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
            out["charging"] = charging
        } catch (_: Exception) {
            out["charging"] = false
        }

        // Free internal storage in megabytes. -1 sentinel on failure.
        try {
            val stat = StatFs(filesDir.absolutePath)
            val bytes = stat.availableBlocksLong * stat.blockSizeLong
            out["freeStorageMb"] = (bytes / (1024L * 1024L)).toInt()
        } catch (_: Exception) {
            out["freeStorageMb"] = -1
        }

        return out
    }

    private fun readNetworkContext(): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            @Suppress("DEPRECATION")
            val info = wifi?.connectionInfo
            if (info != null) {
                val rawSsid = info.ssid?.trim('"')
                if (!rawSsid.isNullOrBlank() && rawSsid != "<unknown ssid>") {
                    out["wifiSsid"] = rawSsid
                }
                val bssid = info.bssid
                if (!bssid.isNullOrBlank() && bssid != "02:00:00:00:00:00") {
                    out["wifiBssid"] = bssid
                }
            }
        } catch (_: Exception) {
        }
        try {
            val fineGranted = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            val coarseGranted = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            if (fineGranted || coarseGranted) {
                val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                if (tm != null) {
                    val cellList: List<CellInfo>? = try {
                        tm.allCellInfo
                    } catch (_: SecurityException) {
                        null
                    }
                    if (!cellList.isNullOrEmpty()) {
                        val registered = cellList.firstOrNull { it.isRegistered } ?: cellList.first()
                        val cellLabel = describeCellInfo(registered)
                        if (!cellLabel.isNullOrBlank()) {
                            out["cellId"] = cellLabel
                        }
                    }
                    val operator = tm.networkOperatorName
                    if (!operator.isNullOrBlank()) {
                        out["carrier"] = operator
                    }
                }
            }
        } catch (_: Exception) {
        }
        return out
    }

    private fun describeCellInfo(info: CellInfo): String? {
        return try {
            when (info) {
                is CellInfoLte -> {
                    val id = info.cellIdentity
                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mccString else id.mcc.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mncString else id.mnc.toString()
                    "LTE/${mcc ?: "?"}-${mnc ?: "?"}/tac=${id.tac}/ci=${id.ci}"
                }
                is CellInfoGsm -> {
                    val id = info.cellIdentity
                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mccString else id.mcc.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mncString else id.mnc.toString()
                    "GSM/${mcc ?: "?"}-${mnc ?: "?"}/lac=${id.lac}/cid=${id.cid}"
                }
                is CellInfoWcdma -> {
                    val id = info.cellIdentity
                    val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mccString else id.mcc.toString()
                    val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mncString else id.mnc.toString()
                    "WCDMA/${mcc ?: "?"}-${mnc ?: "?"}/lac=${id.lac}/cid=${id.cid}"
                }
                is CellInfoCdma -> {
                    val id = info.cellIdentity
                    "CDMA/sid=${id.systemId}/nid=${id.networkId}/bid=${id.basestationId}"
                }
                else -> null
            }
        } catch (_: Exception) {
            null
        }
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
