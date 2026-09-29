package com.techfamz.slimshotai.export

import com.techfamz.slimshotai.nativepreview.NativeTimelineClip
import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which of a timeline's sounds auto captions listen to, and for how long. */
class CaptionAudioSourcesTest {

    private fun clip(
        id: String,
        start: Double,
        end: Double,
        image: Boolean = false,
        reversed: Boolean = false,
    ) = NativeTimelineClip.fromMap(
        mapOf(
            "id" to id,
            "sourceVideoPath" to "/$id.mp4",
            "sourceStart" to 0.0,
            "sourceEnd" to end - start,
            "timelineStart" to start,
            "timelineEnd" to end,
            "isImage" to image,
            "isReversed" to reversed,
        ),
        "/$id.mp4",
    )!!

    private fun overlay(id: String, end: Double, kind: String = "video") =
        NativeTimelineOverlay.fromMap(
            mapOf(
                "id" to id,
                "kind" to kind,
                "path" to "/$id.mp4",
                "startSeconds" to 0.0,
                "endSeconds" to end,
            ),
        )!!

    private val clips = listOf(clip("a", 0.0, 4.0), clip("b", 4.0, 9.0))
    private val overlays = listOf(overlay("o", 6.0), overlay("p", 12.0, kind = "image"))
    private val tracks = listOf(AudioExportMixer.TimelineAudioTrack("/m.mp3", 0.0, 0.0, 15.0, 1.0))

    @Test
    fun `the wire names the kinds of sound`() {
        assertEquals(
            CaptionAudioSources.Include(clips = true, overlays = true, tracks = false),
            CaptionAudioSources.Include.fromWire(listOf("clips", "overlays", "radio")),
        )
        assertEquals(
            CaptionAudioSources.Include(false, false, false),
            CaptionAudioSources.Include.fromWire(null),
        )
    }

    @Test
    fun `video sound is the clips and video overlays, never the music`() {
        val chosen = CaptionAudioSources.select(
            CaptionAudioSources.Include(clips = true, overlays = true, tracks = false),
            clips, overlays, tracks,
        )
        assertEquals(listOf("a", "b"), chosen.clips.map { it.id })
        assertEquals(listOf("o"), chosen.overlays.map { it.id })
        assertTrue(chosen.tracks.isEmpty())
        assertEquals(9.0, chosen.durationSeconds, 0.0)
    }

    @Test
    fun `audio tracks alone run to the end of the music`() {
        val chosen = CaptionAudioSources.select(
            CaptionAudioSources.Include(clips = false, overlays = false, tracks = true),
            clips, overlays, tracks,
        )
        assertTrue(chosen.clips.isEmpty())
        assertEquals(15.0, chosen.durationSeconds, 0.0)
    }

    @Test
    fun `photos and reversed clips stay in the list but end nothing`() {
        // The full list travels to the mixer, which finds transition clips by
        // index; only the duration ignores what has no speech in it.
        val withSilence = clips +
            clip("photo", 9.0, 12.0, image = true) +
            clip("back", 12.0, 14.0, reversed = true)
        val chosen = CaptionAudioSources.select(
            CaptionAudioSources.Include(clips = true, overlays = false, tracks = false),
            withSilence, overlays, tracks,
        )
        assertEquals(4, chosen.clips.size)
        assertEquals(9.0, chosen.durationSeconds, 0.0)
    }

    @Test
    fun `nothing included runs for no time at all`() {
        val chosen = CaptionAudioSources.select(
            CaptionAudioSources.Include(false, false, false),
            clips, overlays, tracks,
        )
        assertEquals(0.0, chosen.durationSeconds, 0.0)
    }
}
