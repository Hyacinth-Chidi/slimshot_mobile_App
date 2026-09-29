package com.techfamz.slimshotai.export

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The imported tracks a composed timeline carries — and only those.
 *
 * A video overlay's sound used to be listed here as well as reaching the mixer
 * as an overlay, so the export played it twice: double volume at 1x, two
 * voices out of step at any other speed.
 */
class TimelineAudioTracksTest {

    private fun track(vararg entries: Pair<String, Any?>) = mapOf(*entries)

    @Test
    fun `reads an imported track`() {
        val tracks = TimelineAudioTracks.fromTimeline(
            mapOf(
                "audioTracks" to listOf(
                    track(
                        "filePath" to "/m.mp3",
                        "sourceStart" to 2.0,
                        "timelineStart" to 1.0,
                        "timelineEnd" to 9.0,
                        "volume" to 0.4,
                    ),
                ),
            ),
        )
        assertEquals(
            listOf(AudioExportMixer.TimelineAudioTrack("/m.mp3", 2.0, 1.0, 9.0, 0.4)),
            tracks,
        )
    }

    @Test
    fun `skips a track with no file or no length, and clamps the volume`() {
        val tracks = TimelineAudioTracks.fromTimeline(
            mapOf(
                "audioTracks" to listOf(
                    track("filePath" to "", "timelineEnd" to 4.0),
                    track("filePath" to "/a.mp3"),
                    track("filePath" to "/b.mp3", "timelineStart" to 5.0, "timelineEnd" to 5.0),
                    track("filePath" to "/c.mp3", "timelineEnd" to 3.0, "volume" to 7.0),
                    "junk",
                ),
            ),
        )
        assertEquals(listOf("/c.mp3"), tracks.map { it.filePath })
        assertEquals(1.0, tracks.single().volume, 0.0)
    }

    @Test
    fun `a video overlay is never read as a track`() {
        val tracks = TimelineAudioTracks.fromTimeline(
            mapOf(
                "overlays" to listOf(
                    mapOf(
                        "id" to "o",
                        "kind" to "video",
                        "path" to "/v.mp4",
                        "startSeconds" to 0.0,
                        "endSeconds" to 4.0,
                    ),
                ),
            ),
        )
        assertTrue(tracks.isEmpty())
    }
}
