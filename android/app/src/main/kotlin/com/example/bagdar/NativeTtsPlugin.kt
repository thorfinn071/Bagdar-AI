package com.example.bagdar

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Phase 2 — `bagdar/native_tts` MethodChannel.
 *
 * Hosts the Kazakh-only RHVoice and espeak-ng engines. ru/en speech
 * stays on `flutter_tts` and never reaches this plugin.
 *
 * The contract mirrors `lib/services/native_tts_bridge.dart` exactly:
 *
 * | Method               | Args                                            | Returns                       |
 * |----------------------|-------------------------------------------------|-------------------------------|
 * | availableEngines     | `{rhvoicePackPath?: String}`                    | `List<Map<String, Any?>>`     |
 * | setEngine            | `{engine: String, packPath?: String}`           | `Boolean`                     |
 * | speak                | `{text, priority, rate, volume, pitch, pan}`    | `Boolean`                     |
 * | stop                 | (none)                                          | `null`                        |
 * | pause / resume       | (none)                                          | `null`                        |
 *
 * Lifecycle events (`start`, `complete`, `error`) are pushed back to
 * Dart via the `bagdar/native_tts_events` EventChannel.
 *
 * When the actual espeak-ng / RHVoice native libraries have not yet
 * been built or downloaded, the engines report `available = false`
 * during `availableEngines` and `TtsService._resolveKkEngine()`
 * transparently falls back to the Russian-voice path. This keeps the
 * Dart side honest: no fake speech is rendered when the synth is
 * missing.
 */
class NativeTtsPlugin(private val context: Context) : MethodCallHandler {
    companion object {
        private const val METHOD_CHANNEL = "bagdar/native_tts"
        private const val EVENT_CHANNEL = "bagdar/native_tts_events"

        private const val EVENT_START = "start"
        private const val EVENT_COMPLETE = "complete"
        private const val EVENT_ERROR = "error"

        // Engine ids — must match KkTtsEngine.id in Dart.
        private const val ENGINE_RHVOICE = "rhvoice"
        private const val ENGINE_ESPEAK = "espeak"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val espeak = EspeakNgEngine(context)
    private val rhvoice = RhvoiceEngine(context)

    private var activeEngine: String? = null
    private var eventSink: EventChannel.EventSink? = null

    private var audioTrack: AudioTrack? = null
    private val playing = AtomicBoolean(false)
    private val stopRequested = AtomicBoolean(false)
    private var playbackThread: Thread? = null

    fun register(methodChannel: MethodChannel, eventChannel: EventChannel) {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "availableEngines" -> handleAvailableEngines(call, result)
            "setEngine" -> handleSetEngine(call, result)
            "speak" -> handleSpeak(call, result)
            "stop" -> handleStop(result)
            "pause" -> handlePause(result)
            "resume" -> handleResume(result)
            else -> result.notImplemented()
        }
    }

    private fun handleAvailableEngines(call: MethodCall, result: Result) {
        try {
            val rhvoicePackPath = call.argument<String>("rhvoicePackPath") ?: ""
            val rhvoiceCap = rhvoice.probe(rhvoicePackPath)
            val espeakCap = espeak.probe()
            val list = listOf(rhvoiceCap.toMap(), espeakCap.toMap())
            result.success(list)
        } catch (e: Exception) {
            result.error("PROBE_FAILED", e.message, null)
        }
    }

    private fun handleSetEngine(call: MethodCall, result: Result) {
        val engine = call.argument<String>("engine") ?: ""
        val packPath = call.argument<String>("packPath") ?: ""
        when (engine) {
            ENGINE_RHVOICE -> {
                val ok = rhvoice.activate(packPath)
                if (ok) {
                    activeEngine = ENGINE_RHVOICE
                }
                result.success(ok)
            }
            ENGINE_ESPEAK -> {
                val ok = espeak.activate()
                if (ok) {
                    activeEngine = ENGINE_ESPEAK
                }
                result.success(ok)
            }
            else -> result.success(false)
        }
    }

    private fun handleSpeak(call: MethodCall, result: Result) {
        val text = call.argument<String>("text") ?: ""
        val priority = call.argument<String>("priority") ?: "info"
        val rate = (call.argument<Number>("rate") ?: 0.5).toFloat()
        val volume = (call.argument<Number>("volume") ?: 1.0).toFloat()
        @Suppress("UNUSED_VARIABLE") // pitch / pan reserved for future engines.
        val pitch = (call.argument<Number>("pitch") ?: 1.0).toFloat()
        @Suppress("UNUSED_VARIABLE")
        val pan = (call.argument<Number>("pan") ?: 0.0).toFloat()

        val engine = activeEngine
        if (engine == null) {
            result.success(false)
            return
        }
        if (text.isEmpty()) {
            result.success(false)
            return
        }

        // Stop any in-flight utterance — preempt within the 50 ms budget
        // required for critical alerts.
        stopPlaybackInternal()

        result.success(true)

        // Synthesis + playback happens off the platform thread. The
        // platform thread must return quickly so a queued critical alert
        // can immediately invoke `stop`.
        playbackThread = thread(start = true, isDaemon = true, name = "BagdarNativeTts") {
            try {
                val pcm = when (engine) {
                    ENGINE_RHVOICE -> rhvoice.synthesize(text, rate)
                    ENGINE_ESPEAK -> espeak.synthesize(text, rate)
                    else -> null
                }
                if (pcm == null || pcm.samples.isEmpty()) {
                    emitEvent(EVENT_ERROR, mapOf("reason" to "synth_unavailable"))
                    return@thread
                }
                if (stopRequested.get()) {
                    return@thread
                }
                emitEvent(EVENT_START, emptyMap())
                playPcm(pcm, volume, priority)
                if (!stopRequested.get()) {
                    emitEvent(EVENT_COMPLETE, emptyMap())
                }
            } catch (e: Exception) {
                emitEvent(EVENT_ERROR, mapOf("reason" to (e.message ?: "exception")))
            }
        }
    }

