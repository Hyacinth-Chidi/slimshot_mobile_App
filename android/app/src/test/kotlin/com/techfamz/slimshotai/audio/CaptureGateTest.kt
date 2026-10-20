package com.techfamz.slimshotai.audio

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The microphone runs from the moment the recorder opens; only what it hears
 * while capturing is kept. That is what lets a take start on the frame the
 * video started on rather than after the microphone's own start-up delay.
 */
class CaptureGateTest {

    @Test
    fun `nothing is written before capturing starts`() {
        val gate = CaptureGate()
        assertEquals(0, gate.accept(1024, capturing = false))
        assertEquals(0L, gate.capturedFrames)
    }

    @Test
    fun `a pause drops what the mic hears`() {
        val gate = CaptureGate()
        assertEquals(800, gate.accept(800, capturing = true))
        assertEquals(0, gate.accept(500, capturing = false))
        assertEquals(800L, gate.capturedFrames)
    }

    @Test
    fun `resumed frames add on`() {
        val gate = CaptureGate()
        gate.accept(1000, capturing = true)
        gate.accept(500, capturing = false)
        gate.accept(200, capturing = true)
        assertEquals(1200L, gate.capturedFrames)
    }

    @Test
    fun `captured length in milliseconds`() {
        val gate = CaptureGate()
        gate.accept(44_100, capturing = true)
        gate.accept(22_050, capturing = true)
        assertEquals(1500L, gate.capturedMs(44_100))
    }
}
