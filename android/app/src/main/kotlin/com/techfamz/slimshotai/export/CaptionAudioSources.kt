package com.techfamz.slimshotai.export

import com.techfamz.slimshotai.nativepreview.NativeTimelineClip
import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay

/** Which of a timeline's sounds auto captions listen to, and for how long. */
internal object CaptionAudioSources {

    /** The kinds of sound a caption pass mixes — `clips`, `overlays`, `tracks` on the wire. */
    data class Include(val clips: Boolean, val overlays: Boolean, val tracks: Boolean) {
        companion object {
            fun fromWire(raw: Any?): Include {
                val names = (raw as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet()
                return Include(
                    clips = "clips" in names,
                    overlays = "overlays" in names,
                    tracks = "tracks" in names,
                )
            }
        }
    }

    data class Selection(
        /**
         * The **whole** clip list when clips are included: the mixer finds a
         * transition's two clips by index into it, so filtering here would fade
         * the wrong clips. Photos and reversed clips are skipped by the mixer.
         */
        val clips: List<NativeTimelineClip>,
        val overlays: List<NativeTimelineOverlay>,
        val tracks: List<AudioExportMixer.TimelineAudioTrack>,
        /** Where the last included sound ends; 0 when there is none. */
        val durationSeconds: Double,
    )

    fun select(
        include: Include,
        clips: List<NativeTimelineClip>,
        overlays: List<NativeTimelineOverlay>,
        tracks: List<AudioExportMixer.TimelineAudioTrack>,
    ): Selection {
        val chosenClips = if (include.clips) clips else emptyList()
        val chosenOverlays = if (include.overlays) overlays.filter { it.isVideo } else emptyList()
        val chosenTracks = if (include.tracks) tracks else emptyList()
        // A photo has no sound and a reversed clip's is backwards speech, so
        // neither is somewhere the transcript could end.
        val clipEnd = chosenClips
            .filter { !it.isImage && !it.isReversed }
            .maxOfOrNull { it.timelineEnd } ?: 0.0
        val end = maxOf(
            clipEnd,
            chosenOverlays.maxOfOrNull { it.endSeconds } ?: 0.0,
            chosenTracks.maxOfOrNull { it.timelineEnd } ?: 0.0,
        )
        return Selection(chosenClips, chosenOverlays, chosenTracks, end)
    }
}