    private fun handleStop(result: Result) {
        stopPlaybackInternal()
        result.success(null)
    }

    private fun handlePause(result: Result) {
        try {
            audioTrack?.pause()
            result.success(null)
        } catch (e: Exception) {
            result.error("PAUSE_FAILED", e.message, null)
        }
    }

    private fun handleResume(result: Result) {
        try {
            audioTrack?.play()
            result.success(null)
        } catch (e: Exception) {
            result.error("RESUME_FAILED", e.message, null)
        }
    }

    private fun stopPlaybackInternal() {
        stopRequested.set(true)
        playing.set(false)
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.stop()
            audioTrack?.release()
        } catch (_: Exception) {
        }
        audioTrack = null
        // Give the synthesis/playback thread a brief window to unwind.
        // The thread checks `stopRequested` and exits at the next chunk.
        try {
            playbackThread?.join(60)
        } catch (_: InterruptedException) {
        }
        playbackThread = null
        // Reset for the next utterance.
        stopRequested.set(false)
    }

    private fun playPcm(pcm: PcmBuffer, volume: Float, priority: String) {
        // Streaming AudioTrack rendered with the same audio-attribute
        // contract `flutter_tts` uses, so audio_session focus rules apply.
        val sampleRate = pcm.sampleRateHz
        val channelMask = AudioFormat.CHANNEL_OUT_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT

        val minBuffer = AudioTrack.getMinBufferSize(sampleRate, channelMask, encoding)
        if (minBuffer <= 0) {
            emitEvent(EVENT_ERROR, mapOf("reason" to "audio_track_min_buffer_failed"))
            return
        }

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val format = AudioFormat.Builder()
            .setSampleRate(sampleRate)
            .setChannelMask(channelMask)
            .setEncoding(encoding)
            .build()

        val track = try {
            AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(format)
                .setBufferSizeInBytes(minBuffer * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } catch (e: Exception) {
            emitEvent(EVENT_ERROR, mapOf("reason" to "audio_track_build_failed"))
            return
        }
        audioTrack = track

        try {
            // Apply per-call volume; AudioManager handles ducking via the
            // audio_session config established in TtsService.init.
            track.setVolume(volume.coerceIn(0f, 1f))
        } catch (_: Exception) {
        }

        try {
            track.play()
        } catch (e: Exception) {
            emitEvent(EVENT_ERROR, mapOf("reason" to "audio_track_play_failed"))
            try {
                track.release()
            } catch (_: Exception) {
            }
            audioTrack = null
            return
        }

        playing.set(true)
        val samples = pcm.samples
        // Stream in 20 ms chunks so first-audio latency stays well under
        // 200 ms and `stop()` interrupts within the 50 ms safety budget.
        val chunkSize = (sampleRate / 50).coerceAtLeast(160)
        var offset = 0
        while (offset < samples.size && !stopRequested.get()) {
            val end = minOf(samples.size, offset + chunkSize)
            val len = end - offset
            try {
                track.write(samples, offset, len)
            } catch (e: Exception) {
                emitEvent(EVENT_ERROR, mapOf("reason" to (e.message ?: "write_failed")))
                break
            }
            offset = end
            // Cooperative cancellation — audio_track.flush() in stop()
            // will let the buffered audio drain instantly.
            if (priority == "critical") {
                // Critical alerts are never paused; pump as fast as possible.
                continue
            }
        }

        if (!stopRequested.get()) {
            try {
                // Wait for the buffered samples to drain. The native side
                // does NOT block the platform thread; this loop is on the
                // dedicated playback thread.
                track.stop()
            } catch (_: Exception) {
            }
        }
        try {
            track.release()
        } catch (_: Exception) {
        }
        if (audioTrack === track) {
            audioTrack = null
        }
        playing.set(false)
    }

    private fun emitEvent(type: String, extras: Map<String, Any?>) {
        val payload = mutableMapOf<String, Any?>("type" to type)
        payload.putAll(extras)
        mainHandler.post {
            try {
                eventSink?.success(payload)
            } catch (_: Exception) {
            }
        }
    }
}
