package com.example.bagdar.capture

/** Structural pairing only. It grants no clock, calibration or clearance authority. */
internal object CapturePairContract {
    fun reasons(
        frameNs: Long,
        rgbNs: Long?,
        depthNs: Long?,
        confidenceNs: Long?,
        tracking: Boolean,
        intrinsicsMatch: Boolean,
        depthDimensionsMatch: Boolean,
    ): List<String> = buildList {
        if (frameNs <= 0) add("invalid_frame_timestamp")
        if (rgbNs == null) add("rgb_unavailable")
        else if (rgbNs != frameNs) add("rgb_frame_timestamp_mismatch")
        if (depthNs == null) add("raw_depth_unavailable")
        else if (depthNs != frameNs) add("depth_not_new_for_frame")
        if (confidenceNs == null) add("confidence_unavailable")
        else if (confidenceNs != depthNs) add("confidence_timestamp_mismatch")
        if (!tracking) add("pose_not_tracking")
        if (!intrinsicsMatch) add("rgb_intrinsics_dimensions_mismatch")
        if (!depthDimensionsMatch) add("depth_confidence_dimensions_mismatch")
    }
}
