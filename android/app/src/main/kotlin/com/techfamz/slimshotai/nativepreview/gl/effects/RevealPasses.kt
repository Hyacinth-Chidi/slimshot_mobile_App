package com.techfamz.slimshotai.nativepreview.gl.effects

/*
 * Reveals: the clip appears from black over its opening.
 *
 * **These are not transitions, and the difference is the whole reason they
 * exist.** A transition is an overlap between two clips — two live decoders,
 * a window resolved by the Dart composer, and by definition something to
 * blend *from*. A reveal is a property of one clip, so it works on the very
 * first clip of a timeline, where there is no previous clip and a transition
 * is meaningless. That is exactly the case a user opening a video wants.
 *
 * Every one of them is the same shape: compute a 0..1 coverage from the
 * pixel's position and the clock, and mix the frame against black. Two rules
 * they all follow:
 *
 * * **Fully revealed at p == 1, by construction.** `mix(black, frame, 1.0)` is
 *   exactly the frame. Each coverage function is written so it is >= 1
 *   everywhere at p == 1 before the clamp, never merely approaching it — a
 *   reveal that ends at 0.99 leaves a permanent 1% veil over the clip.
 * * **A soft edge, not a hard one.** A step function makes the reveal's border
 *   a single-pixel line that crawls with the compression noise underneath it;
 *   `smoothstep` over a small band reads as an edge and does not shimmer. The
 *   band is a fraction of the frame, so it is the same width at preview and
 *   export resolution.
 *
 * Alpha is carried from the sample throughout. The lanes composite a
 * letterboxed frame and the bars must stay exactly as opaque as the composite
 * made them — fading alpha would reveal whatever is behind the canvas rather
 * than black.
 *
 * GL thread only.
 */

/**
 * Two halves part vertically: the top half rises, the bottom falls.
 *
 * The black is what moves, not the picture — the frame stays put and is
 * uncovered, which is what a shutter opening looks like.
 */
internal class ShutterPass(program: FullFrameProgram) :
    SingleFramePass("shutter", program) {

    internal companion object {
        /** Softness of the parting edge, as a fraction of the frame's height. */
        const val EDGE = 0.04f

        /**
         * **Intensity is how much of the frame the shutter starts across.** At 1
         * the halves meet in the middle and the frame opens fully black; below
         * it they start already parted, so a strip of picture is visible from
         * the first frame. Mapping intensity onto the *duration* instead was
         * rejected for the reason `fade_in` documents — the window is the
         * catalog's to state, and an effect redefining its own length would put
         * two answers in the timeline for how long the intro runs.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);

    // Distance from the centre line, 0 at the middle and 0.5 at either edge.
    float fromCentre = abs(vTexCoord.y - 0.5);
    // How far the halves have travelled. Starts at `1 - uIntensity` of the way
    // open and eases to fully open; the +EDGE overshoot guarantees the soft
    // band has cleared the frame's edge at p == 1 rather than leaving a faint
    // line along the top and bottom.
    float open = mix(1.0 - uIntensity, 1.0, easeInOut(uProgress)) * (0.5 + ${EDGE});

    float cover = smoothstep(open - ${EDGE}, open, fromCentre);
    // cover == 1 where the shutter still covers, 0 where it has passed.
    gl_FragColor = vec4(color.rgb * (1.0 - cover), color.a);
}
"""
    }
}

/**
 * The same parting, left and right.
 *
 * Its own entry rather than an axis uniform on [ShutterPass]: the two are
 * different choices a user makes from a tile, and an axis parameter would have
 * to be surfaced somewhere — a second slider for a binary choice.
 */
internal class HorizontalOpenPass(program: FullFrameProgram) :
    SingleFramePass("horizontal_open", program) {

    internal companion object {
        /** Softness of the parting edge, as a fraction of the frame's width. */
        const val EDGE = 0.04f

        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);
    float fromCentre = abs(vTexCoord.x - 0.5);
    float open = mix(1.0 - uIntensity, 1.0, easeInOut(uProgress)) * (0.5 + ${EDGE});
    float cover = smoothstep(open - ${EDGE}, open, fromCentre);
    gl_FragColor = vec4(color.rgb * (1.0 - cover), color.a);
}
"""
    }
}

/**
 * A circle opens from the centre.
 *
 * **The circle is a circle on any canvas shape**, which is the one thing that
 * makes this harder than the shutters: a radius measured in raw UV on a 9:16
 * frame is an ellipse — the same correction `fisheye` and the vignette's own
 * note are about, except here the circular figure is what is wanted rather than
 * the frame-shaped one.
 */
internal class CircleInPass(program: FullFrameProgram) :
    SingleFramePass("circle_in", program) {

    internal companion object {
        /** Softness of the opening edge, as a fraction of the half-diagonal. */
        const val EDGE = 0.06f

        /**
         * How far the circle must travel to clear the frame.
         *
         * In the aspect-corrected space the frame's corners sit at the
         * half-diagonal, which for a 9:16 canvas is further from the centre than
         * the half-width. Overshooting past 1 is what guarantees the corners are
         * uncovered at p == 1 — a radius stopping at the short half-axis would
         * leave four dark corners on the settled clip permanently.
         */
        const val MAX_RADIUS = 1.6f

        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);

    // Into a space where a circle is a circle, then normalised so the short
    // half-axis is 1.0 — the radius below then means the same thing whatever
    // the canvas is.
    vec2 scaleVec = aspectScale(uAspect);
    float dist = length((vTexCoord - vec2(0.5)) * scaleVec) * 2.0;

    // Starts at `1 - uIntensity` of the way open, and overshoots past the
    // corners so nothing is left covered when it settles.
    float radius = mix(1.0 - uIntensity, 1.0, easeInOut(uProgress)) * ${MAX_RADIUS};
    float reveal = 1.0 - smoothstep(radius - ${EDGE}, radius, dist);
    gl_FragColor = vec4(color.rgb * reveal, color.a);
}
"""
    }
}

