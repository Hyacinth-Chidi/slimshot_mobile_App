package com.techfamz.slimshotai.audio

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Extract sheet's waveform: one peak per bucket, the loudest at 1. */
class WaveformPeaksTest {

    private fun mono(vararg samples: Float) = samples

    @Test
    fun `one bucket per requested count`() {
        val peaks = WaveformPeaks.reduce(FloatArray(1000) { 0.1f }, 1000, 1, 37)
        assertEquals(37, peaks.size)
    }

    @Test
    fun `the loudest bucket is 1`() {
        // Four buckets of two frames; a burst in the fourth.
        val samples = mono(0.1f, 0f, 0.05f, 0f, 0f, 0.2f, 0.5f, -0.25f)
        val peaks = WaveformPeaks.reduce(samples, 8, 1, 4)
        assertArrayEquals(doubleArrayOf(0.2, 0.1, 0.4, 1.0), peaks, 1e-6)
    }

    @Test
    fun `silence stays silent`() {
        val peaks = WaveformPeaks.reduce(FloatArray(100), 100, 1, 10)
        assertTrue(peaks.all { it == 0.0 })
    }

    @Test
    fun `stereo takes the louder channel`() {
        // Two stereo frames per bucket: left quiet, right loud in the second.
        val samples = floatArrayOf(0.5f, 0.1f, 0.5f, 0.1f, 0.1f, -1f, 0.1f, 0.2f)
        val peaks = WaveformPeaks.reduce(samples, 4, 2, 2)
        assertArrayEquals(doubleArrayOf(0.5, 1.0), peaks, 1e-6)
    }

    @Test
    fun `fewer frames than buckets does not throw`() {
        val peaks = WaveformPeaks.reduce(floatArrayOf(0.5f, 1f), 2, 1, 10)
        assertEquals(10, peaks.size)
        assertEquals(1.0, peaks.max(), 1e-6)
    }

    @Test
    fun `fed in pieces it gives what it gives whole`() {
        val samples = FloatArray(900) { i -> ((i * 37) % 101 - 50) / 50f }
        val whole = WaveformPeaks.reduce(samples, 900, 1, 30)
        val acc = WaveformPeaks.Accumulator(totalFrames = 900, buckets = 30)
        acc.add(samples.copyOfRange(0, 250), 250, 1)
        acc.add(samples.copyOfRange(250, 900), 650, 1)
        assertArrayEquals(whole, acc.result(), 1e-9)
    }
}
