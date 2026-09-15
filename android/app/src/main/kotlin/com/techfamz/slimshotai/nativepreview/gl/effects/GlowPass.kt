package com.techfamz.slimshotai.nativepreview.gl.effects

import android.opengl.GLES20
import com.techfamz.slimshotai.nativepreview.gl.EffectPass
import com.techfamz.slimshotai.nativepreview.gl.RenderTarget
import com.techfamz.slimshotai.nativepreview.gl.createRenderTarget
import kotlin.math.max

/*
 * A soft bloom: the frame's highlights, blurred, laid back over the frame.
 *
 * The catalog calls it "Dreamy" and it is the most expensive entry there —
 * three passes, which is the reason [com.techfamz.slimshotai.nativepreview.gl.EffectPassChain]
 * exists at all. The shape is the standard one:
 *
 * ```
 *   scene ──> [bright]  ──> A ──> [blur.h] ──> B ──> [blur.v] ──> A
 *        └──────────────────────────────────────────────────────┐
 *                                            [composite(A, scene)] ──> out
 * ```
 *
 * Two things about it are worth stating plainly, because both look like
 * mistakes:
 *
 * **The chain is four passes, not three.** The catalog declares `passCount: 3`
 * — bright, blur, composite — counting the separable blur as one step, which is
 * how a person describes it. In GL a separable blur is two draws, so the real
 * list is four, exactly at `MAX_EFFECT_PASSES`. That is deliberate and it is
 * the cap's whole margin: a glow is the effect the cap was sized for.
 *
 * **The composite pass samples a texture the chain never hands it.** A pass is
 * given one source, and glow's last pass needs two — the blurred highlights
 * *and* the untouched original. The chain cannot supply both without growing an
 * interface every other effect would ignore, so the bright pass records the
 * scene texture it was handed and the composite reads it back
 * ([GlowSource]). It is correct because pass 0 is by definition the one the
 * chain gives the scene to, and it is recorded every frame, so a resize that
 * reallocates the targets is picked up without anything having to invalidate
 * it.
 *
 * GL thread only — every one of these links or draws.
 */

/**
 * One half of glow's blur, run at a **fraction of the frame's resolution**, with
 * the intensity mapped onto its radius.
 *
 * Two jobs, and the second one is the reason the bloom is visible at all.
 *
 * ### The radius, without a rebuild
 *
 * The bloom's radius scales with the intensity because that is what a user
 * dragging the slider means by "more dreamy" — a brighter bloom at a fixed
 * radius just looks overexposed. So glow's intensity has to reach [BlurPass],
 * and it has to reach it **without a rebuild**: the radius is a `@Volatile var`
 * on the pass precisely so it can be retuned between frames, and baking it in
 * at construction would put a `glLinkProgram` on every frame of a slider drag.
 *
 * A thin wrapper rather than making [BlurPass] itself [IntensityControlled]:
 * the standalone `blur` effect maps intensity onto a radius differently — it is
 * the whole effect there, not a bloom's supporting act — and one class cannot
 * hold two mappings without a mode flag deciding which is in force.
 *
 * ### The downsample, which is why the bloom can be seen
 *
 * **The bloom was invisible because it was too small, not because it was
 * broken.** [BlurPass] is a fixed 16 taps and
 * [BlurPass.MAX_RADIUS_FRACTION] caps the radius at 0.014 of the short side —
 * about 15px at 1080 — because past that the strided taps start to band. That
 * cap's reasoning is sound and raising it would trade an invisible bloom for a
 * banded one, which is worse. A halo of 12px around a highlight simply is not a
 * halo anybody notices.
 *
 * Blurring a **half-resolution copy** buys the radius back for nothing: the same
 * 16 taps span twice as many full-resolution pixels, the bilinear downsample
 * pre-smooths the picture so the taps have less high-frequency detail to alias
 * against, and the two blur draws each cost a quarter of the fragments. A bloom
 * is the one thing in the catalog that *can* be computed at a lower resolution
 * without anyone seeing it: it is by definition the low-frequency part of the
 * picture, and it is screened back over a full-resolution scene that keeps every
 * detail.
 *
 * **The texel step follows the target, not the output frame.** [BlurPass]
 * derives both its radius in pixels and its `1/width` step from the viewport it
 * is handed, which is normally the output's size. Handing it the *downscaled*
 * size instead is what makes the arithmetic self-consistent: at half resolution
 * a 15px radius is 7.5 half-res pixels sampled across a half-res texture, which
 * lands on exactly the same 15 full-res pixels — and then the scale factor is
 * pure gain. Passing the full viewport while writing a half-size target would
 * halve the step against the texture actually being sampled and give a bloom
 * *smaller* than the undownsampled one, which is the failure mode worth naming
 * because it looks like the downsample simply not working.
 *
 * ### Which half owns the scaling
 *
 * Pass `.h` allocates and writes the downscale target; pass `.v` reads it and
 * writes the chain's own full-size target. So the horizontal half does the
 * scaling down and the vertical half brings it back up — one resample each way,
 * and the composite that follows samples an ordinary full-size texture with no
 * idea any of this happened. The alternative, teaching
 * [com.techfamz.slimshotai.nativepreview.gl.EffectPassChain] to hand out scaled
 * targets, would put a concept into every single-pass effect that only a bloom
 * has any use for.
 */
