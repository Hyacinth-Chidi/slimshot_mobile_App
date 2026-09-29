package com.techfamz.slimshotai.export

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The mixer's settings. The export keeps exactly what it had; captions are the
 * same mix, mono at 16 kHz, every source at full level.
 */
class MixConfigTest {

    @Test
    fun `the export keeps exactly the settings it had`() {
        assertEquals(
            MixConfig(44_100, 2, 128_000, unityGain = false, skipsReversedClips = false),
            MixConfig.EXPORT,
        )
    }

    @Test
    fun `captions are mono 16 kHz at full level, without reversed speech`() {
        assertEquals(
            MixConfig(16_000, 1, 48_000, unityGain = true, skipsReversedClips = true),
            MixConfig.CAPTIONS,
        )
    }

    @Test
    fun `the export multiplies the level into the crossfade`() {
        assertEquals(0.25, MixConfig.EXPORT.gain(level = 0.5, crossfade = 0.5), 1e-12)
    }

    @Test
    fun `unity gain ignores the level but keeps the crossfade`() {
        assertEquals(0.5, MixConfig.CAPTIONS.gain(level = 0.0, crossfade = 0.5), 1e-12)
        assertEquals(1.0, MixConfig.CAPTIONS.gain(level = 0.2), 1e-12)
    }

    @Test
    fun `stereo writes both channels`() {
        val out = ShortArray(4)
        val written = MixConfig.EXPORT.writePcm(floatArrayOf(0.5f, -0.5f, 0f, 1f), 2, out)
        assertEquals(4, written)
        assertArrayEquals(shortArrayOf(16384, -16384, 0, 32767), out)
    }

    @Test
    fun `mono is the mean of left and right`() {
        val out = ShortArray(2)
        val written = MixConfig.CAPTIONS.writePcm(floatArrayOf(0.5f, 0f, -0.25f, -0.75f), 2, out)
        assertEquals(2, written)
        assertArrayEquals(shortArrayOf(8192, -16384), out)
    }

    @Test
    fun `a sum past full scale clips instead of wrapping`() {
        val out = ShortArray(2)
        MixConfig.EXPORT.writePcm(floatArrayOf(3f, -3f), 1, out)
        assertArrayEquals(shortArrayOf(32767, -32768), out)
    }
}
