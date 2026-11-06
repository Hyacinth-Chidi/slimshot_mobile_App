package com.techfamz.slimshotai.camera.react

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The video's sound in the file follows the moment the player showed, and
 * stays continuous: a jump only when the player really jumped, ordinary drift
 * taken up a sample at a time. Re-aiming at every 40 ms of drift was heard as
 * glitches, since the player's reported position jitters.
 */
class VideoSoundFollowerTest {

    @Test
    fun `nothing showing - held, ended - is silence`() {
        assertEquals(VideoSoundFollower.Step.Silence, VideoSoundFollower.step(null, 1_000.0))
    }

    @Test
    fun `the first moment, or a real jump, is sought`() {
        assertEquals(VideoSoundFollower.Step.Seek(2_000), VideoSoundFollower.step(2_000, null))
        assertEquals(VideoSoundFollower.Step.Seek(9_000), VideoSoundFollower.step(9_000, 2_000.0))
    }

    @Test
    fun `the player's jitter is ridden out, never sought`() {
        for (offset in listOf(-10.0, -5.0, 0.0, 5.0, 10.0)) {
            assertEquals(VideoSoundFollower.Step.Read(0), VideoSoundFollower.step(5_000, 5_000.0 + offset))
        }
    }

    @Test
    fun `drift is taken up a sample at a time`() {
        assertEquals(VideoSoundFollower.Step.Read(1), VideoSoundFollower.step(5_030, 5_000.0))
        assertEquals(VideoSoundFollower.Step.Read(-1), VideoSoundFollower.step(5_000, 5_030.0))
    }
}
