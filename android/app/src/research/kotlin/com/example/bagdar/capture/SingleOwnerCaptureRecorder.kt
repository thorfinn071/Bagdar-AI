package com.example.bagdar.capture

import android.app.Activity
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.Image
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import com.google.ar.core.Config
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.NotYetAvailableException
import com.google.ar.core.exceptions.NotTrackingException
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Capture/export only. All ARCore, GL, Image and disk ownership is on one worker. */
internal class SingleOwnerCaptureRecorder(
    private val activity: Activity,
    private val notify: (String, Boolean) -> Unit,
) {
    private val stopping = AtomicBoolean(false)
    private val worker = HandlerThread("bagdar-research-capture")
    private lateinit var handler: Handler
    private var session: Session? = null
    private var gl: CaptureGlContext? = null
    private var folder: File? = null
    private var manifest: JSONObject? = null
    private var count = 0
    private var bytesWritten = 0L
    private var duplicates = 0
    private var lastFrameNs = 0L
    private var lastSampleElapsedNs = 0L
    private var startElapsedNs = 0L
    @Volatile private var stopReason = "user_stop"
    private var finished = false

    fun start() {
        worker.start()
        handler = Handler(worker.looper)
        handler.post {
            try {
                startElapsedNs = SystemClock.elapsedRealtimeNanos()
                val id = "capture-${UUID.randomUUID()}"
                val root = File(activity.filesDir, "research-captures")
                check(root.exists() || root.mkdirs())
                folder = File(root, id).also { check(it.mkdir()) }
                manifest = JSONObject().apply {
                    put("schemaVersion", 1)
                    put("format", "bagdar-native-capture-v1")
                    put("recordingId", id)
                    put("source", "recorded")
                    put("consentConfirmed", true)
                    put("createdAtUtc", Instant.now().toString())
                    put("deviceModel", "${Build.MANUFACTURER} ${Build.MODEL}")
                    put("androidVersion", Build.VERSION.RELEASE)
                    put("androidApi", Build.VERSION.SDK_INT)
                    put("cameraOwner", "native_arcore_only")
                    put("flutterEngineCreated", false)
                    put("depthMode", "RAW_DEPTH_ONLY")
                    put("sourceTimestampDomain", "arcore_camera_ns_unverified")
                    put("receiveTimestampDomain", "elapsedRealtimeNs")
                    put("clockBindingValidated", false)
                    put("physicalAlignmentValidated", false)
                    put("metricErrorBoundsValidated", false)
                    put("floorReferenceValidated", false)
                    put("bodyVolumeCoverageEstablished", false)
                    put("promotionAllowed", false)
                    put("ordinaryCameraWired", false)
                    put("captureToDecisionAvailable", false)
                    put("maxFrames", MAX_FRAMES)
                    put("maxDurationNs", MAX_DURATION_NS)
                    put("maxPayloadBytes", MAX_BYTES)
                    put("sampleIntervalNs", SAMPLE_INTERVAL_NS)
                    put("startedElapsedNs", startElapsedNs)
                }
                File(folder, "frames.jsonl").writeText("")
                // Pending metadata survives a failure before camera initialization.
                writeJson(File(folder, "pending.json"), checkNotNull(manifest))
                if (stopping.get()) { finish(stopReason, false); return@post }
                val next = Session(activity)
                session = next
                check(next.isDepthModeSupported(Config.DepthMode.RAW_DEPTH_ONLY)) {
                    "RAW_DEPTH_ONLY unavailable on this device"
                }
                next.configure(Config(next).apply {
                    depthMode = Config.DepthMode.RAW_DEPTH_ONLY
                    updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    focusMode = Config.FocusMode.AUTO
                    planeFindingMode = Config.PlaneFindingMode.DISABLED
                    lightEstimationMode = Config.LightEstimationMode.DISABLED
                    cloudAnchorMode = Config.CloudAnchorMode.DISABLED
                    geospatialMode = Config.GeospatialMode.DISABLED
                })
                val cameraId = next.cameraConfig.cameraId
                val characteristics = activity.getSystemService(CameraManager::class.java)
                    .getCameraCharacteristics(cameraId)
                manifest!!.put("rgbCameraId", cameraId)
                manifest!!.put("sensorOrientationDeg", characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION))
                manifest!!.put("camera2TimestampSource", when (characteristics.get(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE)) {
                    CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME -> "REALTIME"
                    else -> "UNKNOWN"
                })
                val context = CaptureGlContext()
                gl = context
                context.initialize()
                next.setCameraTextureName(context.textureId)
                next.setDisplayGeometry(0, 640, 480)
                if (stopping.get()) { finish(stopReason, false); return@post }
                next.resume()
                writeJson(File(folder, "pending.json"), checkNotNull(manifest))
                notify("Запись началась. Стойте на месте; максимум 30 кадров / 10 секунд.", false)
                handler.post(tick)
            } catch (error: Exception) {
                finish("initialization_error:${error.javaClass.simpleName}", true)
            }
        }
    }

    fun stop(reason: String) {
        if (stopping.compareAndSet(false, true)) stopReason = reason
        if (::handler.isInitialized) handler.post { finish(stopReason, false) }
    }

    private val tick = object : Runnable {
        override fun run() {
            if (finished) return
            if (stopping.get()) { finish(stopReason, false); return }
            if (SystemClock.elapsedRealtimeNanos() - startElapsedNs >= MAX_DURATION_NS || count >= MAX_FRAMES) {
                finish("recording_limit", false)
                return
            }
            try {
                val frame = checkNotNull(session).update()
                val receiveNs = SystemClock.elapsedRealtimeNanos()
                // Cancellation may have arrived while a native update was in flight.
                if (stopping.get()) { finish(stopReason, false); return }
                if (receiveNs - startElapsedNs >= MAX_DURATION_NS) {
                    finish("recording_limit", false)
                    return
                }
                check(frame.timestamp >= lastFrameNs) { "source clock moved backwards" }
                if (frame.timestamp > 0 && receiveNs - lastSampleElapsedNs >= SAMPLE_INTERVAL_NS) {
                    if (frame.timestamp > lastFrameNs) {
                        record(frame, receiveNs)
                        lastFrameNs = frame.timestamp
                        lastSampleElapsedNs = receiveNs
                    } else {
                        duplicates++
                    }
                }
                handler.postDelayed(this, 33)
            } catch (error: PayloadLimitException) {
                finish("payload_limit", true)
            } catch (error: Exception) {
                finish("capture_error:${error.javaClass.simpleName}", true)
            }
        }
    }

    private fun record(frame: Frame, receiveNs: Long) {
        val camera = frame.camera
        val intrinsics = camera.imageIntrinsics
        val dimensions = intrinsics.imageDimensions
        val row = JSONObject().apply {
            put("frameIndex", count)
            put("sessionGeneration", 1)
            put("frameId", count + 1)
            put("frameTimestampNs", frame.timestamp)
            put("receivedElapsedNs", receiveNs)
            put("trackingState", camera.trackingState.name)
            put("trackingFailureReason", camera.trackingFailureReason.name)
            put("cameraPose", JSONObject().apply {
                put("translationM", JSONArray(camera.pose.translation.toList()))
                put("rotationQuaternionXyzw", JSONArray(camera.pose.rotationQuaternion.toList()))
                put("convention", "arcore_world_right_up_negative_z_forward")
            })
            put("imageIntrinsics", intrinsicsJson(camera.imageIntrinsics))
            put("textureIntrinsics", intrinsicsJson(camera.textureIntrinsics))
            put("imageToTextureGrid", imageToTextureGrid(frame, dimensions[0], dimensions[1]))
        }
        var rgb: Image? = null
        var depth: Image? = null
        var confidence: Image? = null
        try {
            try { rgb = frame.acquireCameraImage() } catch (_: NotYetAvailableException) { }
            try { depth = frame.acquireRawDepthImage16Bits() }
            catch (_: NotYetAvailableException) { } catch (_: NotTrackingException) { }
            try { confidence = frame.acquireRawDepthConfidenceImage() }
            catch (_: NotYetAvailableException) { } catch (_: NotTrackingException) { }
            row.put("rgb", rgb?.let { imageJson(it, "rgb", 1) } ?: JSONObject.NULL)
            row.put("rawDepth", depth?.let { imageJson(it, "depth", 2) } ?: JSONObject.NULL)
            row.put("confidence", confidence?.let { imageJson(it, "confidence", 1) } ?: JSONObject.NULL)
            val reasons = CapturePairContract.reasons(
                frame.timestamp, rgb?.timestamp, depth?.timestamp, confidence?.timestamp,
                camera.trackingState == TrackingState.TRACKING,
                rgb != null && rgb.width == dimensions[0] && rgb.height == dimensions[1],
                depth != null && confidence != null && depth.width == confidence.width && depth.height == confidence.height,
            )
            row.put("pairStatus", if (reasons.isEmpty()) "same_frame_candidate" else "unavailable")
            row.put("pairReasons", JSONArray(reasons))
        } finally {
            rgb?.close()
            depth?.close()
            confidence?.close()
        }
        // This precedes JSONL append; it is NOT capture latency or a durable-write receipt.
        row.put("payloadsReadyElapsedNs", SystemClock.elapsedRealtimeNanos())
        File(folder, "frames.jsonl").appendText(row.toString() + "\n")
        count++
        notify("Сохранено $count кадров. Данные ещё не подтверждают свободный проход.", false)
    }

    private fun imageJson(image: Image, kind: String, bytesPerPixel: Int): JSONObject {
        check(image.planes.size == if (kind == "rgb") 3 else 1)
        val planes = JSONArray()
        for ((index, plane) in image.planes.withIndex()) {
            val chroma = kind == "rgb" && index > 0
            val width = if (chroma) (image.width + 1) / 2 else image.width
            val height = if (chroma) (image.height + 1) / 2 else image.height
            check(width in 1..4096 && height in 1..4096)
            val size = width.toLong() * height * bytesPerPixel
            if (size > MAX_BYTES || bytesWritten + size > MAX_BYTES) throw PayloadLimitException()
            val packed = CapturePlanePacker.pack(plane.buffer, width, height,
                plane.rowStride, plane.pixelStride, bytesPerPixel)
            val relative = "payloads/${count.toString().padStart(4, '0')}-$kind-$index.bin"
            val target = File(folder, relative)
            check(target.parentFile!!.exists() || target.parentFile!!.mkdirs())
            check(target.createNewFile())
            target.writeBytes(packed)
            bytesWritten += size
            planes.put(JSONObject().apply {
                put("path", relative)
                put("sha256", sha(packed))
                put("byteLength", packed.size)
                put("width", width)
                put("height", height)
                put("bytesPerPixel", bytesPerPixel)
                put("sourceRowStride", plane.rowStride)
                put("sourcePixelStride", plane.pixelStride)
                put("packing", "row_major_samples_without_padding")
            })
        }
        return JSONObject().apply {
            put("timestampNs", image.timestamp)
            put("width", image.width)
            put("height", image.height)
            put("androidImageFormat", image.format)
            put("encoding", when (kind) {
                "rgb" -> "YUV_420_888_three_planes"
                "depth" -> "uint16_little_endian_camera_plane_millimetres_zero_unknown"
                else -> "uint8_confidence_zero_unknown"
            })
            put("coordinateSpace", if (kind == "rgb") "arcore_cpu_image_native" else "arcore_raw_depth_native_gpu_aspect")
            put("cropRect", JSONArray(listOf(image.cropRect.left, image.cropRect.top, image.cropRect.right, image.cropRect.bottom)))
            put("planes", planes)
        }
    }

    private fun intrinsicsJson(value: com.google.ar.core.CameraIntrinsics) = JSONObject().apply {
        put("focalLength", JSONArray(value.focalLength.toList()))
        put("principalPoint", JSONArray(value.principalPoint.toList()))
        put("imageDimensions", JSONArray(value.imageDimensions.toList()))
    }

    private fun imageToTextureGrid(frame: Frame, width: Int, height: Int): JSONObject {
        val points = floatArrayOf(0f, 0f, width / 2f, 0f, width.toFloat(), 0f,
            0f, height / 2f, width / 2f, height / 2f, width.toFloat(), height / 2f,
            0f, height.toFloat(), width / 2f, height.toFloat(), width.toFloat(), height.toFloat())
        val input = ByteBuffer.allocateDirect(points.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        input.put(points).rewind()
        val output = ByteBuffer.allocateDirect(points.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        for (i in points.indices) output.put(i, Float.NaN)
        frame.transformCoordinates2d(Coordinates2d.IMAGE_PIXELS, input, Coordinates2d.TEXTURE_NORMALIZED, output)
        return JSONObject().apply {
            put("inputImagePixels", JSONArray(points.toList()))
            put("outputTextureNormalized", JSONArray(points.indices.map { output.get(it).takeIf(Float::isFinite) ?: JSONObject.NULL }))
            put("displayRotation", 0)
            put("displayWidth", 640)
            put("displayHeight", 480)
            put("physicalAlignmentValidated", false)
        }
    }

    private fun finish(reason: String, failed: Boolean) {
        if (finished) return
        finished = true
        stopping.set(true)
        handler.removeCallbacks(tick)
        var finalReason = reason
        var finalFailed = failed
        try { session?.pause() } catch (_: Exception) { finalReason += ":pause_error"; finalFailed = true }
        try { session?.close() } catch (_: Exception) { finalReason += ":close_error"; finalFailed = true }
        session = null
        try { gl?.close() } catch (_: Exception) { finalReason += ":gl_close_error"; finalFailed = true }
        gl = null
        try {
            manifest?.apply {
                put("recordingStatus", if (finalFailed) "failed" else "complete")
                put("terminationReason", finalReason)
                put("frameCount", count)
                put("payloadBytes", bytesWritten)
                put("duplicateFrameUpdates", duplicates)
                put("stoppedElapsedNs", SystemClock.elapsedRealtimeNanos())
                val rows = File(folder, "frames.jsonl")
                put("frames", JSONObject().put("path", "frames.jsonl").put("sha256", sha(rows.readBytes())))
                writeJson(File(folder, "manifest.json"), this)
            }
            notify("Запись ${if (finalFailed) "завершилась ошибкой" else "сохранена"}: $count кадров. " +
                "Каталог: ${folder?.name ?: "не создан"}. Причина: $finalReason. Экспорт выполняется отдельно.", true)
        } catch (error: Exception) {
            notify("Ошибка сохранения: ${error.javaClass.simpleName}. Запись не подтверждена.", true)
        } finally {
            worker.quitSafely()
        }
    }

    private fun writeJson(file: File, value: JSONObject) {
        val pending = File(file.parentFile, file.name + ".tmp")
        pending.writeText(value.toString(2) + "\n")
        check(pending.renameTo(file))
    }

    private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }

    private class PayloadLimitException : Exception()

    companion object {
        private const val MAX_FRAMES = 30
        private const val MAX_DURATION_NS = 10_000_000_000L
        private const val SAMPLE_INTERVAL_NS = 200_000_000L
        private const val MAX_BYTES = 64L * 1024 * 1024
    }
}
