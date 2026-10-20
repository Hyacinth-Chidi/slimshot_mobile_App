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
    fun `aligning pads silence up to the picture`() {
        // Capture starts once the video is seen moving, a little after it
        // did: silence covers that moment so the take stays on the picture.
        val gate = CaptureGate()
        assertEquals(1764L, gate.alignTo(1764))
        assertEquals(1764L, gate.capturedFrames)
        gate.accept(100, capturing = true)
        assertEquals(1864L, gate.capturedFrames)
    }

    @Test
    fun `aligning never cuts what was captured`() {
        val gate = CaptureGate()
        gate.accept(5000, capturing = true)
        assertEquals(0L, gate.alignTo(4000))
        assertEquals(5000L, gate.capturedFrames)
    }

    @Test
    fun `an alignment in milliseconds becomes frames`() {
        assertEquals(1764L, CaptureGate.framesFor(alignMs = 40, sampleRate = 44_100))
        assertEquals(0L, CaptureGate.framesFor(alignMs = -5, sampleRate = 44_100))
    }

    @Test
    fun `captured length in milliseconds`() {
        val gate = CaptureGate()
        gate.accept(44_100, capturing = true)
        gate.accept(22_050, capturing = true)
        assertEquals(1500L, gate.capturedMs(44_100))
    }
}
