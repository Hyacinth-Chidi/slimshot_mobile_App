package com.techfamz.slimshotai.nativepreview

/**
 * One clip as resolved by the Dart timeline composer.
 *
 * Source ranges are **whole** — nothing is trimmed to make room for a
 * transition. Two clips joined by a transition overlap in timeline time and are
 * assigned different [laneIndex] values so both can decode at once.
 */
internal data class NativeTimelineClip(
    val id: String,
    val sourceVideoPath: String,
    val playbackVideoPath: String,
    val sourceStart: Double,
    val sourceEnd: Double,
    val timelineStart: Double,
    val timelineEnd: Double,
    val speed: Double,
    /**
     * This clip's own gain, and how it varies across the clip.
     *
     * An [AnimatableDouble] so a diamond can fade a clip without touching the
     * project master. **Resolve it through [volumeAt] against [clipProgressAt],
     * per frame** — reading it flat would play a keyframed fade at one level.
     */
    val volume: AnimatableDouble,
    val isReversed: Boolean,
    val hasPreparedProxy: Boolean,
    val needsReverseProxy: Boolean,
    val laneIndex: Int,
    val isImage: Boolean,
    val sourceWidth: Double,
    val sourceHeight: Double,
    /**
     * This clip's own colour filter, in Flutter's 4x5 `ColorFilter.matrix`
     * layout with the offsets on a 0-255 scale, or null when ungraded.
     *
     * Applied to this clip before a transition blends it, so two clips carrying
     * different filters cross-fade between their looks. The project-wide filter
     * is separate and is applied once to the finished frame.
     */
    val colorMatrix: FloatArray?,
    /**
     * The user's pinch scale on top of the contain fit — 1.0 is the plain fit,
     * above it crops toward fill, below it shrinks into the background.
     */
    val canvasScale: AnimatableDouble,
    /** Where the clip's centre is dragged to, offset from canvas centre. */
    val canvasOffsetX: AnimatableDouble,
    val canvasOffsetY: AnimatableDouble,
    /**
     * Rotation about the clip's own centre, in **degrees** as the model stores
     * it. Resolve through [canvasRotationAt]; the renderer converts to radians
     * once, at the uniform.
     */
    val canvasRotation: AnimatableDouble,
    /**
     * This clip's visual effect, as an id from `effect_catalog.dart`, or null
     * for an unaffected clip — which is every project written before effects
     * existed and every clip the user has not touched.
     *
     * **An id this build does not know degrades to no effect**, the same rule
     * unknown transition names already follow: `EffectShaders.passesFor`
     * returns an empty list, so a draft from a newer build opens and plays
     * rather than crashing. Nothing is validated here.
     */
    val effectId: String?,
    /**
     * How strongly [effectId] is applied, **normalised 0..1, never pixels**,
     * and how that strength varies across the clip.
     *
     * A pixel parameter renders differently in the capped preview canvas and in
     * a 1080p export, so the file would not match the canvas the user approved
     * — the mismatch this codebase has already hit with overlay geometry and
     * with text raster density. Each shader turns this fraction into whatever
     * units it needs, against the viewport it is actually drawing.
     *
     * An [AnimatableDouble] rather than a bare number, so the strength may be
     * shaped by a named envelope or by keyframes. **Resolve it through
     * [effectIntensityAt], per frame, against the same progress the shader is
     * given** — there is no second uniform and no animation inside the shaders.
     * A parameter carrying neither envelope nor keyframes resolves flat at
     * every progress, which is exactly what the scalar this replaced did, so an
     * unanimated clip draws byte for byte as it always has.
     */
    val effectIntensity: AnimatableDouble,
    /**
     * The window [effectId]'s animation plays across, in seconds from this
     * clip's first frame, or null when the effect is a static look.
     *
     * Resolved by the Dart composer from `effect_catalog.dart`, never decided
     * here: the catalog is the single source of truth for what effects are, and
     * a second table of intro lengths in Kotlin is how the panel and the
     * renderer drift into disagreeing about how long an intro runs. The
     * renderer is told the window and never has to know which ids are intros.
     */
    val effectIntroSeconds: Double?,
) {
    /** Shape of this clip's own frame, or zero when it could not be probed. */
    val sourceAspect: Double
        get() = if (sourceWidth <= 0.0 || sourceHeight <= 0.0) {
            0.0
        } else {
            sourceWidth / sourceHeight
        }

    val timelineDuration: Double
        get() = timelineEnd - timelineStart

    /**
     * This clip's 0..1 position at [timelineSeconds] — **whole-clip, and the
     * same for every keyframable property**.
     *
     * A diamond is one instant of the *clip*, so every property has to measure
     * progress the same way; otherwise one diamond would sit at two different
     * places depending on which property was asked.
     *
     * Distinct from [effectProgressAt], which measures across an effect's intro
     * window. Both exist on purpose: that is the *effect's* clock, a different
     * quantity that happens to share a range.
     *
     * A zero-length clip is 0, not a division by zero.
     */
    fun clipProgressAt(timelineSeconds: Double): Double {
        val d = timelineDuration
        if (d <= 0.0) return 0.0
        return ((timelineSeconds - timelineStart) / d).coerceIn(0.0, 1.0)
    }

    /** This clip's gain at [progress], clamped to what a player will accept. */
    fun volumeAt(progress: Double): Double = volume.resolveAt(progress).coerceIn(0.0, 1.0)

    /** The pinch scale at [progress], clamped to the range the gesture allows. */
    fun canvasScaleAt(progress: Double): Double =
        canvasScale.resolveAt(progress).coerceIn(0.05, 16.0)

    /** The drag offsets at [progress]. */
    fun canvasOffsetXAt(progress: Double): Double = canvasOffsetX.resolveAt(progress)

    fun canvasOffsetYAt(progress: Double): Double = canvasOffsetY.resolveAt(progress)

    /** The rotation at [progress], in degrees. Unclamped: any angle is a valid angle. */
    fun canvasRotationAt(progress: Double): Double = canvasRotation.resolveAt(progress)

    /**
     * How far this clip's effect has played at [timelineSeconds], 0 at the
     * first frame of its window and 1 at the last, clamped outside it.
     *
     * **This is the effect clock, and it comes off the timeline** — never a
     * frame counter and never `System.nanoTime`. Export runs faster than
     * realtime and preview runs at whatever rate the device manages, so
     * anything self-timed draws a different picture in the file than on the
     * canvas: the single most repeated bug class in this codebase, and the
     * reason `TextAnimationCurves` is a pure function of a position too. Both
     * engines already hold the timeline position at the call site, so the clock
     * costs nothing but this division.
     *
     * The window is [effectIntroSeconds] when the effect declares one, and the
     * whole clip otherwise:
     *
     * * **An intro** reaches 1 after its own seconds and **stays there** for
     *   the rest of the clip. That is what "plays once and settles" means — the
     *   shader's `p == 1` is its resting state, so the clip is left looking
     *   untouched without the effect having to be taken off it. A clip shorter
     *   than the window simply ends before progress reaches 1, which cuts the
     *   intro off with the clip rather than playing it at a different speed.
     * * **A static look** gets progress across the whole clip and ignores it.
     *   Every effect written before this existed is in that case, which is why
     *   adding the clock changes nothing about how they draw.
     *
     * A zero or negative window is 1, not a division by zero: a clip with no
     * length is already over, so its animation has finished. Returning 0 would
     * park a `fade_in` on black for as long as that clip was on screen.
     */
    fun effectProgressAt(timelineSeconds: Double): Double {
        val window = effectIntroSeconds ?: timelineDuration
        if (window <= 0.0) return 1.0
        return ((timelineSeconds - timelineStart) / window).coerceIn(0.0, 1.0)
    }

    /**
     * How strongly this clip's effect is drawn at [progress], clamped to the
     * 0..1 every shader expects.
     *
     * **[progress] is the effect clock — the same value passed to the shader**
     * — so the strength and the picture it shapes can never disagree, and the
     * export reaches the identical value at the identical instant of a clip
     * however fast it is running. Both engines call this with
     * `effectProgressAt(position)`, which is the number they already had.
     *
     * The clamp is here rather than at parse time because an envelope or a
     * keyframe moves the value after parsing: a keyframe row is deliberately
     * unclamped in the model (a general parameter's range is its consumer's
     * business), and a shader turning an out-of-range fraction into a sampling
     * offset would read off the frame.
     *
     * A flat parameter returns its base value at every progress, so a clip that
     * has not asked for animation is drawn exactly as it was before this
     * existed.
     */
    fun effectIntensityAt(progress: Double): Double =
        effectIntensity.resolveAt(progress).coerceIn(0.0, 1.0)

    /**
     * Source position for a given timeline instant.
     *
     * Both clips in a transition resolve their position through this from the
     * one shared clock, which is what keeps the two decoders in step.
     */
    fun sourceAt(timelineSeconds: Double): Double {
        val offset = (timelineSeconds - timelineStart) * speed
        return (sourceStart + offset).coerceIn(sourceStart, sourceEnd)
    }

    fun contains(timelineSeconds: Double): Boolean {
        return timelineSeconds >= timelineStart && timelineSeconds < timelineEnd
    }

    companion object {
        /** Shortest source span a clamped clip is given, in seconds. */
        private const val MIN_SOURCE_SPAN = 0.05

        fun fromMap(map: Map<*, *>, fallbackSource: String): NativeTimelineClip? {
            val id = map["id"] as? String ?: return null
            val sourceVideoPath = (map["sourceVideoPath"] as? String)
                ?.takeIf { it.isNotBlank() }
                ?: fallbackSource
            if (sourceVideoPath.isBlank()) return null

            val playbackVideoPath = (map["playbackVideoPath"] as? String)
                ?.takeIf { it.isNotBlank() }
                ?: (map["overrideVideoPath"] as? String)?.takeIf { it.isNotBlank() }
                ?: sourceVideoPath

            val isImage = map["isImage"] as? Boolean ?: false

            val sourceStart = map.number("sourceStart") ?: return null
            val rawSourceEnd = map.number("sourceEnd") ?: return null

            val timelineStart = map.number("timelineStart") ?: 0.0
            val speed = (map.number("speed") ?: 1.0).coerceAtLeast(0.01)
            val timelineEnd = map.number("timelineEnd")
                ?: (timelineStart + ((rawSourceEnd - sourceStart) / speed))

            // A degenerate source range must never remove the clip.
            //
            // Dropping it here left the engine playing a shorter timeline than
            // the one the editor was drawing: the clip's neighbours closed the
            // gap, so playback skipped straight past a clip the user could
            // still see. An image legitimately has no source range at all, and
            // a video can arrive mid-edit with a momentarily inverted one.
            // Both are clamped to something playable instead.
            val sourceEnd = if (rawSourceEnd > sourceStart) {
                rawSourceEnd
            } else {
                sourceStart + ((timelineEnd - timelineStart) * speed).coerceAtLeast(MIN_SOURCE_SPAN)
            }
            // Either shape the composer writes: a bare number while flat — which
            // is what every clip nobody has keyframed sends — or a map once a
            // diamond exists. The 0..1 clamp moved to [volumeAt]: a keyframe
            // changes the value after parsing, so clamping here would clamp the
            // wrong number.
            val volume = AnimatableDouble.fromWire(map["volume"], fallback = 1.0)
            val isReversed = map["isReversed"] as? Boolean ?: false
            val hasPreparedProxy = map["hasPreparedProxy"] as? Boolean
                ?: (playbackVideoPath != sourceVideoPath)

            return NativeTimelineClip(
                id = id,
                sourceVideoPath = sourceVideoPath,
                playbackVideoPath = playbackVideoPath,
                sourceStart = sourceStart,
                sourceEnd = sourceEnd,
                timelineStart = timelineStart,
                timelineEnd = timelineEnd,
                speed = speed,
                volume = volume,
                isReversed = isReversed,
                hasPreparedProxy = hasPreparedProxy,
                needsReverseProxy = map["needsReverseProxy"] as? Boolean
                    ?: (isReversed && !hasPreparedProxy),
                laneIndex = (map["laneIndex"] as? Number)?.toInt() ?: 0,
                isImage = isImage,
                sourceWidth = map.number("sourceWidth") ?: 0.0,
                sourceHeight = map.number("sourceHeight") ?: 0.0,
                colorMatrix = map.matrix("colorMatrix"),
                // The scale clamp moved to [canvasScaleAt] for the same reason
                // the intensity clamp did: a keyframe moves the value after
                // parsing.
                canvasScale = AnimatableDouble.fromWire(map["canvasScale"], fallback = 1.0),
                canvasOffsetX = AnimatableDouble.fromWire(map["canvasOffsetX"], fallback = 0.0),
                canvasOffsetY = AnimatableDouble.fromWire(map["canvasOffsetY"], fallback = 0.0),
                // Absent from every timeline composed before clips could rotate.
                canvasRotation = AnimatableDouble.fromWire(map["canvasRotation"], fallback = 0.0),
                effectId = (map["effectId"] as? String)?.takeIf { it.isNotBlank() },
                // Either shape the composer writes: a **bare number** while the
                // intensity is flat — which is what every clip sends and what
                // every timeline composed before this model sent — or a map of
                // `baseValue` / `envelope` / `keyframes` once something animates
                // it. `fromWire` reads both and falls back on anything else
                // rather than throwing, so a malformed field costs the clip its
                // intensity, never the whole timeline.
                //
                // The default is the catalog's neutral full strength, so a clip
                // carrying an id but no intensity still shows its effect. The
                // 0..1 clamp moved to [effectIntensityAt]: it has to be applied
                // to the value a frame is actually drawn with, and an envelope
                // or a keyframe can move that after this point.
                effectIntensity = AnimatableDouble.fromWire(
                    map["effectIntensity"],
                    fallback = 1.0,
                ),
                // Absent for every clip composed before the clock existed, and
                // for every static effect — both mean "measure progress across
                // the whole clip". A non-positive window is dropped rather than
                // trusted: it would otherwise be a window that ends before it
                // starts, and `effectProgressAt` would have to guess.
                effectIntroSeconds = map.number("effectIntroSeconds")
                    ?.takeIf { it > 0.0 },
            )
        }

        private fun Map<*, *>.number(key: String): Double? {
            return (this[key] as? Number)?.toDouble()
        }

        /** A 4x5 colour matrix, or null if absent or the wrong shape. */
        private fun Map<*, *>.matrix(key: String): FloatArray? {
            val values = this[key] as? List<*> ?: return null
            if (values.size < 20) return null
            return FloatArray(20) { (values[it] as? Number)?.toFloat() ?: 0f }
        }
    }
}

/**
 * Reads the clip list out of a composed timeline.
 *
 * Shared by playback and export so both walk the *same* clips. If export chose
 * its list differently it could render a timeline the user never previewed —
 * which is the failure the timeline contract exists to prevent.
 */
internal object NativeTimelineClips {

    fun fromTimeline(timeline: Map<String, Any?>): List<NativeTimelineClip> {
        val hasTransitions = (timeline["transitions"] as? List<*>)?.isNotEmpty() == true

        // Without transitions the merged playback list is the better source:
        // adjacent cuts from one file collapse into a single item, so nothing
        // is torn down at a plain split. With transitions the clips must stay
        // separate and whole, because two of them overlap.
        val rawClips = if (hasTransitions) {
            (timeline["videoClips"] as? List<*>) ?: (timeline["segments"] as? List<*>)
        } else {
            (timeline["playbackClips"] as? List<*>)
                ?: (timeline["videoClips"] as? List<*>)
                ?: (timeline["segments"] as? List<*>)
        } ?: return emptyList()

        val fallbackSource = timeline["sourceVideoPath"] as? String ?: ""
        return rawClips.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            NativeTimelineClip.fromMap(map, fallbackSource)
        }
    }
}
