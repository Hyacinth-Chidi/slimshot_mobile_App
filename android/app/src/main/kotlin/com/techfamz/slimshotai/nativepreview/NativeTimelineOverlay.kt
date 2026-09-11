package com.techfamz.slimshotai.nativepreview

/**
 * A photo or video laid over the timeline, as the Dart composer emits it.
 *
 * All geometry is **normalised to the canvas** — `0..1` fractions, never device
 * pixels. The composer converts at the boundary precisely so this side never
 * inherits a screen size; see the overlay section of the timeline contract.
 *
 * Animation is evaluated *here*, per frame, by [stateAt] — a direct port of the
 * arithmetic in `image_overlay_layer.dart`. Export calls it with the output
 * clock, so an overlay fades and slides identically however fast the export
 * runs. If the Flutter layer's curves change, this must change with them.
 */
internal data class NativeTimelineOverlay(
    val id: String,
    /** `image` or `video`. */
    val kind: String,
    val path: String,
    val centerX: Double,
    val centerY: Double,
    /** The fit box, as fractions of canvas width/height (a square in pixels). */
    val boxWidth: Double,
    val boxHeight: Double,
    val scale: Double,
    /** Radians, clockwise, about the overlay's centre. */
    val rotation: Double,
    val opacity: Double,
    val startSeconds: Double,
    val endSeconds: Double,
    /** Draw order — higher lanes paint on top. */
    val laneIndex: Int,
    /** How far a slide animation travels, as canvas fractions. */
    val slideOffsetX: Double,
    val slideOffsetY: Double,
    val animationIn: String?,
    val animationOut: String?,
    val animationInSeconds: Double,
    val animationOutSeconds: Double,
    /** Video overlays only. */
    val sourceStart: Double,
    val sourceEnd: Double,
    val volume: Double,
    val isMuted: Boolean,
) {

    val isVideo: Boolean get() = kind == "video"

    fun contains(timelineSeconds: Double): Boolean {
        return timelineSeconds >= startSeconds && timelineSeconds < endSeconds
    }

    /** Source position of a video overlay at [timelineSeconds]. */
    fun sourceAt(timelineSeconds: Double): Double {
        val offset = (timelineSeconds - startSeconds).coerceAtLeast(0.0)
        val end = if (sourceEnd > sourceStart) sourceEnd else Double.MAX_VALUE
        return (sourceStart + offset).coerceAtMost(end)
    }

    /** What the animations do to this overlay at one instant. */
    data class FrameState(
        val opacity: Double,
        val scale: Double,
        /** Canvas-fraction displacement of the centre. */
        val offsetX: Double,
        val offsetY: Double,
    )

    /**
     * Animation state at [timelineSeconds].
     *
     * The multipliers compose exactly as the Flutter layer composes them: the
     * in-animation runs over the first [animationInSeconds] of the overlay's
     * span, the out-animation over the last [animationOutSeconds], and both can
     * be live at once on a very short overlay.
     */
    fun stateAt(timelineSeconds: Double): FrameState {
        var animScale = 1.0
        var animOpacity = opacity
        var offsetX = 0.0
        var offsetY = 0.0

        val timeIn = timelineSeconds - startSeconds
        val timeRemaining = endSeconds - timelineSeconds

        if (animationIn != null && timeIn < animationInSeconds) {
            val p = (timeIn / animationInSeconds.coerceAtLeast(MIN_ANIM_SECONDS))
                .coerceIn(0.0, 1.0)
            when (animationIn) {
                "fade_in" -> animOpacity *= p
                "zoom_in" -> animScale *= p
                "zoom_out" -> animScale *= (2.0 - p)
                // Positive y is down in canvas fractions, same as Flutter.
                "slide_up" -> offsetY += slideOffsetY * (1 - p)
                "slide_down" -> offsetY += -slideOffsetY * (1 - p)
                "slide_left" -> offsetX += slideOffsetX * (1 - p)
                "slide_right" -> offsetX += -slideOffsetX * (1 - p)
            }
        }

        if (animationOut != null && timeRemaining < animationOutSeconds) {
            val p = (1.0 - timeRemaining / animationOutSeconds.coerceAtLeast(MIN_ANIM_SECONDS))
                .coerceIn(0.0, 1.0)
            when (animationOut) {
                "fade_out" -> animOpacity *= (1 - p)
                "zoom_in_out" -> animScale *= (1 + p)
                "zoom_out_out" -> animScale *= (1 - p)
                "slide_up_out" -> offsetY += -slideOffsetY * p
                "slide_down_out" -> offsetY += slideOffsetY * p
                "slide_left_out" -> offsetX += -slideOffsetX * p
                "slide_right_out" -> offsetX += slideOffsetX * p
            }
        }

        return FrameState(
            opacity = animOpacity.coerceIn(0.0, 1.0),
            scale = (scale * animScale).coerceAtLeast(0.0),
            offsetX = offsetX,
            offsetY = offsetY,
        )
    }

    companion object {
        private const val MIN_ANIM_SECONDS = 0.001

        fun fromMap(map: Map<*, *>): NativeTimelineOverlay? {
            val id = map["id"] as? String ?: return null
            val kind = map["kind"] as? String ?: return null
            val path = (map["path"] as? String)?.takeIf { it.isNotBlank() } ?: return null

            val start = map.number("startSeconds") ?: return null
            val end = map.number("endSeconds") ?: return null
            if (end <= start) return null

            return NativeTimelineOverlay(
                id = id,
                kind = kind,
                path = path,
                centerX = map.number("centerX") ?: 0.5,
                centerY = map.number("centerY") ?: 0.5,
                boxWidth = map.number("boxWidth") ?: 0.25,
                boxHeight = map.number("boxHeight") ?: 0.25,
                scale = (map.number("scale") ?: 1.0).coerceAtLeast(0.0),
                rotation = map.number("rotation") ?: 0.0,
                opacity = (map.number("opacity") ?: 1.0).coerceIn(0.0, 1.0),
                startSeconds = start,
                endSeconds = end,
                laneIndex = (map["laneIndex"] as? Number)?.toInt() ?: 0,
                slideOffsetX = map.number("slideOffsetX") ?: 0.0,
                slideOffsetY = map.number("slideOffsetY") ?: 0.0,
                animationIn = map["animationIn"] as? String,
                animationOut = map["animationOut"] as? String,
                animationInSeconds = map.number("animationInSeconds") ?: 0.5,
                animationOutSeconds = map.number("animationOutSeconds") ?: 0.5,
                sourceStart = map.number("sourceStart") ?: 0.0,
                sourceEnd = map.number("sourceEnd") ?: 0.0,
                volume = (map.number("volume") ?: 1.0).coerceIn(0.0, 1.0),
                isMuted = map["isMuted"] as? Boolean ?: false,
            )
        }

        private fun Map<*, *>.number(key: String): Double? {
            return (this[key] as? Number)?.toDouble()
        }
    }
}

internal object NativeTimelineOverlays {

    /** Reads the composer's `overlays` array, already sorted by lane. */
    fun fromTimeline(timeline: Map<String, Any?>): List<NativeTimelineOverlay> {
        val raw = timeline["overlays"] as? List<*> ?: return emptyList()
        return raw.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            NativeTimelineOverlay.fromMap(map)
        }
    }
}
