package com.techfamz.slimshotai.nativepreview.gl.effects

import android.opengl.GLES20
import kotlin.math.max
import kotlin.math.min

/*
 * The static grades: looks that change a pixel's colour without moving it, and
 * the one convolution that reads its neighbours.
 *
 * **These are the catalog's original static looks** — no `introSeconds`, so
 * `uProgress` runs across the whole clip and every one of them draws the same
 * picture at the first frame as at the last. Two of them read `uProgress`
 * anyway, and where they do it is stated at the shader; the rest declare only
 * what they use, so the unused uniform locations are -1 and the uploads are
 * no-ops.
 *
 * Every one is a [SingleFramePass], which matters for one reason beyond
 * brevity: `EffectShaders.releasePasses` already has a `is SingleFramePass`
 * branch covering the whole family, so none of these needs a release branch of
 * its own. A pass that is *not* one — a wrapper delegating the interface, as
 * `StandaloneBlurPass` does — would need its own, and would leak a program per
 * effect change without it.
 *
 * GL thread only.
 */

/**
 * Maps the picture's luminance between two colours.
 *
 * A duotone is the one grade here that discards the original hue entirely:
 * every pixel's brightness picks a point on a two-colour ramp and the chroma
 * that was there is gone. That is why it is the most easily ruined entry in the
 * catalog — a badly chosen pair does not read as a grade at all, it reads as
 * the video having been damaged — and why the palette below is a stated choice
 * rather than whatever looked fine first.
 *
 * **Luminance is Rec. 709**, the same weights the rest of the pipeline uses for
 * a monochrome (`BwFadePass`); a duotone built on an unweighted RGB average
 * makes skin and sky swap places on the ramp, because green carries most of the
 * perceived brightness and an average pretends it does not.
 */