/**
 * Cells reveal in a grid, each on its own staggered beat.
 *
 * **The stagger is a hash of the cell, not a sweep.** A grid revealing in
 * reading order is a wipe with square edges; what makes this read as a grid is
 * the cells arriving in a scattered order. The hash is deterministic — a pure
 * function of the cell index — so preview and export reveal the same cells at
 * the same instants, the rule every shake in this codebase follows for the same
 * reason.
 */
internal class GridPass(
    id: String,
    program: FullFrameProgram,
) : SingleFramePass(id, program) {

    internal companion object {
        /**
         * Cells across the frame's short side.
         *
         * Five, so a 9:16 canvas is roughly 5x9. Few enough that each cell is a
         * legible block rather than a pixelation, which is `pixel_in`'s job.
         */
        const val CELLS = 5.0f

        /**
         * How much of the window the stagger occupies.
         *
         * At 0.6 the last cell starts at 60% of the window and has the remaining
         * 40% to finish, so every cell is fully revealed by p == 1 — the settle
         * guarantee. A stagger of 1.0 would have the last cell starting exactly
         * as the window ends and it would never appear.
         */
        const val STAGGER = 0.6f

        /**
         * A denser grid: more, smaller cells.
         *
         * `grid_collage` is the same shader with a different cell count, which
         * is why [GridPass] takes its id — the two are one implementation and a
         * second copy would drift.
         */
        const val COLLAGE_CELLS = 9.0f

        /**
         * The grid reveal.
         *
         * Each cell fades up over its own window rather than popping, so the
         * reveal reads as cells arriving rather than as a strobe — and a fade is
         * also what keeps the effect legible at a small cell count, where a pop
         * is a very hard edge.
         */
        fun fragmentFor(cells: Float) = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);

    // Square cells on any canvas shape: dividing raw UV would make them as
    // oblong as the frame is.
    vec2 scaleVec = aspectScale(uAspect);
    vec2 square = (vTexCoord - vec2(0.5)) / scaleVec;
    vec2 cell = floor(square * ${cells});

    // Deterministic per-cell stagger. Folding the two axes into one scalar
    // before hashing keeps neighbouring cells uncorrelated, which is what makes
    // the order read as scattered rather than as a diagonal sweep.
    float seed = hash11(cell.x * 37.0 + cell.y * 91.0);
    // Intensity scales how spread out the stagger is: at 0 every cell arrives
    // together, which is a plain fade.
    float start = seed * ${STAGGER} * uIntensity;
    // Each cell has from its own start to the end of the window. The `max`
    // keeps the divisor away from zero when a cell starts at the very end.
    float span = max(1.0 - start, 0.0001);
    float local = clamp((uProgress - start) / span, 0.0, 1.0);

    // `local` is 1 for every cell at p == 1 — the settle guarantee — so the
    // whole frame is exactly itself.
    gl_FragColor = vec4(color.rgb * easeOut(local), color.a);
}
"""
    }
}

/**
 * A spinning wipe: a radial sweep uncovers the frame like a hand going round.
 *
 * The angular counterpart of [CircleInPass] — that one grows a radius, this one
 * sweeps an angle. `atan` is available in GLSL ES 1.00 in its two-argument form,
 * which is what gives the full -pi..pi range a sweep needs.
 */
internal class RoulettePass(program: FullFrameProgram) :
    SingleFramePass("roulette", program) {

    internal companion object {
        /** Softness of the sweeping edge, in radians. */
        const val EDGE = 0.25f

        /**
         * How many turns the sweep makes.
         *
         * One. More than one turn means the frame is revealed and then revealed
         * again, which is invisible — the second pass has nothing left to
         * uncover.
         */
        const val TURNS = 1.0f

        /**
         * The radial wipe.
         *
         * **The angle is measured in the aspect-corrected space.** Without it
         * the sweep would move visibly faster across the frame's short axis, so
         * the "hand" would appear to accelerate and slow twice per turn on a
         * 9:16 canvas.
         *
         * The `+ EDGE` overshoot on the sweep guarantees the soft band has
         * passed the final angle at p == 1, so no thin dark wedge survives on
         * the settled clip.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);

    vec2 scaleVec = aspectScale(uAspect);
    vec2 centred = (vTexCoord - vec2(0.5)) * scaleVec;

    // 0 at twelve o'clock, increasing clockwise, in 0..2pi. Shifting the
    // `atan` range rather than using it raw puts the sweep's start at the top,
    // which is where a dial's hand starts.
    float angle = atan(centred.x, centred.y);
    if (angle < 0.0) {
        angle = angle + 6.2831853;
    }

    // Eased so the sweep does not stop dead. The overshoot clears the soft band
    // past the end of the turn.
    float swept = easeInOut(uProgress) * (${TURNS} * 6.2831853 + ${EDGE} * 2.0);
    float reveal = smoothstep(swept - ${EDGE}, swept, angle);
    // `reveal` is 1 where the sweep has not reached: invert to uncover behind
    // it. Intensity dials how much of the frame starts covered at all.
    gl_FragColor = vec4(color.rgb * (1.0 - reveal * uIntensity), color.a);
}
"""
    }
}
