package com.techfamz.slimshotai.nativepreview.gl.effects

import android.opengl.GLES20

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
 * * Here the displacement is **radial and scales with distance from the
 *   centre** — red pushed outward, blue pulled inward, both by an amount
 *   proportional to `r²`. The middle of the picture is left perfectly registered
 *   and the corners fringe most, which is exactly what a real lens does, because
 *   the refractive index varies with wavelength and the ray bends more the
 *   further off-axis it enters. A subject centred in a short-form frame stays
 *   sharp, and the effect reads as *glass*.
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
         * Peak channel separation at the frame's corner at intensity 1, as a
         * fraction of the frame's short side.
         *
         * Small on purpose. Fringing is an artefact the eye is extremely
         * sensitive to at edges — a couple of pixels of it at 1080 is plainly
         * visible as colour on a hard contrast boundary — so the whole usable
         * range lives under 1% of the frame. The catalog's 0.35 default lands
         * around a third of this, which is the "expensive vintage lens" amount
         * rather than the "broken render" amount.
         */
        const val MAX_SHIFT = 0.008f

        /**
         * The aberration: three samples at three radii.
         *
         * Green is sampled **unshifted** and is the reference the other two
         * fringe around. That is not an arbitrary pick — green carries ~72% of
         * the luminance, so displacing it would soften the whole picture rather
         * than colour its edges, and the result would read as being out of
         * focus instead of as fringing.
         *
         * Three `texture2D` calls at coordinates the shader computes, no loop —
         * so no constant-bound question arises.
         *
         * Alpha comes from the green (undisplaced) sample: it is the one read at
         * the pixel's own position, so the letterbox bars keep the opacity the
         * composite gave them even where the fringe would sample past an edge.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    vec2 scale = aspectScale(uAspect);
    // Into the square space, so the fringe is radially symmetric rather than as
    // oblong as the frame: on 9:16 an uncorrected radius would fringe the top
    // and bottom edges several times harder than the sides.
    vec2 centred = (vTexCoord - vec2(0.5)) * scale;

    // Normalised so the short half-axis is 1.0 and a corner is beyond it. The
    // squared radius is what makes this a *lens*: separation grows with the
    // square of the off-axis distance, so the centre is registered and the
    // corners carry all of it.
    float r2 = dot(centred * 2.0, centred * 2.0);
    float amount = ${MAX_SHIFT} * uIntensity * r2;

    // Outward for red, inward for blue — the long wavelength focuses further
    // out. A direction vector rather than a normalise, so the centre pixel
    // (where the radius is zero) cannot divide by zero; at r == 0 the offset is
    // zero anyway, which is the registered centre.
    vec2 dir = centred * 2.0;

    vec2 redUv = (centred + dir * amount) / scale + vec2(0.5);
    vec2 blueUv = (centred - dir * amount) / scale + vec2(0.5);

    // Clamped rather than backgrounded: a fringe reaching past the edge should
    // smear the border texel's colour, which is what a lens does at the rim —
    // returning black there would draw a dark outline around the whole frame.
    redUv = clamp(redUv, vec2(0.0), vec2(1.0));
    blueUv = clamp(blueUv, vec2(0.0), vec2(1.0));

    vec4 green = texture2D(uTexture, vTexCoord);
    float red = texture2D(uTexture, redUv).r;
    float blue = texture2D(uTexture, blueUv).b;

    gl_FragColor = vec4(red, green.g, blue, green.a);
}
"""
    }
}

/**
 * An unsharp mask: a 3x3 convolution that raises local contrast.
 *
 * **The only pass in this batch that reads a neighbouring texel**, which makes
 * it the only one that needs to know how big a texel is. ES 2.0 has no
 * `textureSize()`, so the step arrives as a uniform — the same arrangement
 * [BlurPass] uses, and for the same reason. It is computed from the viewport
 * actually being drawn, so one stored intensity sharpens the ~400px preview and
 * the 1080p export by the same *visible* amount rather than by the same pixel
 * count.
 *
 * **Four neighbours, not eight.** The classic sharpen kernel is the 4-connected
 * laplacian (`-1` on each of N/S/E/W, `+5` at the centre), and the 8-connected
 * variant costs four more texture reads to produce a halo that is slightly
 * rounder and, at the amounts anyone would actually leave on, indistinguishable.
 * On the low-end target four reads is the right trade.
 */
