package com.techfamz.slimshotai.nativepreview.gl.effects

/**
 * Darkens the frame toward its corners.
 *
 * The simplest shape in the catalog: one sample, one multiply, no coordinate
 * perturbation and no second texture. It is deliberately the first effect
 * written, because a picture that is plainly the footage with darker corners
 * proves the whole path — the clip's `effectId` parsed, the registry resolved,
 * the scene rendered into an offscreen target, one pass run over it, the result
 * presented — in a way no more elaborate effect could, where a bug and a
 * correct render look alike.
 *
 * GL thread only.
 */
internal class VignettePass(program: FullFrameProgram) :
    SingleFramePass("vignette", program) {

    internal companion object {
        /**
         * How far from the centre the darkening begins, at full intensity.
         *
         * Distance is normalised to the half-diagonal, so **a corner is 1.0 and
         * an edge midpoint is 0.707 on any canvas shape**. Starting at 0.45
         * leaves the subject — centred by construction on a short-form video —
         * untouched while the corners fall away.
         *
         * It began at 0.25 against an aspect-corrected distance, which put the
         * corners of a 9:16 frame at only ~0.57 of the falloff range: the
         * device report was that the effect was there but "user will hardly
         * know if vignette is active".
         */
        const val INNER_RADIUS = 0.45f

        /** Full depth exactly at the corners, which [MAX_DARKEN] keeps off black. */
        const val OUTER_RADIUS = 1.0f

        /**
         * How dark the corners go at intensity 1.
         *
         * Not 1.0, and not an accident: a vignette that reaches pure black is a
         * hole in the picture rather than a look, and the catalog's own note is
         * that a first application must "read as a choice, not as damage". At
         * 0.85 the corner keeps a trace of what is in it.
         */
        const val MAX_DARKEN = 0.85f

        /**
         * The vignette, as one multiply on the sampled colour.
         *
         * GLSL ES 1.00, compiled at runtime — a mistake here is a black frame on
         * a device, never a build error:
         *
         * * `attribute`/`varying`, never `in`/`out`; `texture2D`, never `texture`.
         * * An explicit fragment precision, because ES 2.0 defines no default
         *   `float` precision in a fragment shader.
         * * No loops at all, so no constant-bound question arises.
         *
         * **The distance is deliberately NOT aspect-corrected**, and `uAspect`
         * is left declared only because [FullFrameProgram] supplies it to every
         * effect. A vignette follows the frame's own shape — a lens darkens
         * toward its corners — so a circle in UV space, which is an ellipse on
         * screen, is the correct figure. Correcting for aspect moved the
         * farthest points onto the long edges and the effect read as a band
         * across the top and bottom of a 9:16 clip.
         *
         * The shape is identical in a 400px preview and a 1080p export either
         * way: everything here is a ratio, never a pixel count.
         *
         * Alpha is carried through untouched. The lanes composite a letterboxed
         * frame, and multiplying alpha here would make the bars translucent
         * against whatever the output surface holds.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uAspect;
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);
    vec2 centred = vTexCoord - vec2(0.5);
    // **No aspect correction.** A circle in UV space is an ellipse on a
    // non-square frame, and that ellipse *is* what a vignette looks like — a
    // lens darkens toward its own corners, not in a circle inscribed in them.
    //
    // Correcting for aspect was the bug: dividing the long axis put the
    // farthest points on the long *edges* rather than the corners, so on a
    // 9:16 frame the darkening read as a band across the top and bottom. In UV
    // space every corner is equidistant and every edge midpoint is 0.707 of
    // that, on any canvas shape, which is exactly the falloff wanted.
    //
    // Normalised to the half-diagonal so a corner is 1.0 and the radii below
    // mean the same thing whatever the frame's shape.
    float dist = length(centred) / length(vec2(0.5));
    float falloff = smoothstep($INNER_RADIUS, $OUTER_RADIUS, dist);
    float darken = 1.0 - falloff * uIntensity * $MAX_DARKEN;
    gl_FragColor = vec4(color.rgb * darken, color.a);
}
"""
    }
}
