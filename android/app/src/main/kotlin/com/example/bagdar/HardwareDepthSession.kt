package com.example.bagdar

import android.app.Activity
import android.content.Context
import android.media.Image
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.NotYetAvailableException
import io.flutter.plugin.common.EventChannel
import java.nio.ByteOrder

class HardwareDepthSession(
    private val activity: Activity,
    private val mapSize: Int,
) {
    @Volatile
    private var eventSink: EventChannel.EventSink? = null
    @Volatile
    private var running = false
    @Volatile
    private var starting = false
    private val callbackLock = Any()
    private var pendingStartResult: ((Boolean) -> Unit)? = null

    private var session: Session? = null
    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null
    private var glContext: OffscreenGlContext? = null
    private var lastDepthTimestampNs: Long = -1

    val isRunning: Boolean
        get() = running

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun start(onResult: (Boolean) -> Unit) {
        if (running || starting) {
            activity.runOnUiThread { onResult(true) }
            return
        }
        if (!isSupported(activity)) {
            activity.runOnUiThread { onResult(false) }
            return
        }

        synchronized(callbackLock) {
            pendingStartResult = onResult
        }

        handlerThread = HandlerThread("vg-arcore-depth").also { it.start() }
        handler = Handler(handlerThread!!.looper)
        starting = true

        handler?.post {
            try {
                val arSession = Session(activity)
                if (!arSession.isDepthModeSupported(Config.DepthMode.RAW_DEPTH_ONLY)) {
                    throw IllegalStateException("RAW_DEPTH_ONLY not supported")
                }

                val offscreen = OffscreenGlContext()
                if (!offscreen.init()) {
                    throw IllegalStateException("Failed to initialize offscreen GL context")
                }

                val config = Config(arSession)
                config.depthMode = Config.DepthMode.RAW_DEPTH_ONLY
                config.focusMode = Config.FocusMode.AUTO
                config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                arSession.configure(config)
                arSession.setCameraTextureName(offscreen.textureId)
                arSession.resume()

                if (!starting) {
                    arSession.pause()
                    arSession.close()
                    offscreen.release()
                    return@post
                }

                session = arSession
                glContext = offscreen
                running = true
                starting = false
                lastDepthTimestampNs = -1
                handler?.post(frameRunnable)
                finishStartResult(true)
            } catch (t: Throwable) {
                Log.w(TAG, "ARCore depth init failed", t)
                starting = false
                stop()
                finishStartResult(false)
            }
        }
    }

    fun stop() {
        running = false
        starting = false
        finishStartResult(false)
        handler?.removeCallbacksAndMessages(null)
        handlerThread?.quitSafely()
        handlerThread = null
        handler = null

        try {
            session?.pause()
        } catch (_: Throwable) {
        }
        try {
            session?.close()
        } catch (_: Throwable) {
        }
        session = null

        try {
            glContext?.release()
        } catch (_: Throwable) {
        }
        glContext = null
        lastDepthTimestampNs = -1
    }

    private fun finishStartResult(started: Boolean) {
        val callback = synchronized(callbackLock) {
            val current = pendingStartResult
            pendingStartResult = null
            current
        }
        callback ?: return
        activity.runOnUiThread {
            callback(started)
        }
    }

    private val frameRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            try {
                val frame = session?.update() ?: return
                val depthImage = tryAcquireDepthImage(frame)
                if (depthImage != null) {
                    try {
                        val timestampNs = depthImage.timestamp
                        if (timestampNs != lastDepthTimestampNs) {
                            lastDepthTimestampNs = timestampNs
                            emitDepthFrame(normalizeDepthImage(depthImage))
                        }
                    } finally {
                        depthImage.close()
                    }
                }
            } catch (e: CameraNotAvailableException) {
                Log.w(TAG, "ARCore camera unavailable", e)
                stop()
                return
            } catch (e: Throwable) {
                Log.w(TAG, "ARCore depth frame error", e)
            } finally {
                if (running) {
                    handler?.postDelayed(this, FRAME_INTERVAL_MS)
                }
            }
        }
    }

    private fun tryAcquireDepthImage(frame: com.google.ar.core.Frame): Image? {
        return try {
            frame.acquireRawDepthImage16Bits()
        } catch (_: NotYetAvailableException) {
            null
        } catch (_: Throwable) {
            null
        }
    }

    private fun normalizeDepthImage(depthImage: Image): ByteArray {
        val plane = depthImage.planes[0]
        val buffer = plane.buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        buffer.rewind()
        val depthBuffer = buffer.asShortBuffer()
        val srcWidth = depthImage.width
        val srcHeight = depthImage.height
        val rowStrideShort = plane.rowStride / 2
        val values = FloatArray(mapSize * mapSize)

        for (y in 0 until mapSize) {
            val srcY = ((y.toFloat() / mapSize.toFloat()) * (srcHeight - 1))
                .toInt()
                .coerceIn(0, srcHeight - 1)
            val rowBase = srcY * rowStrideShort
            for (x in 0 until mapSize) {
                val srcX = ((x.toFloat() / mapSize.toFloat()) * (srcWidth - 1))
                    .toInt()
                    .coerceIn(0, srcWidth - 1)
                val depthMm = depthBuffer.get(rowBase + srcX).toInt() and 0xFFFF
                values[y * mapSize + x] = if (depthMm <= 0) 0f else depthMm / 1000f
            }
        }

        val bytes = ByteArray(values.size * 4)
        val byteBuffer = java.nio.ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        byteBuffer.asFloatBuffer().put(values)
        return bytes
    }

    private fun emitDepthFrame(bytes: ByteArray) {
        val sink = eventSink ?: return
        activity.runOnUiThread {
            sink.success(
                mapOf(
                    "values" to bytes,
                    "width" to mapSize,
                    "height" to mapSize,
                    "source" to "arcore",
                ),
            )
        }
    }

    private class OffscreenGlContext {
        var textureId: Int = 0
            private set

        private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
        private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
        private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

        fun init(): Boolean {
            eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (eglDisplay == EGL14.EGL_NO_DISPLAY) return false

            val version = IntArray(2)
            if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) return false

            val configAttribs = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_NONE,
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val numConfigs = IntArray(1)
            if (!EGL14.eglChooseConfig(
                    eglDisplay,
                    configAttribs,
                    0,
                    configs,
                    0,
                    configs.size,
                    numConfigs,
                    0,
                ) || numConfigs[0] <= 0
            ) {
                return false
            }

            val config = configs[0] ?: return false
            val contextAttribs = intArrayOf(
                EGL14.EGL_CONTEXT_CLIENT_VERSION,
                2,
                EGL14.EGL_NONE,
            )
            eglContext = EGL14.eglCreateContext(
                eglDisplay,
                config,
                EGL14.EGL_NO_CONTEXT,
                contextAttribs,
                0,
            )
            if (eglContext == EGL14.EGL_NO_CONTEXT) return false

            val surfaceAttribs = intArrayOf(
                EGL14.EGL_WIDTH,
                1,
                EGL14.EGL_HEIGHT,
                1,
                EGL14.EGL_NONE,
            )
            eglSurface = EGL14.eglCreatePbufferSurface(
                eglDisplay,
                config,
                surfaceAttribs,
                0,
            )
            if (eglSurface == EGL14.EGL_NO_SURFACE) return false

            if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
                return false
            }

            val textureIds = IntArray(1)
            GLES20.glGenTextures(1, textureIds, 0)
            textureId = textureIds[0]
            if (textureId == 0) return false

            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
            GLES20.glTexParameteri(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_MIN_FILTER,
                GLES20.GL_LINEAR,
            )
            GLES20.glTexParameteri(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_MAG_FILTER,
                GLES20.GL_LINEAR,
            )
            GLES20.glTexParameteri(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_WRAP_S,
                GLES20.GL_CLAMP_TO_EDGE,
            )
            GLES20.glTexParameteri(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_WRAP_T,
                GLES20.GL_CLAMP_TO_EDGE,
            )
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, 0)
            return true
        }

        fun release() {
            if (eglDisplay == EGL14.EGL_NO_DISPLAY) return
            EGL14.eglMakeCurrent(
                eglDisplay,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
            if (eglSurface != EGL14.EGL_NO_SURFACE) {
                EGL14.eglDestroySurface(eglDisplay, eglSurface)
                eglSurface = EGL14.EGL_NO_SURFACE
            }
            if (eglContext != EGL14.EGL_NO_CONTEXT) {
                EGL14.eglDestroyContext(eglDisplay, eglContext)
                eglContext = EGL14.EGL_NO_CONTEXT
            }
            EGL14.eglReleaseThread()
            EGL14.eglTerminate(eglDisplay)
            eglDisplay = EGL14.EGL_NO_DISPLAY
            textureId = 0
        }
    }

    companion object {
        private const val TAG = "HardwareDepthSession"
        private const val FRAME_INTERVAL_MS = 33L

        fun isSupported(context: Context): Boolean {
            return try {
                val availability = ArCoreApk.getInstance().checkAvailability(context)
                !availability.isTransient && availability.isSupported
            } catch (e: Throwable) {
                Log.w(TAG, "ARCore availability check failed", e)
                false
            }
        }
    }
}
