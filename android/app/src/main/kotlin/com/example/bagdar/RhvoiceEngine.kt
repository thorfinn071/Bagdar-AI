package com.example.bagdar

import android.content.Context
import android.util.Log
import java.io.File

/**
 * JNI wrapper around the RHVoice synthesizer. The library is shipped
 * out-of-band via the `rhvoice-kk-aigul` language pack downloaded by
 * `LanguagePackManager` — it is NOT bundled in the APK so the install
 * footprint stays under the budget set in
 * `plans/bagdar-kazakh-language-stack-1f2668.md`.
 *
 * Pack layout (after extraction by `LanguagePackManager`):
 *
 *   <packDir>/
 *     lib/{abi}/librhvoice.so      ← dynamically loaded at probe time
 *     voice/aigul/                 ← voice + dictionary data (CC-BY-3.0)
 *     LICENSE.txt                  ← LGPL-2.1 + CC-BY-3.0 notices
 *
 * The engine refuses to activate without all three pieces. When the
 * pack is missing, [probe] reports `available = false`, and the
 * Dart-side resolver in `TtsService._resolveKkEngine()` falls through
 * to espeak-ng (or russianFallback if espeak-ng is also unavailable).
 */
class RhvoiceEngine(@Suppress("UNUSED_PARAMETER") context: Context) {
    companion object {
        private const val TAG = "RhvoiceEngine"
        private const val ENGINE_ID = "rhvoice"
        private const val LIB_FILE = "librhvoice.so"
        private const val VOICE_REL_PATH = "voice"
        private const val LICENSE_FILE = "LICENSE.txt"
        private const val DEFAULT_SAMPLE_RATE = 24000
    }

    @Volatile private var nativeLibLoaded: Boolean = false
    @Volatile private var nativeLibPath: String = ""
    @Volatile private var voicePath: String = ""
    @Volatile private var activated: Boolean = false

    fun probe(packPath: String): EngineCapability {
        if (packPath.isEmpty()) {
            return EngineCapability(
                engine = ENGINE_ID,
                available = false,
                unavailableReason = "pack_not_installed",
            )
        }
        val packDir = File(packPath)
        if (!packDir.exists() || !packDir.isDirectory) {
            return EngineCapability(
                engine = ENGINE_ID,
                available = false,
                unavailableReason = "pack_dir_missing",
            )
        }

        val libFile = findLib(packDir)
        if (libFile == null || !libFile.exists()) {
            return EngineCapability(
                engine = ENGINE_ID,
                available = false,
                unavailableReason = "lib_missing",
            )
        }
        nativeLibPath = libFile.absolutePath

        val voiceDir = File(packDir, VOICE_REL_PATH)
        if (!voiceDir.exists() || !voiceDir.isDirectory) {
            return EngineCapability(
                engine = ENGINE_ID,
                available = false,
                unavailableReason = "voice_data_missing",
            )
        }
        voicePath = voiceDir.absolutePath

        val licenseOk = File(packDir, LICENSE_FILE).exists()
        if (!licenseOk) {
            // The plan locks in LGPL/CC-BY redistribution — refuse to
            // activate without the bundled notice file so the build
            // never ships without the required attribution.
            Log.w(TAG, "LICENSE.txt missing from RHVoice pack — refusing to activate")
            return EngineCapability(
                engine = ENGINE_ID,
                available = false,
                unavailableReason = "license_missing",
            )
        }

        return EngineCapability(
            engine = ENGINE_ID,
            available = true,
            version = packVersion(packDir),
            supportedLanguages = listOf("kk"),
            unavailableReason = "",
        )
    }

    fun activate(packPath: String): Boolean {
        if (activated) return true
        val cap = probe(packPath)
        if (!cap.available) return false
        return try {
            System.load(nativeLibPath)
            nativeLibLoaded = true
            val rc = nativeInit(voicePath)
            activated = (rc == 0)
            if (!activated) {
                Log.w(TAG, "nativeInit returned $rc — RHVoice load failed")
            }
            activated
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "System.load($nativeLibPath) failed: ${e.message}")
            false
        } catch (e: Throwable) {
            Log.w(TAG, "RHVoice activate failed: ${e.message}")
            false
        }
    }

    fun synthesize(text: String, rate: Float): PcmBuffer? {
        if (!activated || text.isEmpty()) return null
        return try {
            val pcm = nativeSynth(text, rate.coerceIn(0.2f, 1.5f)) ?: return null
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

    /** Pick the lib that matches the device ABI; falls back to the first one found. */
    private fun findLib(packDir: File): File? {
        val abis = listOf("arm64-v8a", "armeabi-v7a")
        for (abi in abis) {
            val candidate = File(packDir, "lib/$abi/$LIB_FILE")
            if (candidate.exists()) return candidate
        }
        // Some packs ship the lib at the top level (legacy layout).
        val flat = File(packDir, LIB_FILE)
        if (flat.exists()) return flat
        return null
    }

    private fun packVersion(packDir: File): String {
        val versionFile = File(packDir, "VERSION.txt")
        if (!versionFile.exists()) return ""
        return try {
            versionFile.readText().trim()
        } catch (_: Throwable) {
            ""
        }
    }

    // -- JNI surface ----------------------------------------------------------
    //
    // Implemented by `librhvoice.so` shipped inside the pack. Signatures
    // mirror the official RHVoice C API (`RHVoice_new_tts_engine`,
    // `RHVoice_speak_generic_*`). Until the pack is built and signed,
    // these methods throw `UnsatisfiedLinkError` and the wrapper above
    // reports `available = false` accordingly.

    private external fun nativeInit(voicePath: String): Int

    private external fun nativeSynth(text: String, rate: Float): ByteArray?
}
