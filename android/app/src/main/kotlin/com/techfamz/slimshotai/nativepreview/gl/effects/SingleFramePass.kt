package com.techfamz.slimshotai.nativepreview.gl.effects

import android.opengl.GLES20
import com.techfamz.slimshotai.nativepreview.gl.EffectPass
import com.techfamz.slimshotai.nativepreview.gl.RenderTarget

/**
 * One pass that reads the frame once and writes it once.
 *
 * Most of the catalog is this shape — a vignette modulating colour by distance,
 * a fisheye perturbing the sampling coordinate, a grain adding noise — so the
 * per-effect code is a fragment shader and nothing else. An effect needing more
 * than a source texture and an intensity (glow's composite, which samples two)
 * writes its own [EffectPass] instead.
 *
 * The program is linked once at construction and reused for every frame:
 * `glLinkProgram` in the render path is a visible stall, which is the reason
 * `TransitionShaders.warmUpShaders` exists.
 *
 * GL thread only.
 */
internal open class SingleFramePass(
    override val id: String,
    protected val program: FullFrameProgram,
) : EffectPass, IntensityControlled, ProgressControlled {

    /**
     * The effect's strength, normalised 0..1, uploaded as a uniform on every
     * draw rather than compiled into the shader.
     *
     * `@Volatile` because the timeline thread writes it while the GL thread
     * reads it mid-frame, like every other piece of per-frame renderer state.
     * A slider drag is then a float write — no link, no thread hop, nothing to
     * block on.
     */
    @Volatile
    var intensity: Float = 1f
        set(value) {
            field = value.coerceIn(0f, 1f)
        }

    override fun applyIntensity(intensity: Float) {
        this.intensity = intensity
    }

    /**
     * How far the clip has played through this effect's window, 0..1.
     *
     * `@Volatile` for the same reason [intensity] is — written by the timeline's
     * thread, read by the GL thread mid-frame — but it moves on **every** frame
     * rather than only when a slider does, which is precisely why it is a
     * uniform and not a constructor argument.
     *
     * Every pass carries it whether its shader reads it or not: a static look's
     * program has no `uProgress`, the location is -1, and the upload is a no-op.
     */
    @Volatile
    var progress: Float = 0f
        set(value) {
            field = value.coerceIn(0f, 1f)
        }

    override fun applyProgress(progress: Float) {
        this.progress = progress
    }

    override fun render(
        sourceTextureId: Int,
        target: RenderTarget?,
        viewportWidth: Int,
        viewportHeight: Int,
        passIndex: Int,
    ) {
        if (viewportWidth <= 0 || viewportHeight <= 0) return

        // A null target means "whatever is bound", so the viewport has to be set
        // here: the pass cannot ask the bound framebuffer how big it is.
        if (target != null) {
            target.bind()
        } else {
            GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
        }

        // A pass *replaces* its target's contents, never composites onto them.
        // Blending is context state, so leaving it to whoever drew last would
        // mix the effect with whatever the ping-pong buffer held two frames ago
        // — a ghost of an old frame, which reads as the effect being wrong
        // rather than as a stray GL flag.
        GLES20.glDisable(GLES20.GL_BLEND)

        program.use()
        program.setIntensity(intensity)
        // A no-op for every shader that declares no `uProgress`, which is all of
        // the static looks — the location is -1. So the clock reaching every
        // pass costs one ignored uniform write and changes no existing picture.
        program.setProgress(progress)
        program.setAspect(viewportWidth.toFloat() / viewportHeight.toFloat())
        bindExtraUniforms(viewportWidth, viewportHeight)
        program.bindSource(sourceTextureId)
        program.drawQuad()
    }

    /**
     * Hook for a shader with uniforms beyond intensity and aspect — a texel
     * step, say. Called with the program already current.
     */
    protected open fun bindExtraUniforms(viewportWidth: Int, viewportHeight: Int) = Unit

    /** Deletes the shared program. Idempotent. GL thread only. */
    open fun release() {
        program.release()
    }
}