internal class GlowBlurPass(
    private val blur: BlurPass,
    /**
     * True for the half that renders *into* the downscaled target.
     *
     * Only one of the pair may own it: two passes each allocating a scratch
     * buffer would double the memory for a picture that needs one.
     */
    private val ownsDownscale: Boolean,
) : EffectPass, IntensityControlled {

    override val id: String = blur.id

    /**
     * The half-resolution scratch buffer, allocated on first use at whatever
     * size the frame turns out to be and reused until that changes.
     *
     * **Never per frame.** A 540x960 RGBA target is ~2MB; churning one every
     * frame is exactly the allocation storm that turns a working effect into a
     * stutter on the low-end target, which is the same rule
     * `EffectPassChain.resize` follows.
     */
    private var downscale: RenderTarget? = null

    /**
     * Latched when the device refuses the scratch target.
     *
     * The bloom then runs at full resolution — smaller than intended, but a
     * picture — rather than disappearing. Degrading to the previous behaviour is
     * the right answer on a GL thread that cannot ask the user anything.
     */
    private var downscaleUnavailable = false

    /**
     * The pass that owns the scratch buffer, for the half that does not.
     *
     * Asked per frame rather than copied once, because the buffer is
     * reallocated on a size change and a copy taken at construction would name a
     * released target from then on.
     */
    private var downscaleProvider: GlowBlurPass? = null

    override fun applyIntensity(intensity: Float) {
        val clamped = intensity.coerceIn(0f, 1f)
        blur.radiusFraction = (
            MIN_RADIUS_FRACTION + (MAX_RADIUS_FRACTION - MIN_RADIUS_FRACTION) * clamped
            ).toDouble()
    }

    override fun render(
        sourceTextureId: Int,
        target: RenderTarget?,
        viewportWidth: Int,
        viewportHeight: Int,
        passIndex: Int,
    ) {
        if (viewportWidth <= 0 || viewportHeight <= 0) return

        // The owner allocates; the other half reads whatever the owner ended up
        // with. Asking the owner rather than holding a copy is what keeps `.v`
        // correct across a resize, which releases the old target and builds a
        // new one.
        val small = if (ownsDownscale) {
            scratchFor(viewportWidth, viewportHeight)
        } else {
            downscaleProvider?.downscale
        }

        if (small == null) {
            // No scratch buffer: the full-resolution blur, which is what this
            // effect did before the downsample existed. Both halves take this
            // path together, because `.v` only ever holds a target `.h` gave it.
            blur.render(sourceTextureId, target, viewportWidth, viewportHeight, passIndex)
            return
        }

        if (ownsDownscale) {
            // Down: read the full-size bright pass, write the half-size buffer.
            // The viewport handed on is the *target's* size, so the step and the
            // radius are both measured against the texture being written.
            blur.render(sourceTextureId, small, small.width, small.height, passIndex)
        } else {
            // Up: read the half-size buffer, write the chain's full-size target.
            // The viewport is still the small one — the texture being *sampled*
            // is what the step divides by — while `target.bind()` inside the
            // blur sets the real viewport to the full-size target's own
            // dimensions. `GL_LINEAR` on the scratch texture is what makes the
            // magnification smooth rather than blocky.
            blur.render(small.textureId, target, small.width, small.height, passIndex)
        }
    }

    /**
     * The scratch target for a [width] x [height] frame, or null if refused.
     *
     * Reallocated only when the frame's size changes — a canvas resize, or the
     * switch from preview to export dimensions.
     */
    private fun scratchFor(width: Int, height: Int): RenderTarget? {
        if (downscaleUnavailable) return null

        val smallWidth = max(1, width / DOWNSCALE)
        val smallHeight = max(1, height / DOWNSCALE)

        val existing = downscale
        if (existing != null && existing.width == smallWidth && existing.height == smallHeight) {
            return existing
        }

        existing?.release()
        downscale = null

        val created = createRenderTarget(smallWidth, smallHeight)
        if (created == null) {
            // Latched: a device that refused this size will refuse it again, and
            // retrying an allocation per frame is worse than the smaller bloom.
            downscaleUnavailable = true
            return null
        }
        downscale = created
        return created
    }

    /**
     * Hands [downscale] to the other half of the pair.
     *
     * The two halves are built together in [EffectShaders] and must agree on the
     * buffer: `.v` reads exactly what `.h` wrote. Sharing the field rather than
     * the object keeps `.v` from having to know whether `.h` succeeded — a null
     * here means both fall back to the full-resolution blur, together.
     */
    fun shareDownscaleWith(other: GlowBlurPass) {
        other.downscaleProvider = this
    }

    /**
     * Deletes the shared program and this half's scratch buffer.
     *
     * Idempotent, and safe on both halves: they hold the same [BlurProgram] —
     * whose `release` is idempotent — and only the owning half has a target to
     * drop.
     *
     * GL thread only.
     */
    fun release() {
        blur.release()
        downscale?.release()
        downscale = null
    }

    internal companion object {
        /** Bloom radius at intensity 0, as a fraction of the frame's short side. */
        const val MIN_RADIUS_FRACTION = 0.003f

        /**
         * Bloom radius at intensity 1, **measured against the downscaled
         * target**.
         *
         * Kept at [BlurPass.MAX_RADIUS_FRACTION], which is where the 16-tap
         * kernel begins to band. Because the blur now runs at 1/[DOWNSCALE] of
         * the frame, this is an effective [DOWNSCALE] x 0.014 ≈ 0.028 of the
         * short side in full-resolution terms — roughly 30px at 1080, which is a
         * halo a person actually sees — while every tap stays inside the density
         * the cap was chosen for. That is the whole trade: the same kernel,
         * twice the reach, no banding.
         */
        const val MAX_RADIUS_FRACTION = BlurPass.MAX_RADIUS_FRACTION.toFloat()

        /**
         * How much smaller the blurred copy is, per axis.
         *
         * Two, not four. A quarter-resolution bloom would reach twice as far
         * again, but the canvas is already capped at `kMaxPreviewCanvasPx` in
         * preview, so on a short-side-400 canvas a quarter is 100px — few enough
         * that the upsample itself becomes visible as softness in the bloom's
         * shape. Half is the largest step that is invisible at every size this
         * app renders, and it is already the difference between a bloom nobody
         * notices and one that reads as the effect.
         */
        const val DOWNSCALE = 2
    }
}

