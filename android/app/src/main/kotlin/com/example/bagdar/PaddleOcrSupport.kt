package com.example.bagdar

/**
 * Shared types for the Phase 3 PaddleOCR pipeline. Kept in a dedicated
 * file so the plugin entry point and the engine implementation can
 * evolve independently of the wire shape that Dart depends on.
 *
 * The map representations match
 * `lib/services/paddle_ocr_bridge.dart::OcrTextLine` and
 * `lib/services/paddle_ocr_bridge.dart::PaddleOcrCapability`.
 */

/** One recognized line of text returned by [PaddleOcrEngine.recognize]. */
data class PaddleOcrTextLine(
    val text: String,
    val confidence: Float,
    /** Axis-aligned bounding box `[x, y, w, h]` in source-image pixels. */
    val box: IntArray = IntArray(0),
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "text" to text,
        "confidence" to confidence.toDouble(),
        "box" to box.toList(),
    )

    /*
     * Suppress equals/hashCode generation for the IntArray field.
     * Comparison is never relied on by the plugin path, and the
     * default `data class` equals would shallow-compare references.
     */
    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = System.identityHashCode(this)
}

/** Capability descriptor reported back to Dart via `availableEngine`. */
data class PaddleOcrCapability(
    val available: Boolean,
    val version: String = "",
    val unavailableReason: String = "",
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "available" to available,
        "version" to version,
        "unavailableReason" to unavailableReason,
    )
}
