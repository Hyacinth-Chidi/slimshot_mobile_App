package com.techfamz.slimshotai.nativepreview.gl.effects

/*
 * The intros that move the frame rather than scale it: spin, roll, tilt.
 *
 * All three share one problem the zoom family does not have. **Rotating or
 * sliding a picture moves parts of it off its own edge**, and what appears
 * behind it has to be the background — `sampleFrame` in [EffectShaderLib],
 * which returns opaque black outside 0..1 rather than `GL_CLAMP_TO_EDGE`'s
 * smear of the border texel. A smear reads as the effect being broken; black
 * reads as the frame having moved, which is what happened.
 *
 * Each of them zooms in slightly while it moves, so the corners that would
 * otherwise swing into view are covered for most of the animation. The zoom
 * decays to exactly 1.0 with the motion, so the settled frame is untouched —
 * the same rule the whole intro category is built on.
 *
 * **Rotation happens in an aspect-corrected space.** Rotating a centred UV
 * directly on a 9:16 canvas shears the picture instead of turning it, because
 * one unit across is not one unit down. The correction is a ratio, so it is
 * identical at preview and export resolution.
 *
 * GL thread only.
 */

/**
 * Spins in and settles.
 *
 * A full turn is deliberately not the default: at intensity 1 it is a little
 * over half a turn, which is legible as a spin in half a second where a 360
 * looks like a flicker. The slider takes it further for anyone who wants that.
 */
internal class SpinPass(program: FullFrameProgram) :
    SingleFramePass("spin", program) {

    internal companion object {
        /** Starting rotation at intensity 1, in radians — a bit over half a turn. */
        const val MAX_START_RADIANS = 3.6f

        /**
         * How far in the frame is pushed while it spins.
         *
         * A rotated rectangle's corners sweep outside its own bounds, so
         * without this the frame's corners would cut black wedges across the
         * picture for the whole spin. `sqrt(2)` would cover a square completely
         * at any angle; this is less, because covering it completely would be a
         * very obvious zoom in its own right and the wedges are only visible for
         * the first few frames at the angles that matter.
         */
        const val COVER_SCALE = 1.35f

        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    float settle = easeOut(uProgress);
    // Both the angle and the cover zoom reach exactly their resting values at
    // p == 1: `mix(x, 0.0, 1.0)` is 0 and `mix(s, 1.0, 1.0)` is 1.
    float angle = mix(${MAX_START_RADIANS} * uIntensity, 0.0, settle);
    float scale = mix(${COVER_SCALE}, 1.0, settle);

    vec2 scaleVec = aspectScale(uAspect);
    // Into a square space, so the rotation turns the picture instead of
    // shearing it, and back out afterwards.
    vec2 centred = (vTexCoord - vec2(0.5)) * scaleVec;

    float s = sin(angle);
    float c = cos(angle);
    vec2 turned = vec2(centred.x * c - centred.y * s, centred.x * s + centred.y * c);

    vec2 uv = turned / scaleVec / max(scale, 0.001) + vec2(0.5);
    gl_FragColor = sampleFrame(uTexture, uv);
}
"""
    }
}

/**
 * Rolls in horizontally: the frame travels in from the side while turning.
 *
 * A spin with a translation attached, which is what distinguishes a roll from a
 * spin — a wheel that turns without moving is spinning, not rolling. The
 * rotation direction and the travel direction are linked so it reads as
 * rolling rather than as two animations at once.
 */
internal class RollPass(program: FullFrameProgram) :
    SingleFramePass("roll", program) {

    internal companion object {
        /** How far off frame it starts, as a fraction of the frame's width. */
        const val MAX_TRAVEL = 1.0f

        /** Rotation over the whole roll, in radians — one full turn at full strength. */
        const val MAX_RADIANS = 6.2831853f

        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    float settle = easeOut(uProgress);
    float travel = mix(${MAX_TRAVEL} * uIntensity, 0.0, settle);
    float angle = mix(${MAX_RADIANS} * uIntensity, 0.0, settle);

    vec2 scaleVec = aspectScale(uAspect);
    vec2 centred = (vTexCoord - vec2(0.5)) * scaleVec;

    // The frame arrives from the left, so the sampling coordinate is pushed the
    // other way: shifting where we *read* from by +travel puts the picture at
    // -travel on screen.
    centred.x = centred.x + travel * scaleVec.x;

    float s = sin(angle);
    float c = cos(angle);
    vec2 turned = vec2(centred.x * c - centred.y * s, centred.x * s + centred.y * c);

    vec2 uv = turned / scaleVec + vec2(0.5);
    // Off frame is background: for most of a roll a large part of the quad is
    // outside the picture, and a clamped smear there would be a streak rather
    // than the frame having arrived.
    gl_FragColor = sampleFrame(uTexture, uv);
}
"""
    }
}

