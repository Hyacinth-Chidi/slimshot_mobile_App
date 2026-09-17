package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What a video overlay's sound does on each engine tick.
 *
 * Device-reported: once the overlay's picture moved into GL the overlay went
 * silent in the preview — the `video_player` controller that was deleted had
 * been its picture *and* its sound. The players themselves only run on a
 * device; the decisions are here so they can be pinned.
 */
class OverlayAudioSyncTest {

    private fun overlay(
        start: Double = 5.0,
        end: Double = 12.0,
        volume: Double = 1.0,
        muted: Boolean = false,
        kind: String = "video",
    ): NativeTimelineOverlay = NativeTimelineOverlay.fromMap(
        mapOf(
            "id" to "o",
            "kind" to kind,
            "path" to "/v.mp4",
            "startSeconds" to start,
            "endSeconds" to end,
            "volume" to volume,
            "isMuted" to muted,
        ),
    )!!

    private fun decide(
        advancing: Boolean = true,
        inWindow: Boolean = true,
        playWhenReady: Boolean = true,
        isPlaying: Boolean = true,
        position: Double = 3.0,
        target: Double = 3.0,
        msSinceSeek: Long = 10_000,
    ) = OverlayAudioSync.decide(
        advancing = advancing,
        inWindow = inWindow,
        playWhenReady = playWhenReady,
        playerIsPlaying = isPlaying,
        playerPositionSeconds = position,
        targetSeconds = target,
        msSinceLastSeek = msSinceSeek,
    )

    // ------------------------------------------------------------ who gets one

    @Test
    fun `only an audible video overlay near the playhead holds a player`() {
        assertTrue(OverlayAudioSync.wantsPlayer(overlay(), 6.0))
        // Held a little ahead of its start, so the first sound is not late.
        assertTrue(OverlayAudioSync.wantsPlayer(overlay(), 5.0 - 0.5))
        assertFalse("long before", OverlayAudioSync.wantsPlayer(overlay(), 1.0))
        assertFalse("after", OverlayAudioSync.wantsPlayer(overlay(), 12.0))
        assertFalse("muted", OverlayAudioSync.wantsPlayer(overlay(muted = true), 6.0))
        assertFalse("silent", OverlayAudioSync.wantsPlayer(overlay(volume = 0.0), 6.0))
        assertFalse("a photo", OverlayAudioSync.wantsPlayer(overlay(kind = "image"), 6.0))
    }

    // ------------------------------------------------------------ the decisions

    @Test
    fun `in step and playing, it is left completely alone`() {
        val c = decide(position = 3.0, target = 3.04)
        assertTrue(c.playWhenReady)
        assertNull("a seek here would be an audible click for nothing", c.seekToSeconds)
    }

    @Test
    fun `starting to play seeks onto the instant first`() {
        val c = decide(playWhenReady = false, isPlaying = false, position = 0.0, target = 3.0)
        assertTrue(c.playWhenReady)
        assertEquals(3.0, c.seekToSeconds!!, 0.0)
    }

    @Test
    fun `starting from where it was parked does not seek again`() {
        // The preroll parked it on its first sample; a second seek is a second
        // buffer flush exactly when the sound is due.
        val c = decide(playWhenReady = false, isPlaying = false, position = 3.0, target = 3.01)
        assertTrue(c.playWhenReady)
        assertNull(c.seekToSeconds)
    }

    @Test
    fun `a playhead that jumped is followed, once per cooldown`() {
        assertEquals(9.0, decide(position = 3.0, target = 9.0).seekToSeconds!!, 0.0)
        // Straight after a seek the position has not caught up yet; seeking
        // again every tick is the seek loop of fault 9.
        assertNull(decide(position = 3.0, target = 9.0, msSinceSeek = 100).seekToSeconds)
    }

    @Test
    fun `a player still buffering is not chased`() {
        // Its position stands still while the target advances — the same trap
        // the lanes' drift correction fell into.
        val c = decide(isPlaying = false, position = 3.0, target = 3.6)
        assertTrue(c.playWhenReady)
        assertNull(c.seekToSeconds)
    }

    @Test
    fun `paused, it stops and follows a scrub`() {
        val still = decide(advancing = false, position = 3.0, target = 3.02)
        assertFalse(still.playWhenReady)
        assertNull(still.seekToSeconds)

        val scrubbed = decide(advancing = false, position = 3.0, target = 7.0, msSinceSeek = 500)
        assertFalse(scrubbed.playWhenReady)
        assertEquals(7.0, scrubbed.seekToSeconds!!, 0.0)
    }

    @Test
    fun `ahead of its window it waits, parked on its first sample`() {
        val c = decide(inWindow = false, position = 0.0, target = 2.0, msSinceSeek = 500)
        assertFalse("no sound before the overlay starts", c.playWhenReady)
        assertEquals(2.0, c.seekToSeconds!!, 0.0)
    }

    // ------------------------------------------------------------------- gain

    @Test
    fun `gain is the master volume times the overlay's own`() {
        assertEquals(0.4f, OverlayAudioSync.gain(0.8f, overlay(volume = 0.5)), 1e-6f)
        assertEquals(0f, OverlayAudioSync.gain(0.8f, overlay(muted = true)), 0f)
        assertEquals(0f, OverlayAudioSync.gain(0f, overlay()), 0f)
    }

    // -------------------------------------------------------------- the tail

    @Test
    fun `in the tail the clock runs only while Flutter keeps sending it`() {
        // Past the last clip the engine is parked and not "playing"; the
        // editor's ticker walks the playhead and sends each position. When
        // those stop — paused, backgrounded, anything — the sound must stop
        // too, without relying on a message that says so.
        assertTrue(OverlayAudioSync.tailIsAdvancing(msSinceTailClock = 40))
        assertFalse(OverlayAudioSync.tailIsAdvancing(msSinceTailClock = 400))
    }
}
