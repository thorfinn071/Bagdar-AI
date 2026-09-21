package com.example.bagdar

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt

/// Native FMCW chirp echolocation plugin.
///
/// Phase 5 — Direction 1. Implements synchronized AudioTrack chirp
/// playback and AudioRecord capture at 48 kHz. All DSP (chirp
/// generation, cross-correlation, peak picking, confidence scoring)
/// runs natively; Dart receives only compact range estimates.
///
/// Channel: bagdar/sonar
/// Methods in  → getCapabilities(), startSonar() → Bool, stopSonar()
/// Callbacks out → onSonarCalibrated, onSonarRange({range, conf}),
///                 onSonarError(String), onSonarHeadphones, onSonarCallActive
class SonarPlugin(private val context: Context) {

    companion object {
        private const val SAMPLE_RATE = 48000
        private const val CHIRP_FREQ_LOW = 17000.0
        private const val CHIRP_FREQ_HIGH = 21500.0
        private const val CHIRP_DURATION_MS = 8
        private const val CAPTURE_WINDOW_MS = 35
        private const val CHIRP_SAMPLES = SAMPLE_RATE * CHIRP_DURATION_MS / 1000
        private const val CAPTURE_SAMPLES = SAMPLE_RATE * CAPTURE_WINDOW_MS / 1000
        private const val SPEED_OF_SOUND = 343.0
        private const val MAX_RANGE_M = 3.0
        private const val CHIRP_INTERVAL_MS = 250L
        private const val CALIBRATION_CHIRPS = 8
        private const val PROPERTY_SUPPORT_MIC_NEAR_ULTRASOUND =
            "android.media.property.SUPPORT_MIC_NEAR_ULTRASOUND"
        private const val PROPERTY_SUPPORT_SPEAKER_NEAR_ULTRASOUND =
            "android.media.property.SUPPORT_SPEAKER_NEAR_ULTRASOUND"
        private const val PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED =
            "android.media.property.SUPPORT_AUDIO_SOURCE_UNPROCESSED"

        // The existing single-peak prototype has not implemented the DSP and
        // acoustic-safety requirements below. Keep all physical chirp output
        // fail-closed until those claims are backed by a named-device report.
        private const val DSP_SAFETY_IMPLEMENTED = false
    }

    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var running = false
    private var sonarThread: Thread? = null
    private var headphoneReceiver: BroadcastReceiver? = null
    private var callStateReceiver: BroadcastReceiver? = null

    private var calibrationCount = 0
    private var calibrated = false

    private val referenceChirp: FloatArray by lazy { buildReferenceChirp() }