/**
 * Tilts in and settles — a small rotation, no travel.
 *
 * The restrained member of the family: a few degrees of lean that straightens
 * up, which is the "camera set down" gesture rather than a spin. Its own entry
 * rather than [SpinPass] at low intensity, for the same reason `super_zoom` is
 * separate from `zoom_in` — the slider has to remain usable within each.
 */
internal class TiltPass(program: FullFrameProgram) :
    SingleFramePass("tilt", program) {

    internal companion object {
        /** Starting lean at intensity 1, in radians — about 14 degrees. */
        const val MAX_START_RADIANS = 0.25f

        /**
         * The cover zoom.
         *
         * Much smaller than [SpinPass]'s because the angle is much smaller: a
         * 14-degree lean only sweeps its corners a little way out, and a large
         * cover zoom would be more visible than the tilt it is hiding.
         */
        const val COVER_SCALE = 1.12f

        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    float settle = easeOut(uProgress);
    float angle = mix(${MAX_START_RADIANS} * uIntensity, 0.0, settle);
    float scale = mix(${COVER_SCALE}, 1.0, settle);

    vec2 scaleVec = aspectScale(uAspect);
    vec2 centred = (vTexCoord - vec2(0.5)) * scaleVec;

    float s = sin(angle);
    float c = cos(angle);
    vec2 turned = vec2(centred.x * c - centred.y * s, centred.x * s + centred.y * c);

    vec2 uv = turned / scaleVec / max(scale, 0.001) + vec2(0.5);
    gl_FragColor = sampleFrame(uTexture, uv);
}
"""
    }
}

/**
 * A shake that settles to still.
 *
 * **The displacement is a hash of the clock, never `Random()`.** Export renders
 * faster than realtime, so a shake seeded from anything stateful or self-timed
 * draws different frames in the file than on the canvas — the failure the text
 * animation port already hit and the reason `TextAnimationCurves` is a pure
 * function of a position. `hash21(progress * rate)` is reproducible frame for
 * frame on any device at any rate.
 *
 * The amplitude decays to exactly zero, so the settled frame is untouched. It is
 * the intro half of [HandheldPass], which is the same displacement without the
 * decay.
 */
internal class SteadyInPass(program: FullFrameProgram) :
    SingleFramePass("steady_in", program) {

    internal companion object {
        /** Peak displacement at intensity 1, as a fraction of the frame's short side. */
        const val MAX_AMPLITUDE = 0.055f

        /**
         * How fast the jitter steps, in samples across the window.
         *
         * High enough to read as a shake rather than a wobble; the hash is
         * sampled on a continuous input, so the motion is a smooth walk between
         * hashed values rather than a per-frame teleport.
         */
        const val RATE = 26.0f

        /** How far in the frame is pushed to cover the displacement's edges. */
        const val COVER_SCALE = 1.1f

        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    // Linear decay to exactly zero: the shake has to stop, and an exponential
    // alone never reaches zero, which would leave a permanent sub-pixel jitter
    // on the settled clip.
    float decay = 1.0 - uProgress;
    float amplitude = ${MAX_AMPLITUDE} * uIntensity * decay;

    // Deterministic: a pure function of the timeline position, so preview and
    // export agree frame for frame.
    vec2 jitter = (hash21(uProgress * ${RATE}) - vec2(0.5)) * 2.0 * amplitude;

    vec2 scaleVec = aspectScale(uAspect);
    // The jitter is applied in the square space so the shake travels the same
    // distance on both axes, then taken back out.
    vec2 centred = (vTexCoord - vec2(0.5)) * scaleVec + jitter;

    float scale = mix(${COVER_SCALE}, 1.0, uProgress);
    vec2 uv = centred / scaleVec / max(scale, 0.001) + vec2(0.5);
    gl_FragColor = sampleFrame(uTexture, uv);
}
"""
    }
}