internal class SharpenPass(program: FullFrameProgram) :
    SingleFramePass("sharpen", program) {

    /**
     * Where the texel step lands in the linked program.
     *
     * Looked up once at construction, like [GlowCompositePass] does with its two
     * samplers — `glGetUniformLocation` is a string lookup into the driver's
     * table and doing it per frame is work in the render path for a value that
     * cannot change.
     */
    private val uTexelStep = program.location("uTexelStep")

    /**
     * Supplies the step for the frame being drawn.
     *
     * **The denominator is the output viewport**, which is also the size of the
     * texture being sampled: the chain's ping-pong targets are allocated at
     * exactly the output size, so one texel of the source is one pixel of the
     * destination. That identity is what makes this correct without the pass
     * being told the source texture's dimensions, which it has no way to query.
     */
    override fun bindExtraUniforms(viewportWidth: Int, viewportHeight: Int) {
        GLES20.glUniform2f(
            uTexelStep,
            1f / viewportWidth.toFloat(),
            1f / viewportHeight.toFloat(),
        )
    }

    internal companion object {
        /**
         * Kernel strength at intensity 1.
         *
         * An unsharp mask amplifies whatever the source already has, **including
         * its noise and its compression artefacts** — and the footage this app
         * edits is phone video, which has plenty of both. Past about 1.0 a
         * clip's mosquito noise around hard edges sharpens into visible
         * speckle and the block boundaries of the encoder start to show, which
         * is damage rather than detail. 0.9 keeps the ceiling just inside that.
         */
        const val MAX_AMOUNT = 0.9f

        /**
         * The unsharp mask.
         *
         * `centre * (1 + 4k) - (n + s + e + w) * k` is the 4-connected laplacian
         * sharpen with `k` the strength: the kernel sums to exactly 1 at every
         * `k`, which is what keeps the frame's overall brightness unchanged. A
         * kernel that did not sum to 1 would lighten or darken the picture in
         * proportion to the slider, and that reads as an exposure bug rather
         * than as sharpening.
         *
         * **Clamped to 0..1 at the end**, which a blur never needs: sharpening
         * overshoots by construction — that overshoot *is* the crisp edge — so
         * a bright pixel beside a dark one produces a value above 1. The render
         * target is an 8-bit texture and would clamp anyway, but doing it here
         * means the result is the same on a driver that gives an intermediate
         * float more range, and it keeps a negative from wrapping.
         *
         * Alpha is the centre sample's, untouched. Sharpening alpha would put a
         * halo of translucency along the letterbox seam.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform vec2 uTexelStep;
void main() {
    vec4 centre = texture2D(uTexture, vTexCoord);

    // Four neighbours, one texel out on each axis. No loop — four named reads
    // are clearer here and sidestep the constant-bound question entirely.
    vec3 north = texture2D(uTexture, vTexCoord + vec2(0.0, uTexelStep.y)).rgb;
    vec3 south = texture2D(uTexture, vTexCoord - vec2(0.0, uTexelStep.y)).rgb;
    vec3 east = texture2D(uTexture, vTexCoord + vec2(uTexelStep.x, 0.0)).rgb;
    vec3 west = texture2D(uTexture, vTexCoord - vec2(uTexelStep.x, 0.0)).rgb;

    float k = uIntensity * $MAX_AMOUNT;

    // Sums to 1 at every k: (1 + 4k) - 4k. The picture's average brightness is
    // therefore unchanged whatever the slider is doing.
    vec3 sharp = centre.rgb * (1.0 + 4.0 * k) - (north + south + east + west) * k;

    gl_FragColor = vec4(clamp(sharp, vec3(0.0), vec3(1.0)), centre.a);
}
"""
    }
}
