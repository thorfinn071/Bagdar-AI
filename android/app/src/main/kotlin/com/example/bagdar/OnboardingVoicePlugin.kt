package com.example.bagdar

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel

/** Opt-in, bounded input for onboarding. No default recognizer or audio logs. */
class OnboardingVoicePlugin(
    private val context: Context,
    private val channel: MethodChannel,
    private val captureGate: VoiceCaptureGate = VoiceCaptureGate(),
) {
    private val handler = Handler(Looper.getMainLooper())
    private var active: Request? = null
    private var unreleased: SpeechRecognizer? = null

    private class Request(
        val sessionId: Int,
        val turnId: Int,
        val result: MethodChannel.Result,
        val recognizer: SpeechRecognizer,
    ) {
        var timeout: Runnable? = null
        var ready = false
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "availability" -> result.success(availability())
                "cancel" -> {
                    if (cancel()) result.success(null)
                    else result.error("shutdown_unconfirmed", "Recognizer teardown failed", null)
                }
                "listen" -> {
                    val sessionId = call.argument<Int>("sessionId")
                    val turnId = call.argument<Int>("turnId")
                    val language = call.argument<String>("language")
                    val durationMs = call.argument<Int>("durationMs") ?: 8000
                    if (sessionId == null || turnId == null ||
                        language !in listOf("ru-RU", "kk-KZ", "en-US")) {
                        result.error("invalid_request", "Invalid voice turn", null)
                    } else {
                        listen(sessionId, turnId, language!!, durationMs, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun availability(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return "unsupported"
        return try {
            if (SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) "ready"
            else "unavailable"
        } catch (_: Exception) { "unavailable" }
    }

    private fun listen(
        sessionId: Int, turnId: Int, language: String, durationMs: Int,
        result: MethodChannel.Result,
    ) {
        if (!cancel()) {
            result.error("shutdown_unconfirmed", "Previous recognizer teardown failed", null)
            return
        }
        fun reject(outcome: String) = result.success(mapOf(
            "sessionId" to sessionId, "turnId" to turnId,
            "outcome" to outcome, "isFinal" to true,
        ))
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED) {
            reject("permissionDenied"); return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || availability() != "ready") {
            reject("unavailable"); return
        }
        if (!captureGate.acquire(this)) { reject("unavailable"); return }
        try {
            val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            val request = Request(sessionId, turnId, result, recognizer)
            active = request
            recognizer.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    if (active !== request || request.ready) return
                    // Non-speech readiness cue. Never substitutes for human feedback checks.
                    try {
                        val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 60)
                        val started = tone.startTone(ToneGenerator.TONE_PROP_BEEP, 100)
                        handler.postDelayed({
                            try { tone.release() } catch (_: Exception) {}
                        }, 200)
                        if (!started) {
                            finish(request, "unavailable"); return
                        }
                    } catch (_: Exception) {
                        finish(request, "unavailable"); return
                    }
                    request.ready = true
                    request.timeout?.let { handler.removeCallbacks(it) }
                    request.timeout = Runnable { finish(request, "noSpeech") }
                    handler.postDelayed(request.timeout!!, durationMs.coerceIn(2000, 15000).toLong())
                    channel.invokeMethod("ready", mapOf(
                        "sessionId" to sessionId, "turnId" to turnId,
                    ))
                }
                override fun onResults(results: Bundle?) {
                    if (active !== request) return
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull().orEmpty()
                    val confidence = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
                        ?.firstOrNull()?.takeIf { it.isFinite() && it >= 0f }
                    finish(request, if (request.ready && text.isNotBlank()) "recognized" else "noSpeech",
                        text, confidence)
                }
                override fun onError(error: Int) {
                    val outcome = when (error) {
                        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "noSpeech"
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permissionDenied"
                        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "languageUnavailable"
                        else -> "unavailable"
                    }
                    finish(request, outcome)
                }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            // Bound recognizer startup separately; answer time starts at readiness.
            request.timeout = Runnable { finish(request, "unavailable") }
            handler.postDelayed(request.timeout!!, 3000)
            recognizer.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            })
        } catch (_: Exception) {
            val request = active
            if (request != null) finish(request, "unavailable")
            else { captureGate.release(this); reject("unavailable") }
        }
    }

    private fun finish(request: Request, outcome: String, text: String = "", confidence: Float? = null) {
        if (active !== request) return
        active = null // Invalidate before cancel/destroy can deliver more callbacks.
        request.timeout?.let { handler.removeCallbacks(it) }
        try { request.recognizer.cancel() } catch (_: Exception) {}
        try {
            request.recognizer.destroy()
        } catch (_: Exception) {
            // Retain the failed resource for another cancellation attempt and
            // never acknowledge a successful microphone handoff to Flutter.
            unreleased = request.recognizer
            request.result.error("shutdown_unconfirmed", "Recognizer teardown failed", null)
            return
        }
        captureGate.release(this)
        request.result.success(mapOf(
            "sessionId" to request.sessionId, "turnId" to request.turnId,
            "outcome" to outcome, "text" to text, "isFinal" to true,
            "confidence" to confidence,
        ))
    }

    fun cancel(): Boolean {
        active?.let { finish(it, "cancelled") }
        unreleased?.let { recognizer ->
            try {
                recognizer.cancel()
            } catch (_: Exception) {}
            try {
                recognizer.destroy()
                unreleased = null
            } catch (_: Exception) {}
        }
        if (unreleased == null) captureGate.release(this)
        return unreleased == null
    }
    fun dispose() { cancel(); channel.setMethodCallHandler(null) }
}
