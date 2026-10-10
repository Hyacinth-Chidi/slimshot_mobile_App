package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.TransitionShaders

/**
 * A transition window as resolved by the Dart timeline composer.
 *
 * The window is the span where the two clips overlap: it opens when the
 * incoming clip starts and closes where the outgoing clip would have ended.
 * These values are **never** recomputed here — the clip list this engine
 * receives has already been truncated for playback, so deriving the window from
 * clip boundaries would place it inside the wrong clip.
 */
internal data class NativeTimelineTransitionIntent(
    val leftClipId: String,
    val rightClipId: String,
    val leftClipIndex: Int,
    val rightClipIndex: Int,
    val type: String,
    val durationSeconds: Double,
    val timelineStartSeconds: Double,
    val timelineEndSeconds: Double,
    /**
     * How the picture travels through the window — the keyframe curves, so a
     * transition eases exactly as a keyframe does. Linear unless the seam
     * carries one; the wire omits it then.
     */
    val easing: KeyframeInterpolation = KeyframeInterpolation.LINEAR,
) {
    /**
     * Stable identity for this window. The renderer tags its captured outgoing
     * frame with this so a capture taken for one transition is never reused for
     * another after a seek or a timeline edit.
     */
    val windowKey: String =
        "$leftClipId>$rightClipId@${timelineStartSeconds.toRawBits()}"

    fun contains(timelineSeconds: Double): Boolean {
        return timelineSeconds >= timelineStartSeconds && timelineSeconds < timelineEndSeconds
    }

    /** How far into the window [timelineSeconds] sits, clamped to `0..1`. */
    fun progressAt(timelineSeconds: Double): Float {
        val duration = durationSeconds.coerceAtLeast(MIN_DURATION_SECONDS)
        return ((timelineSeconds - timelineStartSeconds) / duration)
            .coerceIn(0.0, 1.0)
            .toFloat()
    }

    /**
     * How far the **picture** has travelled at [timelineSeconds]: [progressAt]
     * through [easing]. The shader's progress, in preview and export alike.
     * The sound's crossfade keeps [progressAt] — an eased crossfade would surge
     * or, under a bounce, swing back, where the picture only changes pace.
     */
    fun pictureProgressAt(timelineSeconds: Double): Float =
        applyKeyframeEasing(easing, progressAt(timelineSeconds).toDouble()).toFloat()

    private companion object {
        const val MIN_DURATION_SECONDS = 0.001
    }
}

internal object NativeTimelineTransitionIntents {

    /**
     * Whether [a] and [b] are the same windows of the same transitions, easing
     * aside. Easing changes only the shader's progress, which the engine reads
     * every tick, so an edit that only re-eases a seam need not rebuild a lane.
     */
    fun sameWindows(
        a: List<NativeTimelineTransitionIntent>,
        b: List<NativeTimelineTransitionIntent>,
    ): Boolean = a.size == b.size && a.indices.all { i -> a[i] == b[i].copy(easing = a[i].easing) }

    /**
     * Reads the `transitions` array the Dart composer emits.
     *
     * Transitions whose type this build has no shader for are dropped, which
     * degrades them to a hard cut rather than failing the whole timeline.
     */
    fun fromTimeline(timeline: Map<String, Any?>): List<NativeTimelineTransitionIntent> {
        val raw = timeline["transitions"] as? List<*> ?: return emptyList()

        return raw.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null

            val type = map["type"] as? String ?: return@mapNotNull null
            if (!TransitionShaders.isSupported(type)) return@mapNotNull null

            val start = map.number("timelineStartSeconds") ?: return@mapNotNull null
            val end = map.number("timelineEndSeconds") ?: return@mapNotNull null
            if (end <= start) return@mapNotNull null

            NativeTimelineTransitionIntent(
                leftClipId = map["leftClipId"] as? String ?: return@mapNotNull null,
                rightClipId = map["rightClipId"] as? String ?: return@mapNotNull null,
                leftClipIndex = (map["leftClipIndex"] as? Number)?.toInt() ?: return@mapNotNull null,
                rightClipIndex = (map["rightClipIndex"] as? Number)?.toInt()
                    ?: return@mapNotNull null,
                type = type,
                durationSeconds = map.number("durationSeconds") ?: (end - start),
                timelineStartSeconds = start,
                timelineEndSeconds = end,
                easing = keyframeInterpolationByName(map["easing"] as? String),
            )
        }
    }

    private fun Map<*, *>.number(key: String): Double? {
        return (this[key] as? Number)?.toDouble()
    }
}
