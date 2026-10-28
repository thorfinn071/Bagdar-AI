package com.example.bagdar

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Research-only local grammar detector. No SpeechRecognizer, network, PCM or transcript logs. */
class VoskWakeWordPlugin(
    private val context: Context,
    private val channel: MethodChannel,
    private val captureGate: VoiceCaptureGate,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var model: Model? = null // Accessed only by the worker.
    private var active: Capture? = null // Accessed only on the main thread.
    private var foreground = false
    private var disposed = false
    private var recordingCallbackRegistered = false

    private class Capture(val sessionId: Int, val durationMs: Int, val result: MethodChannel.Result) {
        val cancelled = AtomicBoolean(false)
        @Volatile var recorder: AudioRecord? = null
        var reason = "cancelled"
        val stopWaiters = mutableListOf<MethodChannel.Result>()
    }

    private val recordingCallback = object : AudioManager.AudioRecordingCallback() {
        override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
            val request = active ?: return
            val recorder = request.recorder ?: return
            if (configs.any { it.clientAudioSessionId == recorder.audioSessionId && it.isClientSilenced }) {
                stop("interrupted")
            }
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "availability" -> result.success(availability())
                "prepare" -> {
                    if (availability() != "ready" || !foreground || disposed || active != null) {
                        result.success("unavailable")
                    } else worker.execute {
                        val outcome = try {
                            if (model == null) model = Model(installVerifiedModel().absolutePath)
                            "ready"
                        } catch (_: Exception) { "unavailable" }
                        handler.post { result.success(if (disposed || !foreground) "unavailable" else outcome) }
                    }
                }
                "listen" -> {
                    val sessionId = call.argument<Int>("sessionId")
                    val durationMs = call.argument<Int>("durationMs")
                    if (sessionId == null || sessionId <= 0 || durationMs == null || durationMs !in 1000..300000 ||
                        call.argument<Boolean>("experimental") != true) {
                        result.error("invalid_request", "Invalid bounded wake session", null)
                    } else listen(sessionId, durationMs, result)
                }
                "cancel" -> stop("cancelled", result)
                else -> result.notImplemented()
            }
        }
    }

    private fun availability(): String {
        if (!BuildConfig.FLAVOR.equals("research", true)) return "disabled"
        return try { context.assets.open("voice_wake/manifest.json").close(); "ready" }
        catch (_: Exception) { "modelMissing" }
    }

    private fun installVerifiedModel(): File {
        val manifest = context.assets.open("voice_wake/manifest.json").bufferedReader().use { JSONObject(it.readText()) }
        require(manifest.getString("archiveSha256") == "b6d6bfe6195c866805bd18b1f56723e4d2ba4866e81df1481006d0c5704fda4f")
        require(manifest.getString("modelId") == "vosk-model-small-kz-0.42")
        val directory = File(context.noBackupFilesDir, "voice_wake/vosk-model-small-kz-0.42")
        val files = manifest.getJSONArray("files")
        require(files.length() == 14)
        val expectedPaths = mutableSetOf<String>()
        for (index in 0 until files.length()) {
            val entry = files.getJSONObject(index)
            val name = entry.getString("path")
            require(name.isNotEmpty() && !name.startsWith("/") && !name.contains("\\") && ".." !in name.split('/'))
            val target = File(directory, name)
            require(target.canonicalPath.startsWith(directory.canonicalPath + File.separator))
            require(expectedPaths.add(target.canonicalPath))
            fun valid(): Boolean = target.isFile && target.length() == entry.getLong("bytes") &&
                target.inputStream().use { stream ->
                    val digest = MessageDigest.getInstance("SHA-256")
                    val buffer = ByteArray(65536)
                    while (true) { val count = stream.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
                    digest.digest().joinToString("") { "%02x".format(it) } == entry.getString("sha256")
                }
            if (!valid()) {
                target.parentFile?.mkdirs()
                context.assets.open("voice_wake/$name").use { input -> target.outputStream().use { input.copyTo(it) } }
                require(valid())
            }
        }
        require(directory.walkTopDown().filter { it.isFile }.map { it.canonicalPath }.toSet() == expectedPaths)
        return directory
    }

    private fun listen(sessionId: Int, durationMs: Int, result: MethodChannel.Result) {
        if (disposed || !foreground || availability() != "ready" || active != null ||
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("unavailable", "Wake input unavailable", null); return
        }
        val request = Capture(sessionId, durationMs, result)
        if (!captureGate.acquire(request)) { result.error("busy", "Microphone handoff required", null); return }
        if (!recordingCallbackRegistered) {
            try {
                audio.registerAudioRecordingCallback(recordingCallback, handler)
                recordingCallbackRegistered = true
            } catch (_: Exception) {
                captureGate.release(request)
                result.error("unavailable", "Recording state monitoring unavailable", null)
                return
            }
        }
        active = request
        worker.execute { capture(request) }
    }

    private fun capture(request: Capture) {
        var outcome = "unavailable"
        var detectedAt = 0L
        var confidence = 0.0
        var wordDurationMs = 0.0
        var recognizer: Recognizer? = null
        var released = true
        try {
            val loaded = model ?: error("Prepare model first")
            recognizer = Recognizer(loaded, 16000f, "[\"бағдар\",\"[unk]\"]")
            recognizer.setWords(true)
            if (!request.cancelled.get()) {
                val minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                check(minimum > 0)
                val recorder = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minimum, 6400))
                request.recorder = recorder
                check(recorder.state == AudioRecord.STATE_INITIALIZED)
                if (!request.cancelled.get()) {
                    recorder.startRecording()
                    check(recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING)
                    val startedAt = SystemClock.elapsedRealtime()
                    handler.post {
                        if (active === request && !request.cancelled.get() && foreground && !disposed) {
                            try {
                                val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 60)
                                val played = tone.startTone(ToneGenerator.TONE_PROP_BEEP, 100)
                                handler.postDelayed({ try { tone.release() } catch (_: Exception) {} }, 200)
                                if (played) channel.invokeMethod("ready", mapOf("sessionId" to request.sessionId))
                                else stop("unavailable")
                            } catch (_: Exception) { stop("unavailable") }
                        }
                    }
                    val buffer = ShortArray(1600)
                    val segment = WakePcmBuffer()
                    while (!request.cancelled.get()) {
                        if (SystemClock.elapsedRealtime() - startedAt >= request.durationMs) { outcome = "expired"; break }
                        val count = recorder.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                        check(count > 0)
                        if (request.cancelled.get()) break
                        segment.append(buffer, count)
                        if (recognizer.acceptWaveForm(buffer, count)) {
                            val json = JSONObject(recognizer.result)
                            val words = json.optJSONArray("result")
                            val word = words?.optJSONObject(0)
                            if (word != null && WakeWordPolicy.accepts(json.optString("text"), words.length(),
                                    word.optString("word"), word.optDouble("conf"), word.optDouble("start"), word.optDouble("end")) &&
                                verify(loaded, segment.pcm16Bytes())) {
                                outcome = "detected"
                                confidence = word.getDouble("conf")
                                wordDurationMs = (word.getDouble("end") - word.getDouble("start")) * 1000
                                detectedAt = SystemClock.elapsedRealtime()
                                break
                            }
                            segment.clear()
                        }
                    }
                }
            }
        } catch (_: Exception) { outcome = "unavailable" }
        finally {
            // No capture or recognizer may outlive the teardown acknowledgement.
            try { request.recorder?.stop() } catch (_: Exception) {}
            try { request.recorder?.release(); request.recorder = null } catch (_: Exception) { released = false }
            try { recognizer?.close() } catch (_: Exception) { released = false }
            val finalOutcome = outcome
            val finalReleased = released
            handler.post {
                if (finalReleased) captureGate.release(request)
                if (active === request && finalReleased) active = null
                if (!finalReleased) {
                    request.result.error("shutdown_unconfirmed", "Wake teardown failed", null)
                    request.stopWaiters.forEach { it.error("shutdown_unconfirmed", "Wake teardown failed", null) }
                } else {
                    request.result.success(mapOf(
                        "sessionId" to request.sessionId,
                        "outcome" to if (request.cancelled.get()) request.reason else finalOutcome,
                        "keyword" to "bagdar", "confidence" to confidence,
                        "wordDurationMs" to wordDurationMs,
                        "ageMs" to if (detectedAt == 0L) 0 else SystemClock.elapsedRealtime() - detectedAt,
                        "released" to true, "backend" to "vosk_kz_0_42",
                    ))
                    request.stopWaiters.forEach { it.success(null) }
                }
                request.stopWaiters.clear()
            }
        }
    }

    private fun verify(loaded: Model, pcm: ByteArray): Boolean {
        Recognizer(loaded, 16000f).use { verifier ->
            verifier.setWords(true)
            verifier.acceptWaveForm(pcm, pcm.size)
            val json = JSONObject(verifier.finalResult)
            val words = json.optJSONArray("result") ?: return false
            val word = words.optJSONObject(0) ?: return false
            return WakeWordPolicy.accepts(json.optString("text"), words.length(), word.optString("word"),
                word.optDouble("conf"), word.optDouble("start"), word.optDouble("end"))
        }
    }

    private fun stop(reason: String, result: MethodChannel.Result? = null) {
        val request = active
        if (request == null) { result?.success(null); return }
        request.reason = reason
        request.cancelled.set(true)
        if (result != null) request.stopWaiters.add(result)
        try { request.recorder?.stop() } catch (_: Exception) {}
        // Completion is posted by the worker only after release, never by this method.
    }

    fun resumeForeground() { foreground = true }
    fun suspend() { foreground = false; stop("interrupted") }
    fun dispose() {
        disposed = true
        suspend()
        if (recordingCallbackRegistered) {
            try { audio.unregisterAudioRecordingCallback(recordingCallback) } catch (_: Exception) {}
            recordingCallbackRegistered = false
        }
        channel.setMethodCallHandler(null)
        worker.execute { try { model?.close() } catch (_: Exception) {}; model = null }
        worker.shutdown()
    }
}
