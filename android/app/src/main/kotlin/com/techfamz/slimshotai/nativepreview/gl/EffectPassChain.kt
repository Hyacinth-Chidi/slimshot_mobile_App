package com.techfamz.slimshotai.nativepreview.gl

import android.util.Log

/**
 * One shader pass over a whole frame.
 *
 * A pass reads one texture and writes one target. That is the entire contract,
 * and it is deliberately this narrow: a gaussian blur is two passes of the same
 * shader with the axis swapped, and a masked composite — which is what
 * background removal, sky replacement and face beauty all reduce to — is one
 * pass that happens to bind a second texture of its own. Neither needs the
 * chain to know anything about it.
 */
internal interface EffectPass {

    /** Identifies the pass in warnings and logs. Not used for dispatch. */
    val id: String

    /**
     * Draws [sourceTextureId] into [target].
     *
     * **A null [target] means the framebuffer currently bound**, not "no
     * output". It is how the last pass reaches the screen or the encoder's
     * input surface directly: the alternative is the chain rendering into an
     * FBO and the caller then blitting that texture to the output, which is a
     * full extra frame copy per frame for no picture difference. The
     * implementation must therefore bind [target] when it has one and leave the
     * binding alone when it does not — and in the null case honour
     * [viewportWidth] / [viewportHeight], because it cannot ask the bound
     * framebuffer how big it is.
     *
     * [passIndex] is the pass's position in the chain, so a shader used twice
     * with different parameters — the two axes of a separable blur — can tell
     * which invocation it is without the chain holding per-pass state.
     */
    fun render(
        sourceTextureId: Int,
        target: RenderTarget?,
        viewportWidth: Int,
        viewportHeight: Int,
        passIndex: Int,
    )
}

/**
 * Runs a list of [EffectPass]es over a frame, ping-ponging between two targets.
 *
 * A shader cannot sample the texture it is writing, so a chain of passes needs
 * two buffers and alternates them: pass 0 reads the scene and writes A, pass 1
 * reads A and writes B, pass 2 reads B and writes A. Two is sufficient however
 * long the chain is, because a pass only ever needs the one frame before it.
 *
 * Everything here runs on the GL thread with the context current.
 */
internal class EffectPassChain(private val onWarning: (String) -> Unit) {

    private var targetA: RenderTarget? = null
    private var targetB: RenderTarget? = null
    private var width = 0
    private var height = 0

    /**
     * True once the device has refused the targets. Latched, so the frame
     * renders unprocessed from then on instead of retrying an allocation that
     * has already failed at this size.
     */
    private var unavailable = false

    /**
     * Warnings the user has already been told about this session.
     *
     * The GL thread runs this per frame, so an unguarded warning is a toast at
     * 30-60Hz — which is worse than the missing effect it is reporting. One
     * message per distinct cause is what makes it a diagnostic rather than a
     * fault of its own.
     */
    private val warned = mutableSetOf<String>()

    /** True when the chain holds usable targets. */
    val isReady: Boolean
        get() = !unavailable && targetA != null && targetB != null

    /**
     * Allocates the two ping-pong targets for a [width] x [height] frame.
     *
     * **Call this on a size change, never per frame.** Two 1080x1920 RGBA
     * targets are about 16MB — real, but bounded and paid once. Allocating and
     * freeing that per frame is exactly the churn that turns a working effect
     * into a stutter on the low-end target.
     *
     * Returns false when the device refused, which latches the chain off.
     */
    fun resize(width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0) {
            releaseTargets()
            this.width = 0
            this.height = 0
            return false
        }

        // An unchanged size is the common case — the canvas only resizes when
        // the project's shape or the export resolution changes — so this is the
        // guard that keeps a per-frame caller honest.
        if (isReady && width == this.width && height == this.height) return true

        releaseTargets()
        this.width = width
        this.height = height