internal class DuotonePass(program: FullFrameProgram) :
    SingleFramePass("duotone", program) {

    internal companion object {
        /**
         * The shadow colour — a deep indigo, not black.
         *
         * **The pair is teal-and-amber**, the split-tone that colour grading
         * has used for decades because it sits on the warm/cool axis the eye
         * reads as depth: cool shadows, warm highlights. It was chosen over the
         * obvious alternatives for a reason each:
         *
         * * **Not black-to-white** — that is a monochrome, which the catalog
         *   already reaches through `bw_fade`, and a duotone that greys the
         *   picture is a duotone nobody can tell is on.
         * * **Not magenta-to-cyan** — the stock "duotone" of every filter app,
         *   and squarely in the territory the quality bar calls damage: at any
         *   visible strength a face goes purple and the clip is unusable.
         *
         * Indigo rather than pure blue keeps the shadows from going electric,
         * and lifting them off 0 keeps detail in the darks that a ramp starting
         * at black would crush.
         */
        const val SHADOW_R = 0.10f
        const val SHADOW_G = 0.14f
        const val SHADOW_B = 0.29f

        /** The highlight colour — a warm sand, deliberately short of white. */
        const val HIGHLIGHT_R = 0.99f
        const val HIGHLIGHT_G = 0.86f
        const val HIGHLIGHT_B = 0.62f

        /**
         * How far toward the pure duotone intensity 1 goes.
         *
         * **Not 1.0**, and this is the difference between a grade and a poster
         * print: a full duotone has thrown away every hue in the picture, so a
         * red jacket and a green field become the same colour at the same
         * brightness. Holding a little of the original chroma at maximum keeps
         * the subject legible, and at the catalog's 0.8 default the picture is
         * unmistakably toned while still being a photograph of something.
         */
        const val MAX_MIX = 0.88f

        /**
         * The duotone, as a luminance lookup and one `mix`.
         *
         * GLSL ES 1.00, compiled at runtime — a mistake here is a black frame
         * on a device, never a build error. No loops; `varying` and `texture2D`
         * only; an explicit fragment precision, which ES 2.0 requires because it
         * defines no default `float` precision in a fragment shader.
         *
         * `uAspect` is not declared: nothing here measures a distance, so the
         * frame's shape cannot affect the result. [FullFrameProgram] uploads it
         * regardless and the location is simply -1.
         *
         * Alpha is carried through untouched, like every pass here — the lanes
         * composite a letterboxed frame and grading alpha would make the bars
         * translucent against whatever the output surface holds.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);

    // Rec. 709 luma. An unweighted average would put green and blue of equal
    // code value at the same point on the ramp, which they are nothing like
    // perceptually — skin would land in the shadows and sky in the highlights.
    float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));

    vec3 shadow = vec3($SHADOW_R, $SHADOW_G, $SHADOW_B);
    vec3 highlight = vec3($HIGHLIGHT_R, $HIGHLIGHT_G, $HIGHLIGHT_B);
    vec3 toned = mix(shadow, highlight, luma);

    // Toward the toned picture, never all the way: see MAX_MIX.
    vec3 graded = mix(color.rgb, toned, uIntensity * $MAX_MIX);
    gl_FragColor = vec4(graded, color.a);
}
"""
    }
}

/**
 * Chromatic aberration: colour fringing that grows toward the frame's edges.
 *
 * **This is the lens artefact, and `rgb_split` is the glitch one.** The two are
 * both channel displacement and would be indistinguishable if written the same
 * way, so they are deliberately built on different geometry:
 *
 * * Here the displacement is **radial and in proportion to the distance from
 *   the centre** — red magnified slightly, blue shrunk slightly, about the
 *   centre. That is lateral colour, what a real lens does: the refractive index
 *   varies with wavelength, so each colour is imaged at a slightly different
 *   magnification. The centre stays registered and the fringe widens steadily
 *   outward, and the effect reads as *glass*.
 * * `RgbSplitPass` displaces every pixel by the **same horizontal offset**
 *   whatever it is — a uniform translation of two channels, which is a signal
 *   fault, not an optical one. It reads as *damage*.
 *
 * Written as one effect with a strength parameter they would collapse into each
 * other; written as these two they are visibly different looks at the same
 * slider position, which is the point of shipping both.
 */
internal class ChromaticPass(program: FullFrameProgram) :
    SingleFramePass("chromatic", program) {

    internal companion object {
        /**
         * How much larger red is imaged than green — and blue smaller — at
         * intensity 1: the shift at a point is this times its distance from
         * the centre.
         *
         * **Linear, and larger than it was.** The first version grew with the
         * cube of the distance and peaked at 0.008, so the middle of the frame,
         * where the subject is, moved by a third of a pixel even at 100% and
         * only the top and bottom edges showed anything (device-reported: only
         * noticeable at 100%). At the catalog's 0.5 a point halfway from the
         * centre to a 1080-wide frame's side now shifts ~4px and a corner
         * ~16px — a fringe on every edge in the picture, not just the rim.
         */
        const val MAX_SPREAD = 0.03f

        /**
         * The channel shift, as a fraction of the short side, at [radius] —
         * a distance from the centre in the same units — and [intensity].
         * The shader's arithmetic, for tests.
         */
        fun shiftAt(radius: Float, intensity: Float): Float = MAX_SPREAD * intensity * radius

        /**
         * The aberration: three samples, green at the pixel and red and blue
         * scaled about the centre.
         *
         * Green is the reference because it carries ~72% of the luminance:
         * displacing it would soften the whole picture rather than colour its
         * edges. A uniform scale about the centre is the same in pixels on any
         * frame shape, so no aspect correction is needed — the shift points
         * straight out from the centre and is the same number of pixels per
         * pixel of distance across and down.
         *
         * Clamped rather than backgrounded at the border: a fringe reaching
         * past the edge smears the border texel, as a lens does at its rim —
         * black there would draw a dark outline round the frame. Alpha comes
         * from the green sample, read at the pixel itself, so the letterbox
         * keeps the opacity the composite gave it.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
void main() {
    vec2 centred = vTexCoord - vec2(0.5);
    float spread = $MAX_SPREAD * uIntensity;

    // The long wavelength is imaged larger: red out, blue in.
    vec2 redUv = clamp(vec2(0.5) + centred * (1.0 + spread), vec2(0.0), vec2(1.0));
    vec2 blueUv = clamp(vec2(0.5) + centred * (1.0 - spread), vec2(0.0), vec2(1.0));

    vec4 green = texture2D(uTexture, vTexCoord);
    float red = texture2D(uTexture, redUv).r;
    float blue = texture2D(uTexture, blueUv).b;

    gl_FragColor = vec4(red, green.g, blue, green.a);
}
"""
    }
}

/**
 * An unsharp mask on brightness: local contrast raised around a ring a fixed
 * fraction of the frame out.
 *
 * **The ring is measured in the frame, not in texels.** This used to be the
 * one-texel laplacian, and on the device it showed nothing even at 100%: the
 * preview's texture is drawn on screen smaller than it is, and shrinking a
 * picture averages a one-texel halo away — light ring and dark ring land in
 * the same screen pixel. [SAMPLE_RADIUS] puts the ring at the same fraction of
 * the short side on the ~720px preview, a 1080 export and a 2K one, so the
 * canvas and the file sharpen alike, and far enough out to survive the
 * shrink. ES 2.0 has no `textureSize()`, so the step arrives as a uniform
 * ([sampleStep]), worked out from the viewport actually being drawn.
 *
 * **Eight taps round the ring**, four on the axes and four on the diagonals,
 * so the halo is round rather than a plus sign — at a radius of a few texels
 * the four-tap cross showed its shape.
 *
 * **Brightness only, past a noise floor, with the halo limited**, because a
 * strong unsharp mask amplifies whatever phone footage carries: sharpening the
 * colour channels separately breeds colour speckle and coloured fringes, the
 * faint grain below the floor is sensor noise and encoder blocking rather than
 * detail, and an unlimited lift across a hard edge rings into a white or black
 * outline. Those three are what let the amount go well past where the old
 * kernel had to stop.
 */
internal class SharpenPass(program: FullFrameProgram) :
    SingleFramePass("sharpen", program) {

    /** Looked up once — a string lookup per frame is work for a constant. */
    private val uSampleStep = program.location("uSampleStep")

    override fun bindExtraUniforms(viewportWidth: Int, viewportHeight: Int) {
        val (stepX, stepY) = sampleStep(viewportWidth, viewportHeight)
        GLES20.glUniform2f(uSampleStep, stepX, stepY)
    }

    internal companion object {
        /**
         * The ring's radius as a fraction of the frame's short side: ~2.5
         * texels on the 720-wide preview, ~4px in a 1080 export.
         */
        const val SAMPLE_RADIUS = 0.0035f

        /**
         * Lift at intensity 1, as a multiple of the detail. The noise floor
         * and the halo limit in the shader are what make 3 usable: without
         * them past about 1 the footage's own noise sharpened into speckle.
         */
        const val MAX_AMOUNT = 3.0f

        /**
         * The ring's offset in texture coordinates for a [width] x [height]
         * viewport, per axis.
         *
         * **Never under one texel**: on a frame too small for the radius — a
         * tile cell — half a texel out samples the pixel itself and sharpens
         * nothing.
         */
        fun sampleStep(width: Int, height: Int): Pair<Float, Float> {
            val radiusPx = max(1f, SAMPLE_RADIUS * min(width, height))
            return Pair(radiusPx / width, radiusPx / height)
        }

        /**
         * The unsharp mask.
         *
         * The detail is the centre's brightness against the ring's mean, and
         * the lift is added to all three channels alike — a grey change, so no
         * colour is invented. Clamped to 0..1 at the end, since a lift
         * overshoots by construction; alpha is the centre's, untouched, or the
         * letterbox seam would take a halo of translucency.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform vec2 uSampleStep;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
// Detail fainter than this is mostly noise; it fades in across the floor
// rather than switching on, so no edge of a gradient is visible.
const float NOISE_FLOOR = 0.015;
// The most a pixel is lifted or lowered, so a hard edge gains a crisp line
// rather than a white or black outline.
const float HALO_LIMIT = 0.25;

void main() {
    vec4 centre = texture2D(uTexture, vTexCoord);

    vec2 axis = uSampleStep;
    vec2 diag = uSampleStep * 0.7071;
    vec3 ring = texture2D(uTexture, vTexCoord + vec2(axis.x, 0.0)).rgb
        + texture2D(uTexture, vTexCoord - vec2(axis.x, 0.0)).rgb
        + texture2D(uTexture, vTexCoord + vec2(0.0, axis.y)).rgb
        + texture2D(uTexture, vTexCoord - vec2(0.0, axis.y)).rgb
        + texture2D(uTexture, vTexCoord + diag).rgb
        + texture2D(uTexture, vTexCoord - diag).rgb
        + texture2D(uTexture, vTexCoord + vec2(diag.x, -diag.y)).rgb
        + texture2D(uTexture, vTexCoord + vec2(-diag.x, diag.y)).rgb;

    float detail = dot(centre.rgb - ring * 0.125, LUMA);
    float kept = detail * smoothstep(0.0, NOISE_FLOOR, abs(detail));
    float lift = clamp(kept * uIntensity * $MAX_AMOUNT, -HALO_LIMIT, HALO_LIMIT);

    gl_FragColor = vec4(clamp(centre.rgb + vec3(lift), 0.0, 1.0), centre.a);
}
"""
    }
}
