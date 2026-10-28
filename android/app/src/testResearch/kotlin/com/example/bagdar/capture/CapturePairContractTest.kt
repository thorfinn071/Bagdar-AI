package com.example.bagdar.capture

import org.junit.Assert.*
import org.junit.Test

class CapturePairContractTest {
    private fun reasons(frame: Long = 100, rgb: Long? = 100, depth: Long? = 100,
        confidence: Long? = 100, tracking: Boolean = true, intrinsics: Boolean = true,
        dimensions: Boolean = true) = CapturePairContract.reasons(frame, rgb, depth,
            confidence, tracking, intrinsics, dimensions)

    @Test fun exactPairOnlyAdmitsStructuralCandidate() { assertTrue(reasons().isEmpty()) }
    @Test fun reprojectedDepthCannotBeFreshMeasurement() {
        assertTrue(reasons(depth = 99, confidence = 99).contains("depth_not_new_for_frame"))
    }
    @Test fun futureDepthIsAlsoUnavailable() {
        assertTrue(reasons(depth = 101, confidence = 101).contains("depth_not_new_for_frame"))
    }
    @Test fun oldRgbCannotBePairedByCallbackTime() {
        assertTrue(reasons(rgb = 99).contains("rgb_frame_timestamp_mismatch"))
    }
    @Test fun missingInputsRemainExplicit() {
        val errors = reasons(rgb = null, depth = null, confidence = null)
        assertTrue(errors.containsAll(listOf("rgb_unavailable", "raw_depth_unavailable", "confidence_unavailable")))
    }
    @Test fun confidenceMustBelongToDepth() {
        assertTrue(reasons(confidence = 99).contains("confidence_timestamp_mismatch"))
    }
    @Test fun untrackedPoseCannotSupplyGeometry() {
        assertTrue(reasons(tracking = false).contains("pose_not_tracking"))
    }
    @Test fun mismatchedImageIntrinsicsCannotAdmitPair() {
        assertTrue(reasons(intrinsics = false).contains("rgb_intrinsics_dimensions_mismatch"))
    }
    @Test fun mismatchedDepthConfidenceCannotAdmitPair() {
        assertTrue(reasons(dimensions = false).contains("depth_confidence_dimensions_mismatch"))
    }
    @Test fun zeroAndNegativeClocksAreRejected() {
        assertTrue(reasons(frame = 0).contains("invalid_frame_timestamp"))
        assertTrue(reasons(frame = -1).contains("invalid_frame_timestamp"))
    }
}
