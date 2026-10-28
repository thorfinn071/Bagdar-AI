package com.example.bagdar

/** Provisional rejection policy, shared numerically with tool/voice_wake/policy.json. */
object WakeWordPolicy {
    fun accepts(text: String, count: Int, word: String, confidence: Double,
                start: Double, end: Double): Boolean =
        text == "бағдар" && count == 1 && word == "бағдар" &&
            confidence.isFinite() && confidence in 0.85..1.0 &&
            start.isFinite() && end.isFinite() && start >= 0 && end - start in 0.25..2.0
}
