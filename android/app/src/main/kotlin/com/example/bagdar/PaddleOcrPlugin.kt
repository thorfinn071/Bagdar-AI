package com.example.bagdar

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Phase 3 — `bagdar/paddle_ocr` MethodChannel.
 *
 * Hosts the PaddleOCR multilingual OCR pipeline used by `OcrService`
 * when `Settings.enableKazakhStackV2` is on. ru/en speech & ML Kit
 * recognition stay where they were; this plugin is *only* the OCR
 * fast-path for Cyrillic + Kazakh.
 *
 * Contract mirrors `lib/services/paddle_ocr_bridge.dart` exactly:
 *
 * | Method            | Args                                            | Returns                                       |
 * |-------------------|-------------------------------------------------|-----------------------------------------------|
 * | availableEngine   | (none)                                          | `{available, version, unavailableReason}`     |
 * | recognize         | `{yuvBytes, width, height, bytesPerRow, ...}`   | `List<{text, confidence, box}>`               |
 * | dispose           | (none)                                          | `null`                                        |
 *
 * The plugin gracefully reports `available = false` when:
 *   - PaddleLite `.aar` has not been added to `android/app/libs/`
 *   - The four model artifacts (`det.nb`, `rec_multilingual.nb`,
 *     `cls.nb`, `keys.txt`) are missing from `assets/paddle_ocr/`
 *   - Native lib load fails for any reason
 *
 * In every "unavailable" case `OcrService` transparently falls back
 * to the legacy ML Kit recognizer — Phase 3 ships dark until the
 * PaddleLite assets land in a separate ops commit.
 */
class PaddleOcrPlugin(private val context: Context) : MethodCallHandler {
    companion object {
        const val METHOD_CHANNEL = "bagdar/paddle_ocr"
    }

    private val engine = PaddleOcrEngine(context)

    fun register(methodChannel: MethodChannel) {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "availableEngine" -> handleAvailable(result)
            "recognize" -> handleRecognize(call, result)
            "dispose" -> handleDispose(result)
            else -> result.notImplemented()
        }
    }

    private fun handleAvailable(result: Result) {
        try {
            result.success(engine.probe().toMap())
        } catch (e: Exception) {
            result.error("PROBE_FAILED", e.message, null)
        }
    }

    private fun handleRecognize(call: MethodCall, result: Result) {
        val yuv = call.argument<ByteArray>("yuvBytes")
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        val bytesPerRow = call.argument<Int>("bytesPerRow") ?: width
        val rotation = call.argument<Int>("rotationDeg") ?: 90
        val languagePref = call.argument<String>("languagePref") ?: "auto"

        if (yuv == null || yuv.isEmpty() || width <= 0 || height <= 0) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }

        try {
            val lines = engine.recognize(
                yuv = yuv,
                width = width,
                height = height,
                bytesPerRow = bytesPerRow,
                rotationDeg = rotation,
                languagePref = languagePref,
            )
            result.success(lines.map { it.toMap() })
        } catch (e: OutOfMemoryError) {
            // Predictors can spike memory; surface a typed error so the
            // Dart side can log it and the resolver can pause sessions.
            engine.releasePredictors()
            result.error("OOM", e.message, null)
        } catch (e: Exception) {
            result.error("RECOGNIZE_FAILED", e.message, null)
        }
    }

    private fun handleDispose(result: Result) {
        try {
            engine.releasePredictors()
            result.success(null)
        } catch (e: Exception) {
            result.error("DISPOSE_FAILED", e.message, null)
        }
    }
}
