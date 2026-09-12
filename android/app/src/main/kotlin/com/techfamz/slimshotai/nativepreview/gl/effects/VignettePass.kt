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
         * Distance is measured in the aspect-corrected space the shader builds,
         * where the frame's **short** half-axis is 0.5, so the corners of a 9:16
         * frame sit near 0.95. Starting at 0.25 leaves the subject — which on a
         * short-form video is centred by construction — untouched while the
         * edges fall away.
         */
        const val INNER_RADIUS = 0.25f

        /** Where the darkening reaches its full depth. Past the corners, so the corners are not flat black. */
        const val OUTER_RADIUS = 0.95f

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
         * **The distance is aspect-corrected.** Measuring straight in texture
         * coordinates measures a space where one unit across is not one unit
         * down, so on a 9:16 canvas the vignette would be a tall ellipse hugging
         * the sides — visibly not a vignette. Dividing the shorter axis by the
         * aspect puts both axes in the same units, which also makes the shape
         * identical in a 400px preview and a 1080p export: the correction is a
         * ratio, not a pixel count.
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
    // Both axes into the short side's units, so the falloff is a circle on the
    // canvas rather than an ellipse stretched by the frame's shape.
    if (uAspect > 1.0) {
        centred.y /= uAspect;
    } else if (uAspect > 0.0) {
        centred.x *= uAspect;
    }
    float dist = length(centred);
    float falloff = smoothstep($INNER_RADIUS, $OUTER_RADIUS, dist);
    float darken = 1.0 - falloff * uIntensity * $MAX_DARKEN;
    gl_FragColor = vec4(color.rgb * darken, color.a);
}
"""
    }
}
