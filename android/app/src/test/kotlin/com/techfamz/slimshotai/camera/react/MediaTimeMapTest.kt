package com.techfamz.slimshotai.camera.react

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Which moment of the video was on screen at each instant of the take. */
class MediaTimeMapTest {

    private val second = 1_000_000_000L

    @Test
    fun `while it plays, the video moves with the clock`() {
        val map = MediaTimeMap()
        map.sample(0, 0, true)
        map.sample(second, 1_000, true)
        assertEquals(500L, map.mediaMsAt(second / 2))
        assertNull("before the first sample", map.mediaMsAt(-1))
    }

    @Test
    fun `held, it shows no moving moment - resumed, it goes on from where it stood`() {
        val map = MediaTimeMap()
        map.sample(0, 0, true)
        map.sample(second, 1_000, true)
        map.sample(second, 1_000, false)
        assertNull(map.mediaMsAt(second + second / 2))
        assertNull(map.mediaMsAt(2 * second))
        map.sample(3 * second, 1_000, true)
        assertEquals(1_500L, map.mediaMsAt(3 * second + second / 2))
    }

    @Test
    fun `past the last sample it is carried on while playing`() {
        val map = MediaTimeMap()
        map.sample(0, 2_000, true)
        assertEquals(2_250L, map.mediaMsAt(second / 4))
    }

    @Test
    fun `a moment is never carried past where the player said it was next`() {
        val map = MediaTimeMap()
        map.sample(0, 0, true)
        map.sample(second, 900, false)
        assertEquals(900L, map.mediaMsAt(second - 1))
    }

    @Test
    fun `old samples go, the one before the cut stays`() {
        val map = MediaTimeMap()
        map.sample(0, 0, true)
        map.sample(second, 1_000, true)
        map.sample(2 * second, 2_000, true)
        map.prune(2 * second - 1)
        assertEquals(1_500L, map.mediaMsAt(second + second / 2))
    }
}
