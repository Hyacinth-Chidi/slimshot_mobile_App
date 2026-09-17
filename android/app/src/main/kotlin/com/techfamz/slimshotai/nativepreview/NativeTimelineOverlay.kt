package com.techfamz.slimshotai.nativepreview

/**
 * One glyph of a text overlay.
 *
 * A glyph carries **three** rects, not two, because a padded cell and a placed
 * glyph are not the same rectangle:
 *
 * - `atlas*` — fractions of the sprite sheet. The whole **padded** cell, which
 *   is what gets sampled: the padding is real ink (stroke and shadow bleed) and
 *   cropping it away would clip a shadow at the letter's edge.
 * - `box*` — fractions of the text box. Where the glyph is **placed**. These
 *   tile the box and never overlap, unlike the padded cells, which do overlap
 *   their neighbours; placing by the padded rect composites the shared ink
 *   twice.
 * - `src*` — fractions **of the cell**. Which sub-rectangle of the cell maps
 *   onto `box*`; the bleed sits outside it and spills past the box rect's edges,
 *   which is exactly how a shadow reaches beyond its own letter.
 *
 * All twelve values are `0..1` fractions — the Dart side converts at the
 * boundary so this side never sees a device pixel.
 */
internal data class NativeTimelineGlyph(
    val atlasLeft: Double,
    val atlasTop: Double,
    val atlasRight: Double,
    val atlasBottom: Double,
    val boxLeft: Double,
    val boxTop: Double,
    val boxRight: Double,
    val boxBottom: Double,
    val srcLeft: Double,
    val srcTop: Double,
    val srcRight: Double,
    val srcBottom: Double,
)

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
    /** `image`, `video`, or `text`. */
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
    /**
     * Text overlays only: an animation that repeats for the whole span.
     *
     * There is no image-overlay equivalent — [stateAt] never reads it — so a
     * null here is not a missing feature, it is the ordinary case.
     */
    val animationLoop: String?,
    /**
     * Speed multipliers for the per-glyph text animations. Higher is faster: the
     * catalog's natural duration is **divided** by these.
     *
     * Defaulted to 1.0 so an overlay from a composer that does not send them
     * animates at its natural speed rather than at zero (which would divide to
     * infinity) — see `TextAnimationCurves.resolveDurations`, which guards the
     * same way for the same reason.
     *
     * **[speedIn] and [speedOut] are expected to be equal**, and the resolution
     * path deliberately uses one of them for both windows. The animation tab is
     * a single Speed slider; the two fields exist only because the JSON names
     * them separately. `resolveDurations` — the port of the Dart's proportional
     * compression — takes **one** speed, exactly as
     * `resolveTextAnimationDurations` does, so honouring a divergence would
     * require a second copy of that compression rule on this side of the
     * boundary, kept in sync by nothing. Do not "fix" the single-speed call by
     * re-deriving the out window locally; if the slots must genuinely differ,
     * widen `resolveDurations` on both sides of the port and regenerate the
     * shared fixture.
     *
     * [speedLoop] is independent and genuinely its own: a loop's period is not
     * part of the in/out compression at all.
     */
    val speedIn: Double,
    val speedOut: Double,
    val speedLoop: Double,
    /** Video overlays only. */
    val sourceStart: Double,
    val sourceEnd: Double,
    val volume: Double,
    val isMuted: Boolean,
    /** Text overlays only: one entry per drawn character. */
    val glyphs: List<NativeTimelineGlyph>,
    /** Text overlays only: the background box in text-box fractions. */
    /**
     * The shape this overlay is cut to, as the same two vec4s a clip's mask
     * uses — `NativeTimelineClip.NO_MASK` when unmasked.
     *
     * **In the overlay's own box**, not in canvas fractions: an overlay is
     * placed and scaled independently, so a mask measured against the canvas
     * would slide off the picture the moment the overlay moved.
     */
    val mask: FloatArray = NativeTimelineClip.NO_MASK,
    val backgroundLeft: Double,
    val backgroundTop: Double,
    val backgroundRight: Double,
    val backgroundBottom: Double,
    /** Corner radius as a fraction of the box width. */
    val backgroundRadius: Double,
) {

    val isVideo: Boolean get() = kind == "video"

    /**
     * A text overlay with glyphs to draw. A `text` overlay that arrived without
     * them (the atlas exceeded the texture limit) falls back to the plain image
     * path, which is why this checks both.
     */
    val isText: Boolean get() = kind == "text" && glyphs.isNotEmpty()

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
     * The overlay with **no animation applied** — its authored opacity, scale
     * and position.
     *
     * A text overlay whose glyphs carry their own animated state uses this
     * instead of [stateAt]: both read the same `animationIn`/`animationOut`
     * ids, so applying the box-level curve as well would animate the text twice.
     */
    fun restingState(): FrameState = FrameState(
        opacity = opacity.coerceIn(0.0, 1.0),
        scale = scale.coerceAtLeast(0.0),
        offsetX = 0.0,
        offsetY = 0.0,
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

            // A glyph missing any of its twelve values is dropped rather than
            // defaulted: a zero rect would draw a degenerate quad, and a
            // half-parsed table is a contract mismatch, not a layout.
            val glyphs = (map["glyphs"] as? List<*>)?.mapNotNull { entry ->
                val glyph = entry as? Map<*, *> ?: return@mapNotNull null
                NativeTimelineGlyph(
                    atlasLeft = glyph.number("atlasLeft") ?: return@mapNotNull null,
                    atlasTop = glyph.number("atlasTop") ?: return@mapNotNull null,
                    atlasRight = glyph.number("atlasRight") ?: return@mapNotNull null,
                    atlasBottom = glyph.number("atlasBottom") ?: return@mapNotNull null,
                    boxLeft = glyph.number("boxLeft") ?: return@mapNotNull null,
                    boxTop = glyph.number("boxTop") ?: return@mapNotNull null,
                    boxRight = glyph.number("boxRight") ?: return@mapNotNull null,
                    boxBottom = glyph.number("boxBottom") ?: return@mapNotNull null,
                    srcLeft = glyph.number("srcLeft") ?: return@mapNotNull null,
                    srcTop = glyph.number("srcTop") ?: return@mapNotNull null,
                    srcRight = glyph.number("srcRight") ?: return@mapNotNull null,
                    srcBottom = glyph.number("srcBottom") ?: return@mapNotNull null,
                )
            } ?: emptyList()

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
                // Absent until the composer sends them; the defaults are
                // deliberately the no-op ones, so a timeline written by today's
                // Dart animates exactly as it does now.
                animationLoop = map["animationLoop"] as? String,
                speedIn = map.positiveRate("speedIn"),
                speedOut = map.positiveRate("speedOut"),
                speedLoop = map.positiveRate("speedLoop"),
                sourceStart = map.number("sourceStart") ?: 0.0,
                sourceEnd = map.number("sourceEnd") ?: 0.0,
                volume = (map.number("volume") ?: 1.0).coerceIn(0.0, 1.0),
                isMuted = map["isMuted"] as? Boolean ?: false,
                glyphs = glyphs,
                // Absent on every overlay saved before shapes existed, and on
                // every unmasked one; `parseMask` reads that as no mask.
                mask = NativeTimelineClip.parseMask(map["mask"]),
                backgroundLeft = map.number("backgroundLeft") ?: 0.0,
                backgroundTop = map.number("backgroundTop") ?: 0.0,
                backgroundRight = map.number("backgroundRight") ?: 0.0,
                backgroundBottom = map.number("backgroundBottom") ?: 0.0,
                backgroundRadius = map.number("backgroundRadius") ?: 0.0,
            )
        }

        private fun Map<*, *>.number(key: String): Double? {
            return (this[key] as? Number)?.toDouble()
        }

        /**
         * A speed multiplier, never zero or negative.
         *
         * A speed divides a duration, so a zero from a half-initialised model
         * would make a window infinitely long — the animation would freeze on
         * its first frame for the whole overlay rather than fail visibly.
         */
        private fun Map<*, *>.positiveRate(key: String): Double {
            val value = number(key) ?: return 1.0
            return if (value > 0.0) value else 1.0
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
