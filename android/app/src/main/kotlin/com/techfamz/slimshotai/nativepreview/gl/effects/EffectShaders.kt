package com.techfamz.slimshotai.nativepreview.gl.effects

import android.util.Log
import com.techfamz.slimshotai.nativepreview.gl.EffectPass

/**
 * Turns a clip's effect id into the passes that draw it.
 *
 * This is the renderer's half of `effect_catalog.dart` and it mirrors that file
 * id for id. The catalog is the single source of truth for *what effects
 * exist*; this is the single source of truth for *how each one is drawn*. A
 * second list of either anywhere is how the panel and the renderer drift into
 * offering an effect that draws nothing.
 *
 * **Three ways to ask for an effect this build cannot draw, one answer:**
 * an id that is null or blank, an id the catalog never had (a draft from a
 * newer build, an unmigrated rename, a hand-edited file), and an id the catalog
 * *does* have but no shader has been written for yet. All three return an empty
 * list, which [com.techfamz.slimshotai.nativepreview.gl.EffectPassChain] renders
 * as the unprocessed frame. The clip plays; it simply carries no effect. This is
 * the same rule unknown transition names already follow, and it is what lets the
 * catalog and the shaders be filled in at different times — the thirteen entries
 * with no shader yet cost nothing and break nothing.
 *
 * **Every pass here links a program**, so [passesFor] must be called on the GL
 * thread with the context current, and never in the render path: a
 * `glLinkProgram` mid-frame is a visible stall, which is the whole reason
 * `TransitionShaders.warmUpShaders` exists. The engines call it only when a
 * clip's `(id, intensity)` actually changes, and release the previous list.
 *
 * The returned passes are the caller's to own: hold them, hand them to
 * `TransitionRenderer.setEffectPasses`, and [releasePasses] them when they are
 * replaced or the context goes. `setEffectPasses` only drops the renderer's
 * reference — it does not delete a program.
 */
internal object EffectShaders {

    private const val TAG = "SlimshotGl"

    /**
     * The passes drawing [id] at [intensity], or an empty list for no effect.
     *
     * [intensity] is the catalog's normalised 0..1 strength — **never pixels**.
     * Each shader converts it into whatever units it needs against the viewport
     * it is actually drawing, so one stored value looks the same in the capped
     * preview canvas and in a 1080p export. A pixel parameter here would be the
     * preview/export mismatch this codebase has already hit twice.
     *
     * GL thread only.
     */
    fun passesFor(id: String?, intensity: Double): List<EffectPass> {
        // Null, blank and the cleared-selection sentinels, all meaning the same
        // thing to a renderer: draw the clip unaffected. `videoEffectById` in
        // the Dart catalog takes exactly these three.
        if (id.isNullOrBlank() || id == "none") return emptyList()

        val strength = intensity.coerceIn(0.0, 1.0).toFloat()

        return when (id) {
            "vignette" -> listOf(
                VignettePass(FullFrameProgram(VignettePass.FRAGMENT)).apply {
                    this.intensity = strength
                },
            )

            "fisheye" -> listOf(
                FisheyePass(FullFrameProgram(FisheyePass.FRAGMENT)).apply {
                    this.intensity = strength
                },
            )

            "glow" -> glowPasses(strength)

            else -> {
                // Two cases land here and both are correct as no effect: an id
                // this build has never heard of, and a catalog id whose shader
                // has not been written yet. Logged rather than warned to the
                // user — a stale draft opening with one effect missing is not
                // something the user can act on, and this resolves on the GL
                // thread where a toast per frame would be worse than the
                // missing effect.
                Log.i(TAG, "No shader for effect '$id'; rendering unprocessed")
                emptyList()
            }
        }
    }

    /**
     * Bright-pass, separable blur, composite.
     *
     * **Four passes for a `passCount: 3` catalog entry.** The catalog counts the
     * blur as one step, which is how a person describes it; in GL a separable
     * gaussian is two draws. Four is exactly `EffectPassChain.MAX_EFFECT_PASSES`
     * — a glow is the effect that cap was sized for.
     *
     * The blur is [BlurPass], not a second blur shader: one gaussian, written
     * once, used by both the `blur` effect and this one. A copy would drift, and
     * the two would then blur differently for no reason a reader could find.
     *
     * The bloom's radius scales with the intensity because that is what a user
     * dragging the slider means by "more dreamy" — a brighter bloom at a fixed
     * radius just looks overexposed. The floor keeps a low intensity as a soft
     * halo rather than a sharp copy of the highlights laid over the frame.
     */
    private fun glowPasses(intensity: Float): List<EffectPass> {
        val source = GlowSource()

        val bright = GlowBrightPass(FullFrameProgram(GlowBrightPass.FRAGMENT), source)
        bright.intensity = intensity

        val radius = GLOW_MIN_RADIUS_FRACTION +
            (GLOW_MAX_RADIUS_FRACTION - GLOW_MIN_RADIUS_FRACTION) * intensity
        val blur = BlurPass.chain(radius.toDouble())

        val composite = GlowCompositePass(
            FullFrameProgram(GlowCompositePass.FRAGMENT),
            source,
        )
        composite.intensity = intensity

        return listOf(bright) + blur + composite
    }

    /**
     * Releases every pass in [passes], whatever kind each is.
     *
     * The engines hold a heterogeneous list and have no business knowing which
     * concrete type each entry is; without this they would either leak a program
     * per effect change or have to type-check at the call site. Idempotent, and
     * safe on a list whose entries share a program — [BlurPass]'s two halves do.
     *
     * **GL thread only**: a program can only be deleted with the context
     * current.
     */
    fun releasePasses(passes: List<EffectPass>) {
        for (pass in passes) {
            when (pass) {
                is SingleFramePass -> pass.release()
                is BlurPass -> pass.release()
                is GlowCompositePass -> pass.release()
                else -> Log.w(TAG, "Effect pass '${pass.id}' has no release path")
            }
        }
    }

    /** Bloom radius at intensity 0, as a fraction of the frame's short side. */
    private const val GLOW_MIN_RADIUS_FRACTION = 0.003f

    /**
     * Bloom radius at intensity 1.
     *
     * Kept inside [BlurPass.MAX_RADIUS_FRACTION], which is where the 16-tap
     * kernel starts to band as the stride widens. A bloom wider than this wants
     * a downsampled pass, not a coarser one.
     */
    private const val GLOW_MAX_RADIUS_FRACTION = 0.012f
}
