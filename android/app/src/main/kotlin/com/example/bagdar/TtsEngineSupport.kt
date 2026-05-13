package com.example.bagdar

/**
 * Shared types used by [NativeTtsPlugin], [EspeakNgEngine], and
 * [RhvoiceEngine]. Kept in a dedicated file so the engines can be
 * dropped in / swapped without churning the plugin entry-point.
 */

/** Raw PCM buffer returned by a synthesis engine. */
data class PcmBuffer(
    val samples: ByteArray,
    val sampleRateHz: Int,
    val channels: Int = 1,
)

/**
 * Capability descriptor produced by [EspeakNgEngine.probe] and
 * [RhvoiceEngine.probe], serialized back to Dart via
 * `bagdar/native_tts.availableEngines`.
 */
data class EngineCapability(
    val engine: String,
    val available: Boolean,
    val version: String = "",
    val supportedLanguages: List<String> = listOf("kk"),
    val unavailableReason: String = "",
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "engine" to engine,
        "available" to available,
        "version" to version,
        "supportedLanguages" to supportedLanguages,
        "unavailableReason" to unavailableReason,
    )
}