    fun register(channel: MethodChannel) {
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapabilities" -> result.success(readCapabilityReport())
                "startSonar" -> result.success(startSonar())
                "stopSonar" -> {
                    stopSonar()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasMicPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun propertyIsTrue(audioManager: AudioManager, name: String): Boolean =
        audioManager.getProperty(name)?.equals("true", ignoreCase = true) == true

    private fun routeFingerprint(audioManager: AudioManager, inputs: Boolean): String {
        val flag = if (inputs) AudioManager.GET_DEVICES_INPUTS else AudioManager.GET_DEVICES_OUTPUTS
        val types = try {
            audioManager.getDevices(flag)
                .map { it.type }
                .distinct()
                .sorted()
        } catch (_: Exception) {
            emptyList()
        }
        return if (types.isEmpty()) "unknown" else types.joinToString(prefix = "types:", separator = ",")
    }

    private fun readCapabilityReport(): Map<String, Any?> {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        return mapOf(
            "micNearUltrasound" to propertyIsTrue(
                audioManager,
                PROPERTY_SUPPORT_MIC_NEAR_ULTRASOUND,
            ),
            "speakerNearUltrasound" to propertyIsTrue(
                audioManager,
                PROPERTY_SUPPORT_SPEAKER_NEAR_ULTRASOUND,
            ),
            "unprocessedInput" to propertyIsTrue(
                audioManager,
                PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED,
            ),
            "sampleRateHz" to if (minBuffer > 0) SAMPLE_RATE else 0,
            "inputRoute" to routeFingerprint(audioManager, inputs = true),
            "outputRoute" to routeFingerprint(audioManager, inputs = false),
        )
    }

    private fun isHeadphonesPlugged(): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        @Suppress("DEPRECATION")
        return am.isWiredHeadsetOn || am.isBluetoothA2dpOn
    }

    private fun isCallActive(): Boolean = try {
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        tm.callState != TelephonyManager.CALL_STATE_IDLE
    } catch (_: Exception) { false }

    private fun buildReferenceChirp(): FloatArray {
        val duration = CHIRP_DURATION_MS / 1000.0
        return FloatArray(CHIRP_SAMPLES) { i ->
            val t = i.toDouble() / SAMPLE_RATE
            val phase = 2.0 * PI * (CHIRP_FREQ_LOW * t +
                (CHIRP_FREQ_HIGH - CHIRP_FREQ_LOW) / (2.0 * duration) * t * t)
            sin(phase).toFloat()
        }
    }

    private fun chirpToShorts(): ShortArray {
        val ref = referenceChirp
        return ShortArray(ref.size) { i ->
            (ref[i] * Short.MAX_VALUE * 0.80f).toInt().toShort()
        }
    }

    /// Normalized cross-correlation over echo lags. Returns (lagSamples, confidence).
    private fun findEchoLag(recorded: FloatArray, ref: FloatArray): Pair<Int, Float> {
        val maxEchoLag = (MAX_RANGE_M / SPEED_OF_SOUND * 2.0 * SAMPLE_RATE).toInt()
        val searchStart = CHIRP_SAMPLES
        val searchEnd = minOf(recorded.size - ref.size, searchStart + maxEchoLag)
        if (searchEnd <= searchStart) return Pair(0, 0f)

        var refEnergy = 0f
        for (v in ref) refEnergy += v * v
        if (refEnergy < 1e-8f) return Pair(0, 0f)

        var peakCorr = 0f
        var peakLag = searchStart

        for (lag in searchStart until searchEnd) {
            var corr = 0f
            var recEnergy = 0f
            for (k in ref.indices) {
                val rIdx = lag + k
                val rv = recorded[rIdx]
                corr += rv * ref[k]
                recEnergy += rv * rv
            }
            if (recEnergy < 1e-8f) continue
            val norm = corr / sqrt(refEnergy * recEnergy)
            if (abs(norm) > abs(peakCorr)) {
                peakCorr = norm
                peakLag = lag
            }
        }

        val echoLag = (peakLag - CHIRP_SAMPLES).coerceAtLeast(0)
        return Pair(echoLag, abs(peakCorr))
    }

    private fun startSonar(): Boolean {
        if (running) return true
        if (!hasMicPermission()) {
            sendCallback("onSonarError", "permission_denied")
            return false
        }
        if (isHeadphonesPlugged()) {
            sendCallback("onSonarError", "headphones_detected")
            return false
        }
        if (isCallActive()) {
            sendCallback("onSonarError", "call_active")
            return false
        }
        val capabilities = readCapabilityReport()
        if (capabilities["micNearUltrasound"] != true ||
            capabilities["speakerNearUltrasound"] != true ||
            capabilities["unprocessedInput"] != true ||
            (capabilities["sampleRateHz"] as? Int ?: 0) < SAMPLE_RATE ||
            capabilities["inputRoute"] == "unknown" ||
            capabilities["outputRoute"] == "unknown"
        ) {
            sendCallback("onSonarError", "capability_gate_closed")
            return false
        }
        if (!DSP_SAFETY_IMPLEMENTED) {
            sendCallback("onSonarError", "dsp_safety_gate_closed")
            return false
        }
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuf <= 0) {
            sendCallback("onSonarError", "48k_not_supported")
            return false
        }
        registerHeadphoneReceiver()
        registerCallReceiver()
        running = true
        calibrationCount = 0
        calibrated = false
        sonarThread = Thread({ runSonarLoop() }, "BagdarSonar")
        sonarThread?.start()
        return true
    }

    private fun stopSonar() {
        running = false
        try { sonarThread?.join(3000) } catch (_: Exception) {}
        sonarThread = null
        unregisterReceivers()
    }

    private fun runSonarLoop() {
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO)

        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        val recordBufSize = maxOf(minBuf * 2, CAPTURE_SAMPLES * 2)

