package com.techfamz.slimshotai.camera.react

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The live talk gate: out loud, the video is lowered while you talk and your
 * microphone held back while you don't. The microphone hears the video from
 * the speaker, so talking is what the microphone hears **above** the video's
 * own sound at that moment — which the gate knows, because the video's sound
 * is mixed in beside it.
 */
class LiveTalkGateTest {

    private val duck = 0.25
    private val gate = 0.1

    private fun gateWith(lower: Boolean = true) = LiveTalkGate(lower, duck, gate, rampMs = 150)

    /** Feeds [ms] of blocks from [fromMs], each block's (mic, video) from [levels]. */
    private fun feed(g: LiveTalkGate, fromMs: Long, ms: Long, levels: (Long) -> Pair<Double, Double>) {
        var t = fromMs
        while (t < fromMs + ms) {
            val (mic, video) = levels(t)
            g.addBlock(t, mic, video)
            t += LiveTalkGate.BLOCK_MS
        }
    }

    private fun assertGains(expectedVideo: Double, expectedMic: Double, gains: LiveTalkGate.Gains) {
        assertEquals("video", expectedVideo, gains.video, 1e-6)
        assertEquals("mic", expectedMic, gains.mic, 1e-6)
    }

    @Test
    fun `with headphones nothing is lowered and nothing held back`() {
        val g = gateWith(lower = false)
        feed(g, 0, 8_000) { t -> if (t in 3_000 until 4_000) -8.0 to -10.0 else -30.0 to -10.0 }
        assertGains(1.0, 1.0, g.gainsAt(3_500))
        assertGains(1.0, 1.0, g.gainsAt(6_000))
    }

    @Test
    fun `only the speaker's copy of the video - nobody talking - holds the microphone back`() {
        val g = gateWith()
        feed(g, 0, 8_000) { -30.0 to -10.0 }
        assertGains(1.0, gate, g.gainsAt(6_000))
    }

    @Test
    fun `loud music in the video is not talking`() {
        val g = gateWith()
        feed(g, 0, 8_000) { t -> if (t in 4_000 until 6_000) -23.0 to -3.0 else -30.0 to -10.0 }
        assertGains(1.0, gate, g.gainsAt(5_000))
    }

    @Test
    fun `talking over the video lowers it and lets the microphone through, ramped at the edges`() {
        val g = gateWith()
        feed(g, 0, 8_000) { t -> if (t in 4_000 until 5_000) -8.0 to -10.0 else -30.0 to -10.0 }
        assertGains(duck, 1.0, g.gainsAt(4_500))
        assertGains(1.0, gate, g.gainsAt(3_000))
        assertGains(1.0, gate, g.gainsAt(6_000))
        val edge = g.gainsAt(4_000 - LiveTalkGate.LEAD_MS - 75)
        assertTrue("half way up the ramp: ${edge.mic}", edge.mic > gate && edge.mic < 1.0)
    }

    @Test
    fun `talking from the very first moment is never held back`() {
        val g = gateWith()
        feed(g, 0, 3_000) { -8.0 to -10.0 }
        assertEquals(1.0, g.gainsAt(100).mic, 1e-6)
        assertEquals(1.0, g.gainsAt(2_000).mic, 1e-6)
    }

    @Test
    fun `a click is not talking`() {
        val g = gateWith()
        feed(g, 0, 8_000) { t -> if (t == 5_000L) -5.0 to -10.0 else -30.0 to -10.0 }
        assertGains(1.0, gate, g.gainsAt(5_000))
    }

    @Test
    fun `a short pause between two words keeps the talking whole`() {
        val g = gateWith()
        feed(g, 0, 8_000) { t ->
            if (t in 4_000 until 4_400 || t in 4_600 until 5_000) -8.0 to -10.0 else -30.0 to -10.0
        }
        assertGains(duck, 1.0, g.gainsAt(4_500))
    }

    @Test
    fun `in a quiet room with the video silent, a voice is talking`() {
        val g = gateWith()
        feed(g, 0, 6_000) { t -> if (t in 3_000 until 4_000) -15.0 to -120.0 else -60.0 to -120.0 }
        assertGains(duck, 1.0, g.gainsAt(3_500))
        assertGains(1.0, gate, g.gainsAt(1_500))
    }
}
