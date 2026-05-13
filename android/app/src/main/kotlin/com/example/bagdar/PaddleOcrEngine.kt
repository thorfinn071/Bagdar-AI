package com.example.bagdar

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * Phase 3 — PaddleLite-backed multilingual OCR engine.
 *
 * Wraps three PaddleLite predictors (`det`, `cls`, `rec_multilingual`)
 * plus a charset file (`keys.txt`) covering Latin, Cyrillic, and the
 * Kazakh extra letters (Ә Ғ Қ Ң Ө Ұ Ү Һ І). All four artifacts ship
 * inside the APK at `assets/paddle_ocr/` and are unpacked to
 * `filesDir/paddle_ocr/` on first activation.
 *
 * **Status:** Scaffold. Until the PaddleLite `.aar` lands in
 * `android/app/libs/` and the four model artifacts are added to
 * `assets/paddle_ocr/`, [probe] reports `available = false` and the
 * Dart-side resolver in `OcrService` falls back to the legacy ML Kit
 * pipeline. The contract below is the one [PaddleOcrPlugin] expects
 * so a future commit can drop in the real predictors without
 * touching the plugin or the Dart bridge.
 */
class PaddleOcrEngine(private val context: Context) {
    companion object {
        private const val TAG = "PaddleOcrEngine"
        private const val ENGINE_ID = "paddle_ocr"
        private const val ASSETS_DIR = "paddle_ocr"

        private const val DET_MODEL = "det.nb"
        private const val REC_MODEL = "rec_multilingual.nb"
        private const val CLS_MODEL = "cls.nb"
        private const val KEYS_FILE = "keys.txt"

        /// Maximum edge after preprocessing — keeps the predictor under
        /// the 800 ms/frame target on Snapdragon 680-class hardware.
        const val MAX_INPUT_EDGE_PX = 960
    }

    @Volatile private var unpacked: Boolean? = null
    @Volatile private var modelDir: String = ""

    @Volatile private var predictorsLoaded: Boolean = false

    /**
     * Probe whether the OCR engine can run on this device. Cheap +
     * idempotent — repeated calls reuse the cached result.
     */
    fun probe(): PaddleOcrCapability {
        val staged = ensureAssetsUnpacked()
        if (!staged) {
            return PaddleOcrCapability(
                available = false,
                unavailableReason = "models_missing",
            )
        }
        if (!isPaddleLiteAvailable()) {
            return PaddleOcrCapability(
                available = false,
                unavailableReason = "paddlelite_aar_missing",
            )
        }
        return PaddleOcrCapability(
            available = true,
            version = paddleLiteVersionOrEmpty(),
        )
    }

    /**
     * Run det + cls + rec on a YUV420 frame, returning ranked text lines
     * sorted by reading order. The returned list is **never** null —
     * even on engine failure we return an empty list so the Dart side
     * can fall back without an exception round-trip.
     */
    fun recognize(
        yuv: ByteArray,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        rotationDeg: Int,
        languagePref: String,
    ): List<PaddleOcrTextLine> {
        if (!probe().available) return emptyList()
        if (!ensurePredictorsLoaded()) return emptyList()

        // The actual det→cls→rec pipeline is documented inline so the
        // future commit that drops in PaddleLite only has to fill in
        // the four marked TODOs:
        //
        //   1. YUV → RGB via libyuv (ships in PaddleLite). Resize the
        //      long edge to `MAX_INPUT_EDGE_PX` keeping aspect ratio.
        //   2. det predictor → returns N axis-aligned boxes.
        //   3. cls predictor → 0°/180° rotation per box. Skip if the
        //      device is in landscape and the text appears upright
        //      (covered by `rotationDeg` heuristic).
        //   4. rec predictor → CTC-decoded text + confidence per box.
        //
        // For each box, optionally apply NMS, then sort top-to-bottom
        // / left-to-right. Apply confidence filtering on the Dart side
        // (`OcrService._kPaddleConfidenceThreshold`) so we don't double-
        // filter.

        // Unused-parameter discipline: silence warnings without
        // hand-rolling stub usage. These will be consumed by the real
        // pipeline.
        @Suppress("UNUSED_VARIABLE")
        val v1 = yuv
        @Suppress("UNUSED_VARIABLE")
        val v2 = width
        @Suppress("UNUSED_VARIABLE")
        val v3 = height
        @Suppress("UNUSED_VARIABLE")
        val v4 = bytesPerRow
        @Suppress("UNUSED_VARIABLE")
        val v5 = rotationDeg
        @Suppress("UNUSED_VARIABLE")
        val v6 = languagePref

        Log.w(TAG, "recognize: PaddleLite pipeline not yet bundled — returning empty list")
        return emptyList()
    }

