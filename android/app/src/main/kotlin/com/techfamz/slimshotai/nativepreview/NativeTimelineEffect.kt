package com.techfamz.slimshotai.nativepreview

/**
 * One effect bar as the composer sends it (`EditorTimelineEffect`): an effect
 * over [start]–[end] of the timeline, applied to the main video.
 *
 * [intensity] resolves at the bar's own progress — the diamonds' clock — and
 * [introSeconds] is the window a timed effect's shader progress runs across
 * from [start] (null for a static look). Parsing only; which bars draw at an
 * instant is [EffectStack]'s.
 */
internal data class NativeTimelineEffect(
    val id: String,
    val effectId: String,
    val start: Double,
    val end: Double,
    val lane: Int,
    val intensity: AnimatableDouble,
    val introSeconds: Double?,
) {
    val duration: Double get() = end - start

    companion object {
        /** `kMinClipDurationSeconds`: the shortest bar the timeline makes. */
        const val MIN_SECONDS = 0.2

        /**
         * Null for a map with no id or no effect; a degenerate span is held to
         * [MIN_SECONDS] rather than dropped, the rule clips follow — a bar the
         * engine silently skipped would differ from the one on the timeline.
         */
        fun fromMap(map: Map<*, *>): NativeTimelineEffect? {
            val id = map["id"] as? String ?: return null
            val effectId = (map["effectId"] as? String)?.takeIf { it.isNotBlank() } ?: return null
            val start = (map.number("start") ?: 0.0).coerceAtLeast(0.0)
            val rawEnd = map.number("end") ?: (start + MIN_SECONDS)
            val end = if (rawEnd - start < MIN_SECONDS) start + MIN_SECONDS else rawEnd
            return NativeTimelineEffect(
                id = id,
                effectId = effectId,
                start = start,
                end = end,
                lane = (map["lane"] as? Number)?.toInt() ?: 0,
                intensity = AnimatableDouble.fromWire(map["intensity"], fallback = 1.0),
                introSeconds = map.number("introSeconds")?.takeIf { it > 0.0 },
            )
        }

        /** Reads a timeline's `effects` array, in the order sent (by lane). */
        fun listFrom(timeline: Map<String, Any?>): List<NativeTimelineEffect> {
            val raw = timeline["effects"] as? List<*> ?: return emptyList()
            return raw.mapNotNull { (it as? Map<*, *>)?.let(::fromMap) }
        }

        private fun Map<*, *>.number(key: String): Double? =
            (this[key] as? Number)?.toDouble()?.takeIf { it.isFinite() }
    }
}
