package com.techfamz.slimshotai.nativepreview.gl.effects

import android.opengl.GLES20
import com.techfamz.slimshotai.nativepreview.gl.EffectPass
import com.techfamz.slimshotai.nativepreview.gl.RenderTarget

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
 * One half of glow's blur, with the intensity mapped onto its radius.
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
 * Delegates everything else, so the chain sees an ordinary pass.
 */
internal class GlowBlurPass(
    private val blur: BlurPass,
) : EffectPass by blur, IntensityControlled {

    override fun applyIntensity(intensity: Float) {
        val clamped = intensity.coerceIn(0f, 1f)
        blur.radiusFraction = (
            MIN_RADIUS_FRACTION + (MAX_RADIUS_FRACTION - MIN_RADIUS_FRACTION) * clamped
            ).toDouble()
    }

    /** Deletes the shared program. Idempotent — both halves hold the same one. */
    fun release() {
        blur.release()
    }

    internal companion object {
        /** Bloom radius at intensity 0, as a fraction of the frame's short side. */
        const val MIN_RADIUS_FRACTION = 0.003f

        /**
         * Bloom radius at intensity 1.
         *
         * Kept inside [BlurPass.MAX_RADIUS_FRACTION], which is where the 16-tap
         * kernel starts to band as the stride widens. A bloom wider than this
         * wants a downsampled pass, not a coarser one.
         */
        const val MAX_RADIUS_FRACTION = 0.012f
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