        @Suppress("MissingPermission")
        val recorder = try {
            AudioRecord(
                MediaRecorder.AudioSource.UNPROCESSED,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                recordBufSize,
            )
        } catch (e: Exception) {
            sendCallback("onSonarError", "recorder_init: ${e.message}")
            running = false
            return
        }

        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            sendCallback("onSonarError", "recorder_not_initialized")
            running = false
            return
        }

        val playMinBuf = AudioTrack.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        val playBufSize = maxOf(playMinBuf, CHIRP_SAMPLES * 2)

        val player = try {
            @Suppress("DEPRECATION")
            AudioTrack(
                AudioManager.STREAM_MUSIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                playBufSize,
                AudioTrack.MODE_STREAM,
            )
        } catch (e: Exception) {
            recorder.release()
            sendCallback("onSonarError", "player_init: ${e.message}")
            running = false
            return
        }

        if (player.state != AudioTrack.STATE_INITIALIZED) {
            recorder.release()
            player.release()
            sendCallback("onSonarError", "player_not_initialized")
            running = false
            return
        }

        val chirpShorts = chirpToShorts()
        val captureShorts = ShortArray(CAPTURE_SAMPLES)
        val captureFloats = FloatArray(CAPTURE_SAMPLES)

        try {
            recorder.startRecording()
            player.play()

            while (running) {
                player.write(chirpShorts, 0, chirpShorts.size)

                var offset = 0
                while (offset < CAPTURE_SAMPLES && running) {
                    val read = recorder.read(captureShorts, offset, CAPTURE_SAMPLES - offset)
                    if (read > 0) offset += read else break
                }

                if (!running || offset < CAPTURE_SAMPLES / 2) break

                for (i in 0 until offset) {
                    captureFloats[i] = captureShorts[i].toFloat() / Short.MAX_VALUE
                }

                val (echoLag, confidence) = findEchoLag(captureFloats.copyOf(offset), referenceChirp)
                val rangeM = echoLag.toDouble() / SAMPLE_RATE * SPEED_OF_SOUND / 2.0

                if (!calibrated) {
                    calibrationCount++
                    if (calibrationCount >= CALIBRATION_CHIRPS) {
                        calibrated = true
                        val capabilities = readCapabilityReport()
                        sendCallbackMap(
                            "onSonarCalibrated",
                            mapOf(
                                "schemaVersion" to 1,
                                "chirpCount" to calibrationCount,
                                "sampleRateHz" to recorder.sampleRate,
                                "directPathCancellationApplied" to false,
                                "multipathPeakSelectionApplied" to false,
                                "acousticLevelValidated" to false,
                                "repeatabilityMadM" to -1.0,
                                "routeFingerprint" to
                                    "${capabilities["inputRoute"]}|${capabilities["outputRoute"]}",
                            ),
                        )
                    }
                } else if (rangeM in 0.05..MAX_RANGE_M) {
                    sendCallbackMap("onSonarRange", mapOf("range" to rangeM, "conf" to confidence.toDouble()))
                }

                try { Thread.sleep(CHIRP_INTERVAL_MS) } catch (_: InterruptedException) { break }
            }
        } catch (e: Exception) {
            sendCallback("onSonarError", e.message ?: "unknown")
        } finally {
            running = false
            try { recorder.stop() } catch (_: Exception) {}
            recorder.release()
            try { player.stop() } catch (_: Exception) {}
            player.release()
        }
    }

    private fun registerHeadphoneReceiver() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action == AudioManager.ACTION_HEADSET_PLUG) {
                    val state = intent.getIntExtra("state", 0)
                    if (state == 1) {
                        sendCallback("onSonarHeadphones", null)
                        stopSonar()
                    }
                }
            }
        }
        try {
            context.registerReceiver(receiver, IntentFilter(AudioManager.ACTION_HEADSET_PLUG))
            headphoneReceiver = receiver
        } catch (_: Exception) {}
    }

    private fun registerCallReceiver() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
                if (state != TelephonyManager.EXTRA_STATE_IDLE) {
                    sendCallback("onSonarCallActive", null)
                    stopSonar()
                }
            }
        }
        try {
            context.registerReceiver(
                receiver,
                IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED),
            )
            callStateReceiver = receiver
        } catch (_: Exception) {}
    }

    private fun unregisterReceivers() {
        try { headphoneReceiver?.let { context.unregisterReceiver(it) } } catch (_: Exception) {}
        try { callStateReceiver?.let { context.unregisterReceiver(it) } } catch (_: Exception) {}
        headphoneReceiver = null
        callStateReceiver = null
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
        stopSonar()
        methodChannel = null
    }
}
