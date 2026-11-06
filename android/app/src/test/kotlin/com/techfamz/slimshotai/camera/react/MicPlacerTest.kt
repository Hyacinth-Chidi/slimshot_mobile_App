package com.techfamz.slimshotai.camera.react

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The microphone laid down as one continuous stream: anchored by its
 * timestamp at the start and after a pause or a real gap, end to end
 * otherwise — placing every block by its own jittery timestamp left gaps and
 * overlaps between blocks, heard as clicks.
 */
class MicPlacerTest {

    private val ms = 1_000_000L

    @Test
    fun `blocks go end to end however their timestamps jitter`() {
        val placer = MicPlacer(48_000)
        val jitter = longArrayOf(0, 1, -1, 2, 0, -2, 1, 0)
        val starts = (0 until 8).map { k -> placer.place((k * 10 + jitter[k]) * ms, 480) }
        assertEquals((0 until 8).map { it * 480L }, starts)
    }

    @Test
    fun `a pause drops the microphone, and the next block is anchored where it was heard`() {
        val placer = MicPlacer(48_000)
        placer.place(0, 480)
        placer.place(10 * ms, 480)
        assertNull(placer.place(null, 480))
        assertEquals(30 * 48L, placer.place(30 * ms, 480))
    }

    @Test
    fun `a real gap - frames the microphone lost - is anchored again, not closed up`() {
        val placer = MicPlacer(48_000)
        placer.place(0, 480)
        placer.place(10 * ms, 480)
        assertEquals(120 * 48L, placer.place(120 * ms, 480))
    }

    @Test
    fun `timestamps drifting past the jitter are followed a sample at a time`() {
        val later = MicPlacer(48_000)
        later.place(0, 480)
        val behind = (1..3).map { k -> later.place((k * 10 + 25) * ms, 480) }
        assertEquals(listOf(481L, 962L, 1443L), behind)

        val earlier = MicPlacer(48_000)
        earlier.place(100 * ms, 480)
        val ahead = (1..3).map { k -> earlier.place((100 + k * 10 - 25) * ms, 480) }
        assertEquals(listOf(5279L, 5758L, 6237L), ahead)
    }
}
