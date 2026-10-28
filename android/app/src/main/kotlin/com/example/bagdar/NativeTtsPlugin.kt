package com.example.bagdar

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** One active synthesis + one newest pending; cancellation belongs to a request. */
class NativeTtsPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val espeak = EspeakNgEngine(context)
    private val rhvoice = RhvoiceEngine(context)
    private val gate = SpeechRequestGate()
    private val playbackLock = Any()
    private val engineLock = ReentrantLock()
    private val worker = ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS,
        ArrayBlockingQueue<Runnable>(1), { task ->
            Thread(task, "BagdarNativeTts").apply { isDaemon = true }
        })
    private var activeEngine: String? = null
    private var eventSink: EventChannel.EventSink? = null
    private var audioTrack: AudioTrack? = null

    fun register(methodChannel: MethodChannel, eventChannel: EventChannel) {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
            override fun onCancel(arguments: Any?) { eventSink = null; stopPlaybackInternal() }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availableEngines" -> try {
                if (!engineLock.tryLock()) {
                    result.error("SYNTH_BUSY", "Probe after synthesis settles", null); return
                }
                try {
                result.success(listOf(
                    rhvoice.probe(call.argument<String>("rhvoicePackPath") ?: "").toMap(),
                    espeak.probe().toMap()))
                } finally { engineLock.unlock() }
            } catch (e: Exception) { result.error("PROBE_FAILED", e.message, null) }
            "setEngine" -> {
                if (!engineLock.tryLock()) { result.success(false); return }
                try {
                val engine = call.argument<String>("engine") ?: ""
                val ok = when (engine) {
                    "rhvoice" -> rhvoice.activate(call.argument<String>("packPath") ?: "")
                    "espeak" -> espeak.activate()
                    else -> false
                }
                if (ok) activeEngine = engine
                result.success(ok)
                } finally { engineLock.unlock() }
            }
            "speak" -> handleSpeak(call, result)
            "stop" -> { stopPlaybackInternal(); result.success(null) }
            "pause", "resume" -> try {
                synchronized(playbackLock) {
                    if (call.method == "pause") audioTrack?.pause() else audioTrack?.play()
                }
                result.success(null)
            } catch (e: Exception) { result.error("PLAYBACK_STATE_FAILED", e.message, null) }
            else -> result.notImplemented()
        }
    }

    private fun handleSpeak(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("requestId")
        val text = call.argument<String>("text") ?: ""
        val engine = activeEngine
        if (id.isNullOrEmpty() || id.length > 96 || text.isEmpty() || engine == null || worker.isShutdown) {
            result.success(false); return
        }
        val rate = (call.argument<Number>("rate") ?: 0.5).toFloat()
        val volume = (call.argument<Number>("volume") ?: 1.0).toFloat()
        stopPlaybackInternal()
        val request = synchronized(playbackLock) { gate.begin(id) }
        try {
            worker.execute {
                try {
                    if (!gate.owns(request)) return@execute
                    val pcm = engineLock.withLock { when (engine) {
                        "rhvoice" -> rhvoice.synthesize(text, rate)
                        "espeak" -> espeak.synthesize(text, rate)
                        else -> null
                    } }
                    if (!gate.owns(request)) return@execute
                    if (pcm == null || pcm.samples.isEmpty()) throw IllegalStateException("synth_unavailable")
                    if (playPcm(request, pcm, volume)) emitEvent("complete", request)
                } catch (e: Exception) {
                    if (gate.owns(request)) emitEvent("error", request, e.message ?: "exception")
                }
            }
            result.success(true)
        } catch (e: Exception) {
            request.cancelled.set(true)
            result.success(false)
        }
    }

    private fun stopPlaybackInternal() {
        synchronized(playbackLock) {
            gate.cancel()
            worker.queue.clear()
            val track = audioTrack
            audioTrack = null
            try { track?.pause(); track?.flush(); track?.stop() } catch (_: Exception) {}
            // Worker owns release; no UI-thread join or concurrent release
            // while AudioTrack.write is unwinding.
        }
    }

    fun dispose() {
        stopPlaybackInternal()
        worker.shutdownNow()
        eventSink = null
    }

    private fun playPcm(request: SpeechRequestGate.Request, pcm: PcmBuffer, volume: Float): Boolean {
        val sampleRate = pcm.sampleRateHz
        val minBuffer = AudioTrack.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT)
        if (minBuffer <= 0) throw IllegalStateException("audio_track_min_buffer_failed")
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
            .setBufferSizeInBytes(minBuffer * 2).setTransferMode(AudioTrack.MODE_STREAM).build()
        try {
            synchronized(playbackLock) {
                if (!gate.owns(request)) return false
                audioTrack = track
                track.setVolume(volume.coerceIn(0f, 1f))
                track.play()
            }
            var offset = 0
            val chunkSize = (sampleRate / 50).coerceAtLeast(160)
            while (offset < pcm.samples.size && gate.owns(request)) {
                val written = track.write(pcm.samples, offset, minOf(chunkSize, pcm.samples.size - offset))
                if (written <= 0) throw IllegalStateException("audio_track_write_failed_$written")
                if (offset == 0) emitEvent("start", request)
                offset += written
            }
            if (!gate.owns(request)) return false
            // Write completion means buffering; wait for the playback head.
            val drainDeadline = SystemClock.elapsedRealtime() + pcm.samples.size * 1000L / sampleRate + 1000L
            while (gate.owns(request) && track.playbackHeadPosition.toLong() < pcm.samples.size) {
                if (SystemClock.elapsedRealtime() > drainDeadline) throw IllegalStateException("audio_track_drain_timeout")
                Thread.sleep(5)
            }
            return gate.owns(request)
        } finally {
            synchronized(playbackLock) {
                if (audioTrack === track) audioTrack = null
                try { track.stop() } catch (_: Exception) {}
                try { track.release() } catch (_: Exception) {}
            }
        }
    }

    private fun emitEvent(type: String, request: SpeechRequestGate.Request, reason: String? = null) {
        val payload = mapOf("type" to type, "requestId" to request.id, "reason" to reason,
            "atElapsedRealtimeUs" to SystemClock.elapsedRealtimeNanos() / 1000,
            "milestone" to if (type == "start") "pcm_submitted" else type)
        mainHandler.post { if (gate.owns(request)) eventSink?.success(payload) }
    }
}
