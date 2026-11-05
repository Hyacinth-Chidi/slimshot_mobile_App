package com.techfamz.slimshotai.camera

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * A selfie is saved by CameraX with its mirror in the EXIF orientation, not in
 * the pixels; the editor's photo decoders read only the plain turns. So a
 * flipped photo is baked upright before anyone sees it, and the bake must read
 * every one of the eight orientations the way a viewer does: flip across the
 * vertical axis first, then turn clockwise.
 */
class ExifTurnTest {

    /** Where a pixel at ([x], [y]) of a [w] x [h] stored image is shown. */
    private fun shown(turn: ExifTurn, x: Int, y: Int, w: Int, h: Int): Pair<Int, Int> {
        var px = x
        val py = y
        if (turn.flip) px = w - 1 - x
        return when (turn.degrees) {
            90 -> Pair(h - 1 - py, px)
            180 -> Pair(w - 1 - px, h - 1 - py)
            270 -> Pair(py, w - 1 - px)
            else -> Pair(px, py)
        }
    }

    @Test
    fun `the plain turns carry no flip`() {
        assertEquals(ExifTurn(flip = false, degrees = 0), ExifTurn.of(1))
        assertEquals(ExifTurn(flip = false, degrees = 90), ExifTurn.of(6))
        assertEquals(ExifTurn(flip = false, degrees = 180), ExifTurn.of(3))
        assertEquals(ExifTurn(flip = false, degrees = 270), ExifTurn.of(8))
    }

    @Test
    fun `the mirrored four flip, then turn`() {
        assertEquals(ExifTurn(flip = true, degrees = 0), ExifTurn.of(2))
        assertEquals(ExifTurn(flip = true, degrees = 180), ExifTurn.of(4))
        assertEquals(ExifTurn(flip = true, degrees = 270), ExifTurn.of(5))
        assertEquals(ExifTurn(flip = true, degrees = 90), ExifTurn.of(7))
    }

    @Test
    fun `an unknown or missing orientation is upright`() {
        assertEquals(ExifTurn(flip = false, degrees = 0), ExifTurn.of(0))
        assertEquals(ExifTurn(flip = false, degrees = 0), ExifTurn.of(42))
    }

    @Test
    fun `each reading matches the EXIF definition of its orientation`() {
        // A 4 x 2 image. The EXIF spec says where its stored top-left pixel
        // (0, 0) belongs once shown: 2 mirrors it to the top right, 4 to the
        // bottom left, 5 (transpose) keeps it top left of the turned picture,
        // 7 (transverse) sends it to the bottom right.
        val w = 4
        val h = 2
        assertEquals(Pair(3, 0), shown(ExifTurn.of(2), 0, 0, w, h))
        assertEquals(Pair(0, 1), shown(ExifTurn.of(4), 0, 0, w, h))
        assertEquals(Pair(0, 0), shown(ExifTurn.of(5), 0, 0, w, h))
        assertEquals(Pair(1, 3), shown(ExifTurn.of(7), 0, 0, w, h))
        // And the plain turn 6 (90 clockwise) puts it top right of a 2 x 4.
        assertEquals(Pair(1, 0), shown(ExifTurn.of(6), 0, 0, w, h))
    }

    @Test
    fun `only a flipped photo needs baking`() {
        for (orientation in 0..8) {
            val flipped = orientation in setOf(2, 4, 5, 7)
            assertEquals("orientation $orientation", flipped, ExifTurn.of(orientation).needsBaking)
        }
    }
}
