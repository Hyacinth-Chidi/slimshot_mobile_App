package com.techfamz.slimshotai.nativepreview.gl.effects

import com.techfamz.slimshotai.nativepreview.gl.RenderTarget

/*
 * The intros that resolve rather than move: detail, colour and focus arriving.
 *
 * Nothing here perturbs geometry, so the settle guarantee is simpler than the
 * zoom family's — each is a `mix` that ends on the untouched sample. What they
 * share instead is that they must be *exactly* the untouched frame at p == 1,
 * not approximately: `mix(a, b, 1.0)` is exactly `b` in GLSL, so every one of
 * these settles by construction.
 *
 * GL thread only.
 */

/**
 * Heavy pixelation resolving to full detail.
 *
 * **The block size is a fraction of the frame, never a pixel count.** A 16-pixel
 * block is an eighth of a 128px thumbnail and a sixtieth of a 1080p export, so a
 * pixel-count parameter would make the file and the canvas different pictures —
 * the resolution-dependence rule this codebase has broken with overlay geometry
 * and text raster density. Expressed as a fraction it resolves against whatever
 * viewport is being drawn.
 */
internal class PixelInPass(program: FullFrameProgram) :
    SingleFramePass("pixel_in", program) {

    internal companion object {
        /**
         * The starting block size at intensity 1, as a fraction of the short
         * side.
         *
         * 1/14 of the frame — coarse enough that the opening frame is plainly
         * blocks rather than a soft picture, which is the whole gesture.
         */
        const val MAX_BLOCK_FRACTION = 0.07f

        /**
         * **The resolve is exponential, not linear.** Block size falls from
         * ~75px to 1px, and a linear ramp spends most of the window between 40
         * and 2 pixels where the change is barely visible, then resolves the
         * last visible step in a single frame. Interpolating the *reciprocal*
         * spends equal time at each visible doubling, which is what reads as
         * detail arriving smoothly.
         *
         * The `1.0` endpoint is the identity: at p == 1 the block is one texel
         * of the correction space, which quantises the coordinate to itself.
         * Explicitly branching to the raw sample at the end removes any doubt —
         * a settled clip must be byte-for-byte the unaffected frame, and a
         * quantisation that is only *almost* the identity would shift the whole
         * picture by half a texel forever.
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
    float eased = easeInOut(uProgress);
    if (eased >= 1.0) {
        // The settled frame, with no quantisation arithmetic at all. A block
        // size that merely rounds to the identity would leave a half-texel
        // shift on every clip carrying this effect, forever.
        gl_FragColor = texture2D(uTexture, vTexCoord);
        return;
    }

    float startBlock = ${MAX_BLOCK_FRACTION} * uIntensity;
    // Interpolating 1/size rather than size: equal time per visible doubling.
    float invStart = 1.0 / max(startBlock, 0.0001);
    float invBlock = mix(invStart, 4096.0, eased);
    float block = 1.0 / invBlock;

    // Square blocks on any canvas shape: quantising raw UV would make them as
    // oblong as the frame is.
    vec2 scaleVec = aspectScale(uAspect);
    vec2 square = (vTexCoord - vec2(0.5)) * scaleVec;
    // +0.5 * block samples the block's centre rather than its corner, so the
    // colour shown is the middle of what it represents.
    vec2 snapped = (floor(square / block) + vec2(0.5)) * block;
    vec2 uv = snapped / scaleVec + vec2(0.5);

    gl_FragColor = texture2D(uTexture, clamp(uv, vec2(0.0), vec2(1.0)));
}
"""
    }
}

/**
 * The hue sweeps round and settles on the footage's own colour.
 *
 * A rotation in YIQ chroma space rather than a full RGB-HSV-RGB round trip: the
 * conversion is two 3x3 matrix multiplies where HSV is a chain of branches and
 * divisions, and on a fragment shader running at 1080p that difference is real.
 * The result is the same rotation of the colour wheel.
 */
internal class HueShiftPass(program: FullFrameProgram) :
    SingleFramePass("hue_shift", program) {

    internal companion object {
        /** How far round the wheel it starts, in radians — a full turn at full strength. */
        const val MAX_RADIANS = 6.2831853f

        /**
         * **Ends on exactly zero rotation**, so the settled clip carries its own
         * colour: `mix(x, 0.0, 1.0)` is 0, and a zero rotation is the identity
         * matrix, so no residual cast survives the intro.
         *
         * Luminance is untouched by construction — the rotation is applied to
         * the I and Q chroma axes only, so the picture's brightness never moves
         * while its colour does.
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
    float angle = mix(${MAX_RADIANS} * uIntensity, 0.0, easeInOut(uProgress));

    // RGB to YIQ. The luma row is the NTSC one, which is what the chroma axes
    // are defined against.
    float y = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    float i = dot(color.rgb, vec3(0.596, -0.274, -0.322));
    float q = dot(color.rgb, vec3(0.211, -0.523, 0.312));

    // Rotating I and Q about the luma axis is exactly a hue rotation.
    float s = sin(angle);
    float c = cos(angle);
    float ri = i * c - q * s;
    float rq = i * s + q * c;

    vec3 rgb = vec3(
        y + 0.956 * ri + 0.621 * rq,
        y - 0.272 * ri - 0.647 * rq,
        y - 1.106 * ri + 1.703 * rq
    );
    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), color.a);
}
"""
    }
}

/**
 * Opens desaturated and the colour returns.
 *
 * The simplest of the resolve family and the one whose settle is most obviously
 * exact: a `mix` between the grey and the original that ends on the original.
 */
internal class BwFadePass(program: FullFrameProgram) :
    SingleFramePass("bw_fade", program) {

    internal companion object {
        /**
         * The Rec. 709 luma weights, not a flat average.
         *
         * An average makes pure blue as bright as pure green, so a desaturated
         * sky comes out far lighter than the eye expects and the opening frame
         * reads as washed out rather than as monochrome.
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
    float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    // How grey it starts: intensity 1 opens fully monochrome, lower opens
    // part-way desaturated.
    float startGrey = uIntensity;
    float grey = mix(startGrey, 0.0, easeInOut(uProgress));
    // `mix(a, b, 0.0)` is exactly `a`, so a settled clip is exactly its own
    // colour with no residual desaturation.
    gl_FragColor = vec4(mix(color.rgb, vec3(luma), grey), color.a);
}
"""
    }
}

/**
 * Opens blurred and resolves sharp.
 *
 * **The one intro that is not a single pass**, because a gaussian is separable
 * and a single-pass NxN blur of the same radius costs the square of the
 * samples. It reuses [BlurPass] rather than carrying a second gaussian — one
 * blur, written once, is what keeps `blur`, `glow` and this one from drifting
 * into blurring differently for no reason a reader could find.
 *
 * It maps **progress**, not intensity, onto the radius: the radius has to fall
 * to exactly zero so the settled clip is sharp, and intensity sets how blurred
 * it *starts*. That is the same division of labour `fade_in` makes — intensity
 * is how far down the effect begins, progress is how far through it is.
 *
 * Two passes, so it is [BlurPass.chain] with the radius driven per frame.
 */
internal class BlurInPass(
    private val blur: BlurPass,
) : com.techfamz.slimshotai.nativepreview.gl.EffectPass, IntensityControlled, ProgressControlled {

    override val id: String = "blur_in.${blur.id}"

    /**
     * How blurred the clip opens. `@Volatile` for the usual reason — written by
     * the timeline's thread, read on the GL thread mid-frame.
     */
    @Volatile
    private var intensity: Float = 1f

    /**
     * How far through the intro the clip is. Written **every frame**, which is
     * exactly why it is a uniform-shaped field and not a constructor argument.
     */
    @Volatile
    private var progress: Float = 0f

    override fun applyIntensity(intensity: Float) {
        this.intensity = intensity.coerceIn(0f, 1f)
        updateRadius()
    }

    override fun applyProgress(progress: Float) {
        this.progress = progress.coerceIn(0f, 1f)
        updateRadius()
    }

    /**
     * Drives [BlurPass.radiusFraction] from the two.
     *
     * A field write, no GL call — the radius is read on the GL thread at the
     * pass's next draw, which is what lets this be called per frame.
     *
     * **Ends at exactly zero.** `(1 - p)` is 0 at p == 1, and
     * [BlurPass.render] returns before drawing when the radius is zero, so the
     * settled clip goes through the blur program untouched rather than through
     * a one-tap kernel that is only nearly the identity.
     */
    private fun updateRadius() {
        val remaining = 1f - progress
        // Eased so the sharpening does not spend its last frames in the range
        // where a sub-pixel radius is indistinguishable from none.
        val eased = remaining * remaining
        blur.radiusFraction = (MAX_RADIUS_FRACTION * intensity * eased).toDouble()
    }

    override fun render(
        sourceTextureId: Int,
        target: RenderTarget?,
        viewportWidth: Int,
        viewportHeight: Int,
        passIndex: Int,
    ) {
        blur.render(sourceTextureId, target, viewportWidth, viewportHeight, passIndex)
    }

    /** Deletes the shared program. Idempotent — both halves hold the same one. */
    fun release() {
        blur.release()
    }

    internal companion object {
        /**
         * How blurred it opens, at intensity 1.
         *
         * At [BlurPass.MAX_RADIUS_FRACTION] — the density cap, where 16 taps
         * begin to band. An intro that opened blurrier than the `blur` effect
         * can honestly render would band on its first frames, which is the one
         * place a viewer is looking hardest.
         */
        const val MAX_RADIUS_FRACTION = BlurPass.MAX_RADIUS_FRACTION.toFloat()
    }
}
