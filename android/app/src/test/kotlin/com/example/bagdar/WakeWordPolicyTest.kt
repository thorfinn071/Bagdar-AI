package com.example.bagdar

import org.junit.Assert.*
import org.junit.Test

class WakeWordPolicyTest {
    @Test fun rollingPcmPreservesLatestSamplesAfterLongSilenceAndClearsBetweenUtterances() {
        val buffer = WakePcmBuffer(4)
        repeat(10) { buffer.append(shortArrayOf(0, 0, 0), 3) }
        buffer.append(shortArrayOf(0x1234, -2, 123), 2)
        assertArrayEquals(byteArrayOf(0, 0, 0, 0, 0x34, 0x12, -2, -1), buffer.pcm16Bytes())
        buffer.clear()
        assertArrayEquals(byteArrayOf(), buffer.pcm16Bytes())
        buffer.append(shortArrayOf(42), 1)
        assertArrayEquals(byteArrayOf(42, 0), buffer.pcm16Bytes())
    }
    private fun accepts(text: String = "бағдар", count: Int = 1, word: String = "бағдар",
                        confidence: Double = 0.9, start: Double = 0.0, end: Double = 0.8) =
        WakeWordPolicy.accepts(text, count, word, confidence, start, end)

    @Test fun exactWordAndUnknownRemainDistinct() {
        assertTrue(accepts())
        listOf("", "[unk]", "багдар", "не бағдар", "бағдар [unk]", "бағдар бағдар").forEach { assertFalse(accepts(text = it)) }
        assertFalse(accepts(count = 0))
        assertFalse(accepts(count = 2))
        assertFalse(accepts(word = "[unk]"))
    }
    @Test fun invalidAndUncalibratedScoresAreRejected() {
        listOf(Double.NaN, Double.POSITIVE_INFINITY, -1.0, 0.849, 1.001).forEach { assertFalse(accepts(confidence = it)) }
        assertTrue(accepts(confidence = 0.85))
        assertTrue(accepts(confidence = 1.0))
    }
    @Test fun wordDurationMustBeFiniteAndBounded() {
        listOf(Double.NaN, Double.POSITIVE_INFINITY, 0.249, 2.001, -0.1).forEach { assertFalse(accepts(end = it)) }
        assertFalse(accepts(start = -0.1))
        assertTrue(accepts(end = 0.25))
        assertTrue(accepts(end = 2.0))
    }
    @Test fun captureOwnerCannotBeReplacedOrReleasedByAnotherInput() {
        val gate = VoiceCaptureGate()
        val detector = Any()
        val asr = Any()
        assertTrue(gate.acquire(detector))
        assertFalse(gate.acquire(asr))
        gate.release(asr)
        assertFalse(gate.acquire(asr))
        gate.release(detector)
        assertTrue(gate.acquire(asr))
        gate.release(detector)
        assertFalse(gate.acquire(Any()))
        gate.release(asr)
        assertTrue(gate.acquire(Any()))
    }
}
