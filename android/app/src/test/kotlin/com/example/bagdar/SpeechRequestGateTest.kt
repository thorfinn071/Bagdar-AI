package com.example.bagdar

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class SpeechRequestGateTest {
    @Test fun cancelledSynthesisCannotReviveWhenNextRequestStarts() {
        val gate = SpeechRequestGate()
        val old = gate.begin("old")
        val synthesisEntered = CountDownLatch(1)
        val resumeOldSynthesis = CountDownLatch(1)
        var oldMayPlay = true
        val worker = Thread {
            synthesisEntered.countDown()
            assertTrue(resumeOldSynthesis.await(2, TimeUnit.SECONDS))
            oldMayPlay = gate.owns(old)
        }
        worker.start()
        assertTrue(synthesisEntered.await(2, TimeUnit.SECONDS))
        gate.cancel()
        val next = gate.begin("next")
        resumeOldSynthesis.countDown()
        worker.join(2000)
        assertFalse(worker.isAlive)
        assertFalse(oldMayPlay)
        assertTrue(old.cancelled.get())
        assertTrue(gate.owns(next))
    }

    @Test fun replacementsAndStopInvalidateEveryPriorIdentity() {
        val gate = SpeechRequestGate()
        val requests = (0..30).map { gate.begin("request-$it") }
        assertTrue(gate.owns(requests.last()))
        requests.dropLast(1).forEach { assertFalse(gate.owns(it)); assertTrue(it.cancelled.get()) }
        gate.cancel()
        requests.forEach { assertFalse(gate.owns(it)); assertTrue(it.cancelled.get()) }
    }
}
