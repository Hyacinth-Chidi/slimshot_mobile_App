package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.BackgroundFit
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * A background photo **covers** the canvas: scaled so the smaller side fills
 * and the larger is cropped centrally — the opposite of a clip's *contain* fit,
 * because a background with bars would need a background of its own.
 *
 * The value is the fraction of the photo's own extent that is visible on each
 * axis; the shader maps canvas uv into it about the centre. Both the letterbox
 * pixels (sampled inside every transition's helpers) and the no-clip tail
 * (drawn as a whole-canvas quad) go through this one function, so the photo
 * cannot sit differently behind a clip than it does on the tail.
 */
class BackgroundFitTest {

    @Test
    fun `a wide photo on a tall canvas shows its central band`() {
        // 16:9 behind 9:16: full height, and 9/16 ÷ 16/9 of the width.
        val (u, v) = BackgroundFit.cover(16.0 / 9.0, 9.0 / 16.0)
        assertEquals((9.0 / 16.0) / (16.0 / 9.0), u.toDouble(), 1e-6)
        assertEquals(1f, v, 1e-6f)
    }

    @Test
    fun `a tall photo on a wide canvas shows its central slice`() {
        val (u, v) = BackgroundFit.cover(9.0 / 16.0, 16.0 / 9.0)
        assertEquals(1f, u, 1e-6f)
        assertEquals((9.0 / 16.0) / (16.0 / 9.0), v.toDouble(), 1e-6)
    }

    @Test
    fun `a matching shape shows all of itself`() {
        val (u, v) = BackgroundFit.cover(0.5625, 0.5625)
        assertEquals(1f, u, 1e-6f)
        assertEquals(1f, v, 1e-6f)
    }

    @Test
    fun `a lane's contain fit yields the reciprocal cover fit, pinch scale cancelling`() {
        // A 16:9 clip on a 9:16 canvas is contain-fitted (1, 9/16 ÷ 16/9). To
        // cover the canvas instead, the fit uniform must exceed 1 on the axis
        // that had bars: the reciprocal of the visible fraction.
        val canvas = 9.0 / 16.0
        val fitY = (canvas / (16.0 / 9.0)).toFloat()
        val (u, v) = BackgroundFit.coverFitFromContain(1f, fitY, canvas)
        assertEquals(1.0 / (canvas / (16.0 / 9.0)), u.toDouble(), 1e-5)
        assertEquals(1f, v, 1e-6f)

        // The engine hands the renderer fit × pinch scale; the ratio is what
        // carries the clip's shape, so the scale must not change the answer.
        val (u2, v2) = BackgroundFit.coverFitFromContain(2f, fitY * 2f, canvas)
        assertEquals(u, u2, 1e-5f)
        assertEquals(v, v2, 1e-6f)
    }

    @Test
    fun `a degenerate contain fit covers with the whole texture`() {
        assertEquals(Pair(1f, 1f), BackgroundFit.coverFitFromContain(0f, 1f, 0.5625))
        assertEquals(Pair(1f, 1f), BackgroundFit.coverFitFromContain(1f, 1f, 0.0))
    }

    @Test
    fun `an unknown shape shows all of itself rather than guessing`() {
        assertEquals(Pair(1f, 1f), BackgroundFit.cover(0.0, 0.5625))
        assertEquals(Pair(1f, 1f), BackgroundFit.cover(1.5, 0.0))
    }
}
