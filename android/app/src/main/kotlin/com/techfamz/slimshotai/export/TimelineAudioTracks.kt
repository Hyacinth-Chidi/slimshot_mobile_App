package com.techfamz.slimshotai.export

/**
 * The imported audio tracks a composed timeline carries — **and only those**.
 *
 * A video overlay's sound is not one of them. It reaches the mixer as an
 * overlay, at its own speed, so the sound runs with the picture; the export
 * also listed it here, at 1x, and so mixed it twice — double volume at normal
 * speed, two voices out of step at any other.
 */
internal object TimelineAudioTracks {

    fun fromTimeline(timeline: Map<String, Any?>): List<AudioExportMixer.TimelineAudioTrack> {
        val raw = timeline["audioTracks"] as? List<*> ?: return emptyList()
        return raw.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val path = map["filePath"] as? String ?: return@mapNotNull null
            if (path.isBlank()) return@mapNotNull null

            val timelineStart = (map["timelineStart"] as? Number)?.toDouble() ?: 0.0
            val timelineEnd = (map["timelineEnd"] as? Number)?.toDouble()
                ?: return@mapNotNull null
            if (timelineEnd <= timelineStart) return@mapNotNull null

            AudioExportMixer.TimelineAudioTrack(
                filePath = path,
                sourceStart = (map["sourceStart"] as? Number)?.toDouble() ?: 0.0,
                timelineStart = timelineStart,
                timelineEnd = timelineEnd,
                volume = ((map["volume"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 1.0),
            )
        }
    }
}
