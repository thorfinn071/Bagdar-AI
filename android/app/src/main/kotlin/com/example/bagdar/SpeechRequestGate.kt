package com.example.bagdar

import java.util.concurrent.atomic.AtomicBoolean

/** Cancellation belongs to a request; a new request can never reset it. */
class SpeechRequestGate {
    class Request(val id: String) {
        val cancelled = AtomicBoolean(false)
    }
    @Volatile private var active: Request? = null

    @Synchronized fun begin(id: String): Request {
        active?.cancelled?.set(true)
        return Request(id).also { active = it }
    }
    @Synchronized fun cancel() {
        active?.cancelled?.set(true)
        active = null
    }
    fun owns(request: Request): Boolean = active === request && !request.cancelled.get()
}