    /**
     * Tear down the three predictors. Called by `OcrService.dispose()`
     * and proactively from the plugin when an OOM is observed during
     * `recognize`.
     */
    fun releasePredictors() {
        if (!predictorsLoaded) return
        try {
            // TODO: predictor.release() for det / cls / rec when
            // PaddleLite is wired in.
        } catch (e: Throwable) {
            Log.w(TAG, "releasePredictors failed: ${e.message}")
        } finally {
            predictorsLoaded = false
        }
    }

    // -- Internals ------------------------------------------------------------

    /**
     * Unpack the four bundled assets to `filesDir/paddle_ocr/` on first
     * activation. Returns `false` if the assets directory is missing
     * any of the four files (i.e. the build hasn't shipped them yet).
     */
    private fun ensureAssetsUnpacked(): Boolean {
        unpacked?.let { return it }
        return try {
            val targetDir = File(context.filesDir, "paddle_ocr")
            if (!targetDir.exists()) targetDir.mkdirs()
            val sentinel = File(targetDir, ".installed")
            val required = listOf(DET_MODEL, REC_MODEL, CLS_MODEL, KEYS_FILE)

            // Re-copy when sentinel is missing OR any required file
            // is missing (covers OTA upgrades that bumped a model).
            val needsCopy =
                !sentinel.exists() ||
                    required.any { !File(targetDir, it).exists() }
            if (needsCopy) {
                for (name in required) {
                    val ok = copyAssetIfPresent("$ASSETS_DIR/$name", File(targetDir, name))
                    if (!ok) {
                        unpacked = false
                        return false
                    }
                }
                sentinel.writeText("ok")
            }
            modelDir = targetDir.absolutePath
            unpacked = true
            true
        } catch (e: Throwable) {
            Log.w(TAG, "ensureAssetsUnpacked failed: ${e.message}")
            unpacked = false
            false
        }
    }

    private fun copyAssetIfPresent(assetPath: String, dest: File): Boolean {
        return try {
            context.assets.open(assetPath).use { input ->
                FileOutputStream(dest).use { output ->
                    input.copyTo(output)
                }
            }
            true
        } catch (_: Throwable) {
            // Asset missing — the four-file shape is part of the
            // graceful-degradation contract; absence flips probe() to
            // `available = false`.
            false
        }
    }

    /**
     * Detect whether PaddleLite's classes are linked into the app.
     * When the AAR is missing, `Class.forName` throws and the engine
     * gracefully reports `available = false`.
     */
    private fun isPaddleLiteAvailable(): Boolean {
        return try {
            // Public entry point in com.baidu.paddle.lite — present
            // when PaddleLite.aar is dropped into android/app/libs/.
            Class.forName("com.baidu.paddle.lite.PaddlePredictor")
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun paddleLiteVersionOrEmpty(): String {
        // TODO: Inspect com.baidu.paddle.lite.Version when the AAR is
        // bundled. Until then, return "" so the Dart side knows the
        // probe ran but no version info is available.
        return ""
    }

    private fun ensurePredictorsLoaded(): Boolean {
        if (predictorsLoaded) return true
        if (modelDir.isEmpty()) return false
        return try {
            // TODO: load det / cls / rec via PaddleLite.create().
            // For now, refuse to mark loaded — keeps recognize() in
            // the empty-list short-circuit until the real models are
            // dropped in.
            false
        } catch (e: Throwable) {
            Log.w(TAG, "ensurePredictorsLoaded failed: ${e.message}")
            false
        }
    }
}
