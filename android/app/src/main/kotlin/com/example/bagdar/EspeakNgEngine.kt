package com.example.bagdar

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * JNI wrapper around the Bagdar-bundled espeak-ng 1.51 Android port.
 *
 * The companion native lib (`libbagdar-espeakng.so`) and the kk voice
 * data (`assets/espeak-ng-data/`) are produced by
 * `tools/espeak-ng/build_android.sh` using NDK r25c at the pinned
 * upstream commit. See `tools/espeak-ng/README.md` for the
 * reproducible-build recipe.
 *
 * The class is intentionally tolerant of a missing native library:
 * [probe] reports `available = false` when the .so cannot be loaded
 * and the Dart-side resolver in `TtsService._resolveKkEngine()` will
 * pick the next engine in the fallback chain (or russianFallback if
 * none of the native engines are available).
 *
 * Lifetime:
 *   probe()      → detect lib + voice data; safe to call from any thread.
 *   activate()   → ensure the .so is loaded and the data path is
 *                  unpacked from assets to filesDir/espeak-ng-data/.
 *   synthesize() → render `text` to PCM bytes. Called on the
 *                  `BagdarNativeTts` worker thread.
 */
class EspeakNgEngine(private val context: Context) {
    companion object {
        private const val TAG = "EspeakNgEngine"
        private const val ENGINE_ID = "espeak"
        private const val ASSETS_VOICE_DIR = "espeak-ng-data"
        private const val LIB_NAME = "bagdar-espeakng"
        private const val DEFAULT_SAMPLE_RATE = 22050
    }

    @Volatile private var nativeLibLoaded: Boolean? = null
    @Volatile private var voiceDirReady: Boolean? = null
    @Volatile private var dataPath: String = ""

    fun probe(): EngineCapability {
        val libOk = ensureLibLoaded()
        val voiceOk = ensureVoiceDir()
        val available = libOk && voiceOk
        val reason = when {
            !libOk -> "lib_missing"
            !voiceOk -> "voice_data_missing"
            else -> ""
        }
        val version = if (available) {
            try {
                nativeVersion()
            } catch (e: UnsatisfiedLinkError) {
                ""
            } catch (e: Throwable) {
                ""
            }
        } else {
            ""
        }
        return EngineCapability(
            engine = ENGINE_ID,
            available = available,
            version = version,
            supportedLanguages = listOf("kk", "ru", "en"),
            unavailableReason = reason,
        )
    }

    fun activate(): Boolean {
        val libOk = ensureLibLoaded()
        val voiceOk = ensureVoiceDir()
        if (!libOk || !voiceOk) return false
        return try {
            nativeInit(dataPath) == 0
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "nativeInit unavailable: ${e.message}")
            false
        } catch (e: Throwable) {
            Log.w(TAG, "nativeInit failed: ${e.message}")
            false
        }
    }

    fun synthesize(text: String, rate: Float): PcmBuffer? {
        if (text.isEmpty()) return null
        if (!ensureLibLoaded() || !ensureVoiceDir()) return null
        return try {
            val rateWpm = (110 + (rate.coerceIn(0.2f, 1.5f) * 80f)).toInt()
                .coerceIn(80, 350)
            val pcm = nativeSynth(text, "kk", rateWpm) ?: return null
            PcmBuffer(samples = pcm, sampleRateHz = DEFAULT_SAMPLE_RATE)
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "nativeSynth unavailable: ${e.message}")
            null
        } catch (e: Throwable) {
            Log.w(TAG, "nativeSynth failed: ${e.message}")
            null
        }
    }

    // -- Internals -------------------------------------------------------------

    private fun ensureLibLoaded(): Boolean {
        nativeLibLoaded?.let { return it }
        return try {
            System.loadLibrary(LIB_NAME)
            nativeLibLoaded = true
            true
        } catch (e: UnsatisfiedLinkError) {
            // Expected when the espeak-ng build hasn't been run yet.
            // probe()/activate()/synthesize() all degrade silently.
            Log.i(TAG, "libbagdar-espeakng.so unavailable (build not run?)")
            nativeLibLoaded = false
            false
        } catch (e: Throwable) {
            Log.w(TAG, "loadLibrary failed: ${e.message}")
            nativeLibLoaded = false
            false
        }
    }

    private fun ensureVoiceDir(): Boolean {
        voiceDirReady?.let { return it }
        return try {
            val targetDir = File(context.filesDir, ASSETS_VOICE_DIR)
            if (!targetDir.exists()) targetDir.mkdirs()
            // Copy assets once; subsequent launches reuse the cached
            // unpacked tree.
            val sentinel = File(targetDir, ".installed")
            if (!sentinel.exists()) {
                copyAssetsTree(ASSETS_VOICE_DIR, targetDir)
                sentinel.writeText("ok")
            }
            // If the assets directory is empty (build not run yet), we
            // still mark voiceDirReady = false so probe() reports the
            // missing voice data.
            val hasFiles = targetDir.listFiles()?.any { it.isFile && it.length() > 0 } == true
            if (!hasFiles) {
                voiceDirReady = false
                return false
            }
            dataPath = targetDir.absolutePath
            voiceDirReady = true
            true
        } catch (e: Throwable) {
            Log.w(TAG, "ensureVoiceDir failed: ${e.message}")
            voiceDirReady = false
            false
        }
    }

    private fun copyAssetsTree(assetPath: String, destDir: File) {
        val manager = context.assets
        val entries = try {
            manager.list(assetPath) ?: emptyArray()
        } catch (e: Throwable) {
            emptyArray()
        }
        if (entries.isEmpty()) {
            // Assume `assetPath` is a single file. If `open()` fails the
            // assets bundle simply has no espeak-ng data — that's OK,
            // probe() will return available=false.
            try {
                manager.open(assetPath).use { input ->
                    FileOutputStream(File(destDir, File(assetPath).name)).use { output ->
                        input.copyTo(output)
                    }
                }
            } catch (_: Throwable) {
            }
            return
        }
        for (entry in entries) {
            val full = "$assetPath/$entry"
            val outFile = File(destDir, entry)
            val sub = try {
                manager.list(full) ?: emptyArray()
            } catch (_: Throwable) {
                emptyArray()
            }
            if (sub.isNotEmpty()) {
                outFile.mkdirs()
                copyAssetsTree(full, outFile)
            } else {
                try {
                    manager.open(full).use { input ->
                        FileOutputStream(outFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                } catch (_: Throwable) {
                }
            }
        }
    }

    // -- JNI surface ----------------------------------------------------------
    //
    // The corresponding C wrapper lives in `tools/espeak-ng/jni/` (see
    // `tools/espeak-ng/README.md`). All methods are declared external so
    // the class compiles even when libbagdar-espeakng.so is absent — the
    // first invocation throws `UnsatisfiedLinkError` and the wrapper
    // gracefully reports unavailability.

    private external fun nativeInit(dataPath: String): Int
    private external fun nativeVersion(): String
    private external fun nativeSynth(text: String, lang: String, wpm: Int): ByteArray?
}
