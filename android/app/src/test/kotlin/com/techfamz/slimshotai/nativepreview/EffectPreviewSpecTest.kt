package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.effects.EffectPreviewRequest
import com.techfamz.slimshotai.nativepreview.gl.effects.EffectPreviewSpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * An effect tile's atlas, as the engine lays it out: the cells match the
 * Dart `effectPreviewCellRect` once read back upright, and a request it
 * cannot honour is refused rather than drawn wrong.
 */
class EffectPreviewSpecTest {

    private val spec = EffectPreviewSpec(160, 144, 5, 25, 15)

    @Test
    fun `the default spec lays out 5 by 5`() {
        assertEquals(5, spec.rows)
        assertEquals(800, spec.atlasWidth)
        assertEquals(720, spec.atlasHeight)
    }

    @Test
    fun `frame 0 is plain, then 15 fps`() {
        assertNull(spec.frameSeconds(0))
        assertEquals(0.0, spec.frameSeconds(1)!!, 1e-12)
        assertEquals(23.0 / 15, spec.frameSeconds(24)!!, 1e-12)
    }

    @Test
    fun `GL rows are flipped so the read-back atlas is upright`() {
        assertArrayEquals(intArrayOf(0, 576, 160, 144), spec.cellViewport(0))
        assertArrayEquals(intArrayOf(160, 432, 160, 144), spec.cellViewport(6))
        assertArrayEquals(intArrayOf(640, 0, 160, 144), spec.cellViewport(24))
    }

    @Test
    fun `slices cover every cell in order, at most 4 a slice`() {
        val slices = spec.slices()
        assertEquals((0 until 25).toList(), slices.flatMap { it.toList() })
        assertTrue(slices.all { it.count() in 1..EffectPreviewSpec.MAX_CELLS_PER_SLICE })
    }

    @Test
    fun `fromArgs takes the default`() {
        assertEquals(spec, EffectPreviewSpec.fromArgs(160, 144, 5, 25, 15))
    }

    @Test
    fun `fromArgs rejects a cell off a 16 px boundary`() {
        assertNull(EffectPreviewSpec.fromArgs(150, 144, 5, 25, 15))
        assertNull(EffectPreviewSpec.fromArgs(160, 140, 5, 25, 15))
    }

    @Test
    fun `fromArgs rejects too few frames and a missing value`() {
        assertNull(EffectPreviewSpec.fromArgs(160, 144, 5, 0, 15))
        assertNull(EffectPreviewSpec.fromArgs(160, 144, 5, 1, 15))
        assertNull(EffectPreviewSpec.fromArgs(null, 144, 5, 25, 15))
    }

    @Test
    fun `fromArgs rejects an atlas over 4096`() {
        assertNull(EffectPreviewSpec.fromArgs(512, 144, 9, 25, 15))
    }

    private fun bar(effectId: String) = mapOf(
        "id" to "preview_$effectId",
        "effectId" to effectId,
        "start" to 0.0,
        "end" to 3.0,
        "lane" to 0,
        "intensity" to 0.6,
    )

    @Test
    fun `parse rejects an effect with no pass cost`() {
        assertNull(EffectPreviewRequest.parse(bar("from_the_future"), spec))
        assertNotNull(EffectPreviewRequest.parse(bar("vignette"), spec))
    }

    @Test
    fun `parse rejects a malformed effect or a missing spec`() {
        assertNull(EffectPreviewRequest.parse("vignette", spec))
        assertNull(EffectPreviewRequest.parse(mapOf("effectId" to "vignette"), spec))
        assertNull(EffectPreviewRequest.parse(bar("vignette"), null))
    }
}
