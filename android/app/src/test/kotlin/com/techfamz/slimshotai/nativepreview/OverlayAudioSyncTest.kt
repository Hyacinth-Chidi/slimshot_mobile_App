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
    fun `ordinary drift is never seeked, because a flush is audible`() {
        // **Device-reported as crackling.** The overlay player and the clip
        // lane are two independent ExoPlayers with no shared clock, so they
        // genuinely drift apart by tenths of a second over a long overlay.
        // The lanes tolerate 0.25s and then seek, which costs a dropped video
        // frame nobody notices mid-blend; audio cannot pay that price — every
        // seek flushes the audio codec, which is a click. So a drift this size
        // is simply lived with: a few tens of ms of skew against the picture
        // is invisible, and a click is not.
        assertNull(decide(position = 3.0, target = 3.30).seekToSeconds)
        assertNull(decide(position = 3.0, target = 2.70).seekToSeconds)
        // Only a jump no one could mistake for drift — a scrub, a loop round,
        // a clip boundary — is worth the flush.
        assertEquals(6.0, decide(position = 3.0, target = 6.0).seekToSeconds!!, 0.0)
    }

    @Test
    fun `a drift seek is rare even when it does fire`() {
        // The cooldown is long enough that a pathological case degrades to an
        // occasional tick rather than a rattle.
        assertNull(decide(position = 3.0, target = 6.0, msSinceSeek = 1_500).seekToSeconds)
        assertEquals(
            6.0,
            decide(position = 3.0, target = 6.0, msSinceSeek = 4_000).seekToSeconds!!,
            0.0,
        )
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
    fun `sound is ramped in and out rather than switched`() {
        // A player started or stopped mid-waveform is a step discontinuity,
        // which is a click. The gain is ramped over a few ticks instead; the
        // ramp is short enough not to read as a fade.
        assertEquals(0f, OverlayAudioSync.rampedGain(current = 0f, target = 1f, step = 0), 0f)
        val first = OverlayAudioSync.rampedGain(current = 0f, target = 1f, step = 1)
        assertTrue("moves toward the target", first > 0f && first < 1f)
        // It arrives, exactly, in a bounded number of steps.
        var gain = 0f
        for (i in 1..OverlayAudioSync.RAMP_TICKS) {
            gain = OverlayAudioSync.rampedGain(gain, 1f, 1)
        }
        assertEquals(1f, gain, 1e-6f)
        // And down to true silence, so a stopped overlay is really silent.
        var down = 1f
        for (i in 1..OverlayAudioSync.RAMP_TICKS) {
            down = OverlayAudioSync.rampedGain(down, 0f, 1)
        }
        assertEquals(0f, down, 0f)
    }

    @Test
    fun `a player is only stopped once it is actually silent`() {
        // Pausing at full gain is the same click as starting at it.
        assertFalse(OverlayAudioSync.mayStop(currentGain = 0.5f))
        assertTrue(OverlayAudioSync.mayStop(currentGain = 0f))
    }

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