/**
 * Where the bright pass leaves the scene texture for the composite pass.
 *
 * A field on an object shared by the two passes, not a parameter, because the
 * chain's `render` signature is the same for every effect and widening it for
 * one would put a concept fifteen effects do not have into all of them.
 *
 * Single-threaded by construction: both passes run inside one `EffectPassChain.run`
 * on the GL thread, in order, in the same frame.
 */
internal class GlowSource {
    var sceneTextureId: Int = 0
}

/**
 * Pass 1 of glow: keeps what is bright, discards the rest.
 *
 * Also the pass that records the scene texture for [GlowCompositePass]; see the
 * class docs above for why that is here rather than in the chain.
 */
internal class GlowBrightPass(
    program: FullFrameProgram,
    private val source: GlowSource,
) : SingleFramePass("glow.bright", program) {

    override fun render(
        sourceTextureId: Int,
        target: RenderTarget?,
        viewportWidth: Int,
        viewportHeight: Int,
        passIndex: Int,
    ) {
        // Recorded before the draw and every frame, so a target reallocation —
        // a canvas resize, or the switch from preview to export dimensions —
        // reaches the composite without anything having to invalidate it.
        source.sceneTextureId = sourceTextureId
        super.render(sourceTextureId, target, viewportWidth, viewportHeight, passIndex)
    }

    internal companion object {
        /**
         * Luminance above which a pixel starts contributing to the glow, at
         * intensity 1.
         *
         * Low enough that ordinary skin and sky bloom — which is the look
         * people mean by "dreamy" — rather than only clipped highlights, which
         * on compressed phone footage are rare enough that the effect would
         * appear to do nothing on most clips.
         */
        const val MIN_THRESHOLD = 0.35f

        /** Threshold at the lowest intensity: only the brightest pixels bloom. */
        const val MAX_THRESHOLD = 0.8f

        /**
         * The bright pass.
         *
         * GLSL ES 1.00: `varying`, `texture2D`, an explicit fragment precision,
         * and no loops.
         *
         * The Rec. 709 luma weights, not a flat average: an average makes pure
         * blue as bright as pure green, so a blue sky would bloom as hard as a
         * highlight and the effect would read as a colour cast.
         *
         * **The knee is a `smoothstep`, not a hard cut.** A step function makes
         * the glow's edge follow a luminance contour exactly, and on gently
         * graded footage — a sky — that contour crawls with the compression
         * noise from frame to frame, which is visible as the bloom shimmering.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);
    float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    // A stronger effect blooms more of the picture, so the threshold falls as
    // the intensity rises.
    float threshold = mix($MAX_THRESHOLD, $MIN_THRESHOLD, uIntensity);
    float keep = smoothstep(threshold, min(threshold + 0.25, 1.0), luma);
    gl_FragColor = vec4(color.rgb * keep, 1.0);
}
"""
    }
}

/**
 * Pass 3 of glow: adds the blurred highlights back onto the original frame.
 *
 * Its own [EffectPass] rather than a [SingleFramePass] because it binds two
 * textures — the chain's source (the blurred bloom) and the recorded scene.
 */
internal class GlowCompositePass(
    private val program: FullFrameProgram,
    private val source: GlowSource,
) : EffectPass, IntensityControlled {

    override val id: String = "glow.composite"

    /**
     * Uploaded as a uniform on every draw, never baked in — see
     * [IntensityControlled] for why that distinction is the whole point.
     */
    @Volatile
    var intensity: Float = 1f
        set(value) {
            field = value.coerceIn(0f, 1f)
        }

    override fun applyIntensity(intensity: Float) {
        this.intensity = intensity
    }

    private val uBloom = program.location("uBloom")
    private val uScene = program.location("uScene")

    override fun render(
        sourceTextureId: Int,
        target: RenderTarget?,
        viewportWidth: Int,
        viewportHeight: Int,
        passIndex: Int,
    ) {
        if (viewportWidth <= 0 || viewportHeight <= 0) return

        if (target != null) {
            target.bind()
        } else {
            GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
        }

        val scene = source.sceneTextureId
        if (scene == 0) {
            // The bright pass never ran — the chain capped the list, or this
            // pass was scheduled alone by mistake. Adding a bloom to nothing
            // would blow the frame out; passing the source through leaves the
            // picture intact and merely unglowed, which is the same degradation
            // an unknown effect id takes.
            GLES20.glDisable(GLES20.GL_BLEND)
            program.use()
            program.setIntensity(0f)
            program.bindTexture(GLES20.GL_TEXTURE0, 0, uBloom, sourceTextureId)
            program.bindTexture(GLES20.GL_TEXTURE1, 1, uScene, sourceTextureId)
            program.drawQuad()
            return
        }

        GLES20.glDisable(GLES20.GL_BLEND)
        program.use()
        program.setIntensity(intensity)
        // Unit 0 is the blurred bloom the chain handed us; unit 1 is the
        // original scene the bright pass recorded.
        program.bindTexture(GLES20.GL_TEXTURE0, 0, uBloom, sourceTextureId)
        program.bindTexture(GLES20.GL_TEXTURE1, 1, uScene, scene)
        program.drawQuad()
    }

    fun release() {
        program.release()
    }

    internal companion object {
        /**
         * How much bloom is added at intensity 1.
         *
         * Screen blending saturates on its own, so this is a ceiling on how far
         * the highlights spill rather than a brightness: past roughly this the
         * picture reads as overexposed rather than as soft.
         */
        const val MAX_BLOOM = 0.9f

        /**
         * The composite.
         *
         * **Screen, not add.** `a + b` drives an already-bright highlight past
         * 1.0 and clips it to flat white, which is exactly where the glow is
         * strongest — so an additive bloom eats the detail it is supposed to
         * soften. Screen (`1 - (1-a)(1-b)`) approaches 1.0 without reaching it,
         * so a highlight keeps its shape however much bloom lands on it.
         *
         * The scene's alpha is carried through, not the bloom's: the lanes
         * composite a letterboxed frame and the bars must stay exactly as
         * opaque as the composite made them.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uBloom;
uniform sampler2D uScene;
uniform float uIntensity;
void main() {
    vec4 scene = texture2D(uScene, vTexCoord);
    vec3 bloom = texture2D(uBloom, vTexCoord).rgb * (uIntensity * $MAX_BLOOM);
    vec3 screened = vec3(1.0) - (vec3(1.0) - scene.rgb) * (vec3(1.0) - clamp(bloom, 0.0, 1.0));
    gl_FragColor = vec4(screened, scene.a);
}
"""
    }
}
