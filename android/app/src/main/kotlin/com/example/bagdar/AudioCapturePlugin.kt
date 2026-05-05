package com.example.bagdar

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder

class AudioCapturePlugin(private val context: Context) {
    companion object {
        private const val SAMPLE_RATE = 16000
        private const val WINDOW_SAMPLES = 16000
    }

    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    @Volatile private var running = false
    @Volatile private var paused = false
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isStereo = false
    private var actualChannels = 1
    private var bufferSizeBytes = 0

    fun setupChannels(
        methodChannel: MethodChannel,
        eventChannel: EventChannel,
    ) {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val ok = startCapture()
                    result.success(
                        mapOf(
                            "started" to ok,
                            "sampleRate" to SAMPLE_RATE,
                            "channels" to actualChannels,
                            "isStereo" to isStereo,
                        ),
                    )
                }
                "stop" -> {
                    stopCapture()
                    result.success(true)
                }
                "pause" -> {
                    paused = true
                    result.success(true)
                }
                "resume" -> {
                    paused = false
                    result.success(true)
                }
                "getConfig" -> {
                    result.success(
                        mapOf(
                            "sampleRate" to SAMPLE_RATE,
                            "channels" to actualChannels,
                            "isStereo" to isStereo,
                            "running" to running,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun hasMicPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun startCapture(): Boolean {
        if (running) return true
        if (!hasMicPermission()) return false

        val stereoConfig = AudioFormat.CHANNEL_IN_STEREO
        val monoConfig = AudioFormat.CHANNEL_IN_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT

        var minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, stereoConfig, encoding)
        isStereo = minBuf > 0
        actualChannels = if (isStereo) 2 else 1
        val channelConfig = if (isStereo) stereoConfig else monoConfig

        if (!isStereo) {
            minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, monoConfig, encoding)
        }
        if (minBuf <= 0) return false

        bufferSizeBytes = WINDOW_SAMPLES * actualChannels * 2
        val recordBufSize = maxOf(minBuf, bufferSizeBytes) * 2

        val recorder = try {
            @Suppress("MissingPermission")
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                channelConfig,
                encoding,
                recordBufSize,
            )
        } catch (e: Exception) {
            return false
        }

        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return false
        }

        audioRecord = recorder
        running = true
        paused = false

        captureThread = Thread({
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO)
            recorder.startRecording()
            val readBuf = ShortArray(WINDOW_SAMPLES * actualChannels)
            val byteBuf = ByteBuffer.allocate(bufferSizeBytes).order(ByteOrder.LITTLE_ENDIAN)

            while (running) {
                if (paused) {
                    try { Thread.sleep(100) } catch (_: InterruptedException) { break }
                    continue
                }

                var offset = 0
                val total = readBuf.size
                while (offset < total && running && !paused) {
                    val read = recorder.read(readBuf, offset, total - offset)
                    if (read > 0) {
                        offset += read
                    } else {
                        break
                    }
                }

                if (offset < total || !running) continue

                byteBuf.clear()
                for (s in readBuf) {
                    byteBuf.putShort(s)
                }

                val copy = byteBuf.array().copyOf()
                val ts = System.currentTimeMillis()

                mainHandler.post {
                    try {
                        eventSink?.success(
                            mapOf(
                                "data" to copy,
                                "timestamp" to ts,
                                "channels" to actualChannels,
                                "sampleRate" to SAMPLE_RATE,
                            ),
                        )
                    } catch (_: Exception) {}
                }
            }

            try {
                recorder.stop()
            } catch (_: Exception) {}
            recorder.release()
        }, "BagdarAudioCapture")

        captureThread?.start()
        return true
    }

    private fun stopCapture() {
        running = false
        try {
            captureThread?.join(2000)
        } catch (_: Exception) {}
        captureThread = null
        audioRecord = null
    }

    fun dispose() {
        stopCapture()
        eventSink = null
    }
}