        val a = createRenderTarget(width, height)
        val b = if (a != null) createRenderTarget(width, height) else null
        if (a == null || b == null) {
            // Partial success still leaves the chain unusable: one target cannot
            // ping-pong. Drop whichever was allocated rather than hold memory
            // nothing can use.
            a?.release()
            b?.release()
            targetA = null
            targetB = null
            unavailable = true
            Log.e(TAG, "Effect targets refused at ${width}x$height; effects disabled")
            warnOnce(
                "targets",
                "This device could not allocate the effect buffers, so effects are off.",
            )
            return false
        }

        targetA = a
        targetB = b
        // A fresh allocation at a new size deserves a fresh verdict: a device
        // that refused 4K may well accept 1080p, and latching the failure across
        // sizes would disable effects for the whole session over one export.
        unavailable = false
        return true
    }

    /**
     * Runs [passes] over [sceneTextureId] and returns the texture holding the
     * result.
     *
     * Returns [sceneTextureId] **unchanged** when there is nothing to do or the
     * chain is unavailable, so the caller composites the unprocessed frame and
     * the picture is missing an effect rather than missing entirely.
     *
     * Every pass here writes to an FBO, the last one included. The interface
     * allows a null target and the caller is free to run the final pass itself
     * that way, straight to the output — but `run` cannot: it has to return a
     * texture, and a pass that drew to the bound framebuffer left its result
     * somewhere unsamplable.
     *
     * [viewportWidth] / [viewportHeight] are passed through for a pass that
     * needs the frame's dimensions — a blur's texel step is 1/width — and are
     * not the targets' size, which each target sets itself in [RenderTarget.bind].
     */
    fun run(
        sceneTextureId: Int,
        passes: List<EffectPass>,
        viewportWidth: Int,
        viewportHeight: Int,
    ): Int {
        if (passes.isEmpty() || sceneTextureId == 0) return sceneTextureId

        val a = targetA
        val b = targetB
        if (unavailable || a == null || b == null) {
            warnOnce(
                "unavailable",
                "Effects are unavailable on this device; the video is unprocessed.",
            )
            return sceneTextureId
        }

        // Past the cap, run the first N rather than refusing the lot: a partial
        // effect that renders is a better answer than a correct one that melts a
        // low-end device, and the warning says which it got.
        val effective = if (passes.size > MAX_EFFECT_PASSES) {
            warnOnce(
                "cap",
                "An effect asked for ${passes.size} passes; only the first " +
                    "$MAX_EFFECT_PASSES were applied.",
            )
            passes.subList(0, MAX_EFFECT_PASSES)
        } else {
            passes
        }

        var source = sceneTextureId
        for ((index, pass) in effective.withIndex()) {
            // Alternating on the index is what keeps a pass from sampling the
            // texture it is writing — undefined in GL, and in practice reads as
            // smearing or a frame of garbage rather than as an error.
            val target = if (index % 2 == 0) a else b
            pass.render(source, target, viewportWidth, viewportHeight, index)
            source = target.textureId
        }

        // Whichever target the last pass wrote — A for an odd count, B for an
        // even one. Returning it as-is is the point: blitting back to a
        // canonical target so the answer is always A would charge every
        // odd-length chain, which is the common one, a full frame copy for
        // nothing.
        return source
    }

    /** Drops both targets. Call on the GL thread. */
    fun release() {
        releaseTargets()
        width = 0
        height = 0
        unavailable = false
        warned.clear()
    }

    private fun releaseTargets() {
        targetA?.release()
        targetA = null
        targetB?.release()
        targetB = null
    }

    private fun warnOnce(key: String, message: String) {
        if (!warned.add(key)) return
        onWarning(message)
    }

    internal companion object {
        private const val TAG = "SlimshotGl"

        /**
         * Enough for a separable blur plus a composite, and a hard stop on a
         * future catalog entry quietly asking for twelve.
         *
         * Visible so a caller building a pass list can check against it rather
         * than discover the cap through a warning after the fact.
         */
        const val MAX_EFFECT_PASSES = 4
    }
}
