package com.example.bagdar

/** One native owner until its capture teardown has completed. */
class VoiceCaptureGate {
    private var owner: Any? = null
    @Synchronized fun acquire(candidate: Any): Boolean {
        if (owner != null && owner !== candidate) return false
        owner = candidate
        return true
    }
    @Synchronized fun release(candidate: Any) {
        if (owner === candidate) owner = null
    }
}
