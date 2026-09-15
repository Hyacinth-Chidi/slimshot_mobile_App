package com.techfamz.slimshotai.nativepreview.gl.effects

/**
 * GLSL fragments every timed effect shares, pasted into their sources.
 *
 * **String interpolation, not a `#include`** — GLSL ES 1.00 has no preprocessor
 * include, and the shaders here are Kotlin strings anyway, so composing them is
 * a concatenation. `TransitionShaders` already builds its variants this way.
 *
 * What lives here is what more than one effect must agree on. Three things
 * qualify, and each is a bug this codebase has already made once somewhere:
 *
 * * **Easing.** A dozen intros that each wrote their own settle curve would
 *   settle at a dozen different rates, and "the zooms feel different from each
 *   other" is not a report anyone can act on.
 * * **Sampling outside the frame.** A shake, a roll and a slide all move the
 *   picture off its own edge, and what shows there has to be the background
 *   rather than `GL_CLAMP_TO_EDGE`'s smear of the edge texel — a smear reads as
 *   the effect being broken.
 * * **Determinism.** Shake is a hash of the clock, never `Random()`. The text
 *   animation port already hit this: preview and export must agree frame for
 *   frame, and a random number generator cannot.
 */
internal object EffectShaderLib {

    /**
     * Easing, aspect correction and off-frame sampling.
     *
     * Every timed effect's shader begins with this. It declares nothing — no
     * uniforms, no varyings — so it composes with any of them.
     *
     * GLSL ES 1.00 throughout: no `in`/`out`, no `texture`, no loops, and every
     * function takes and returns only the types ES 2.0 defines.
     */
    const val COMMON = """
// --- easing ---------------------------------------------------------------
//
// **Every intro settles on the same curve.** An intro's whole job is to arrive
// and stop, so what the eye judges is the last 20% — a linear ramp stops dead
// and reads as a jump even though the numbers arrive exactly where they should.
// This is the standard cubic ease-out: fast at the start, asymptotically slow
// into its endpoint.
//
// `easeOut(1.0)` is exactly 1.0, which is not a nicety: a timed effect's
// settled state is `p == 1` producing the untouched frame, and a curve landing
// on 0.999 leaves a permanent sub-pixel offset on every clip carrying an intro.
float easeOut(float p) {
    float inv = 1.0 - p;
    return 1.0 - inv * inv * inv;
}

// Ease in and out — for effects that start still, move, and end still, where an
// ease-out alone would start with a jolt.
float easeInOut(float p) {
    return p * p * (3.0 - 2.0 * p);
}

// --- aspect ---------------------------------------------------------------
//
// Texture coordinates are 0..1 on both axes whatever the frame's shape, so a
// distance measured in them is a distance in a stretched space: a "circular"
// reveal on a 9:16 canvas would be an egg, and a shake of equal amplitude would
// travel visibly further horizontally than vertically.
//
// Scaling the *short* axis up to match keeps the correction a ratio, so it is
// identical in a 400px preview and a 1080p export. Returns the multiplier that
// takes a centred UV into a square space; divide by it to come back.
vec2 aspectScale(float aspect) {
    vec2 scale = vec2(1.0);
    if (aspect > 1.0) {
        scale.y = 1.0 / aspect;
    } else if (aspect > 0.0) {
        scale.x = aspect;
    }
    return scale;
}

// --- sampling -------------------------------------------------------------
//
// **Off the frame is background, never a smeared edge texel.**
//
// The scene target is `GL_CLAMP_TO_EDGE`, so a coordinate outside 0..1 repeats
// the border pixel — a streak of whatever happened to be on the edge, dragged
// across the picture. On a zoom that never happens; on a shake, a roll or a
// slide it happens on every frame, and it reads as the effect being broken
// rather than as the frame having moved.
//
// Black is the honest answer and it is also the consistent one: the lanes
// letterbox against the project background and the composite is already opaque,
// so a frame moved off its own edge reveals the same black the bars are.
//
// Alpha is carried from the sample and forced to the scene's own opacity
// outside, so the bars never become translucent against whatever the output
// surface holds — the mistake `FadeInPass` documents.
vec4 sampleFrame(sampler2D tex, vec2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }
    return texture2D(tex, uv);
}

// --- determinism ----------------------------------------------------------
//
// **A hash of the clock, never `Random()`.** Export renders faster than
// realtime, so anything self-timed or stateful draws a different picture in the
// file than on the canvas — the single most repeated bug class in this codebase,
// and exactly what `TextAnimationCurves` is a pure function of a position for.
// A shake seeded from a hash of `uProgress` is reproducible frame for frame on
// any device at any rate.
//
// The classic sin-fract hash. `mediump` is enough because the input is bounded
// 0..1 and scaled by small constants, so the argument to `sin` never reaches the
// magnitudes where a low-precision `sin` loses its periodicity.
float hash11(float n) {
    return fract(sin(n * 127.1) * 43758.5453);
}

// Two independent values from one seed, for a 2D displacement. Offsetting the
// seed rather than hashing the hash keeps the two axes uncorrelated — chaining
// produces a visible diagonal drift.
vec2 hash21(float n) {
    return vec2(hash11(n), hash11(n + 71.7));
}

// --- zoom -----------------------------------------------------------------
//
// Samples the frame magnified by [scale] about its centre.
//
// Scale > 1 magnifies (a push in), scale < 1 shrinks. Because it divides the
// centred coordinate, `scale == 1.0` is exactly the identity — no rounding, no
// residual offset — which is what lets a zoom intro settle into a picture that
// is byte-for-byte the unaffected frame.
vec2 zoomUv(vec2 uv, float scale, vec2 centre) {
    return (uv - centre) / max(scale, 0.001) + centre;
}
"""
}
