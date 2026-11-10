package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * "Mute clip audio" on the engine side: one reading of the wire's `isMuted`,
 * shared by playback and export so the two cannot disagree, and a mute that
 * wins over any clip volume.
 */
class ClipAudioMuteTest {

    @Test
    fun `a timeline that says so mutes its clips`() {
        assertTrue(NativeTimelineClips.clipsMuted(mapOf("isMuted" to true)))
    }

    @Test
    fun `a timeline that does not say so keeps their sound`() {
        assertFalse(NativeTimelineClips.clipsMuted(emptyMap()))
        assertFalse(NativeTimelineClips.clipsMuted(mapOf("isMuted" to false)))
        assertFalse(NativeTimelineClips.clipsMuted(mapOf("isMuted" to null)))
    }

    @Test
    fun `a muted clip is silent whatever its volume, keyframed or not`() {
        for (gain in listOf(0.0, 0.3, 1.0, 2.0)) {
            assertEquals(0.0, NativeTimelineClips.clipGain(clipsMuted = true, gain = gain), 0.0)
        }
    }

    @Test
    fun `an unmuted clip plays at its own volume`() {
        for (gain in listOf(0.0, 0.3, 1.0)) {
            assertEquals(gain, NativeTimelineClips.clipGain(clipsMuted = false, gain = gain), 0.0)
        }
    }
}
