package com.techfamz.slimshotai.nativepreview.gl.effects

/**
 * Bulges the frame outward from its centre, as a wide lens does.
 *
 * The template for the whole distortion family — ripple, swirl and mirror all
 * follow it. What distinguishes these from a grade is that they **perturb the
 * sampling coordinate rather than the colour**: the shader decides where to
 * read from, and the picture is otherwise untouched. Two rules fall out of that
 * and they are why this one is written now rather than with the other twelve:
 *
 * * **The perturbation is computed in an aspect-corrected space.** Texture
 *   coordinates are 0..1 on both axes whatever the frame's shape, so a radius
 *   measured in them is a radius in a stretched space — a "circular" bulge on a
 *   9:16 canvas would be an egg. The correction is a ratio, so it is identical
 *   at preview and export resolution.
 * * **The result is clamped back into 0..1 before sampling.** The scene target
 *   is `GL_CLAMP_TO_EDGE`, so an out-of-range read smears the edge texel rather
 *   than wrapping — but a fisheye pulls *inward* at the edges, and past the
 *   frame there is nothing to pull. Explicit clamping keeps the smear a
 *   deliberate edge repeat instead of relying on a texture parameter set
 *   somewhere else.
 *
 * GL thread only.
 */
internal class FisheyePass(program: FullFrameProgram) :
    SingleFramePass("fisheye", program) {

    internal companion object {
        /**
         * How much the lens bulges at intensity 1.
         *
         * The distortion is `r' = r * (1 - k * (1 - r^2))` with `k` this value
         * scaled by the intensity: the centre magnifies most and the rim is left
         * where it is, which is what a barrel distortion looks like. Past about
         * 0.6 the centre magnifies enough that the frame's corners are pulled
         * out of view entirely, so the effect reads as a crop rather than as a
         * lens.
         */
        const val MAX_STRENGTH = 0.55f

        /**
         * The barrel distortion, as one coordinate perturbation.
         *
         * GLSL ES 1.00, compiled at runtime — a mistake here is a black frame on
         * a device, never a build error. No loops, so no constant-bound
         * question; `attribute`/`varying` and `texture2D` only; an explicit
         * fragment precision, which ES 2.0 requires because it defines no
         * default `float` precision in a fragment shader.
         *
         * `mediump` is sufficient here and is the right choice: a `highp`
         * fragment precision is optional in ES 2.0, so a shader demanding it
         * fails to compile outright on a driver that does not offer it — and on
         * this app's minSdk 24 range that is a real device, not a hypothetical.
         * The coordinates are 0..1 with a smooth perturbation, so `mediump`'s
         * ~10 bits of mantissa are well inside the texel grid of even a 2K
         * frame.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uAspect;
void main() {
    vec2 centred = vTexCoord - vec2(0.5);

    // Into a space where a circle is a circle. The scale is undone after the
    // perturbation, so the frame's own shape is preserved: correcting on the
    // way in but not on the way out would squash the whole picture.
    vec2 scale = vec2(1.0);
    if (uAspect > 1.0) {
        scale.y = 1.0 / uAspect;
    } else if (uAspect > 0.0) {
        scale.x = uAspect;
    }
    vec2 corrected = centred * scale;

    // Normalised so the frame's short half-axis is 1.0 — the falloff then has
    // the same shape whatever the canvas is, instead of being anchored to a
    // radius that means something different on each.
    float radius = length(corrected) * 2.0;
    float strength = uIntensity * $MAX_STRENGTH;

    // r' < r near the centre and r' -> r at the rim: the middle of the picture
    // is magnified and the edge stays put, which is a barrel bulge. Clamping
    // the factor keeps a high intensity from folding the coordinate through
    // zero, which would mirror the centre of the frame.
    float factor = clamp(1.0 - strength * (1.0 - radius * radius), 0.05, 2.0);

    vec2 distorted = corrected * factor;
    vec2 uv = distorted / scale + vec2(0.5);

    // The scene target clamps, but saying so here makes the edge behaviour a
    // property of the effect rather than of a texture parameter set elsewhere.
    uv = clamp(uv, vec2(0.0), vec2(1.0));
    gl_FragColor = texture2D(uTexture, uv);
}
"""
    }
}
