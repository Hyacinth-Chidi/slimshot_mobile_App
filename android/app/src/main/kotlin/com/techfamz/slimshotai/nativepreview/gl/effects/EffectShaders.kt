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
 * clip's effect **id** changes, and release the previous list.
 *
 * **An intensity change is not a rebuild.** It goes through [applyIntensity],
 * which writes a float onto passes that already exist — no context, no thread
 * hop. Building a pass per intensity would put a link on every frame of a
 * slider drag, and would make the per-frame intensity that envelopes and
 * keyframes need impossible.
 *
 * The returned passes are the caller's to own: hold them, hand them to
 * `TransitionRenderer.setEffectPasses`, and [releasePasses] them when they are
 * replaced or the context goes. `setEffectPasses` only drops the renderer's
 * reference — it does not delete a program.
 */
internal object EffectShaders {

    private const val TAG = "SlimshotGl"

    /**
     * The passes drawing [id], or an empty list for no effect.
     *
     * **Takes no intensity, deliberately.** A pass is built once per effect
     * *id* and carries its strength as a uniform it uploads on every draw, so
     * retuning it is [applyIntensity] — a float write on whatever thread is
     * driving — and never a rebuild. Baking the strength in here would mean
     * every frame of a slider drag re-linked a GL program through a blocking
     * thread hop, which is the cost `TransitionShaders.warmUpShaders` exists to
     * keep out of the render path. `BlurPass` established the pattern with its
     * settable `radiusFraction`; see [IntensityControlled].
     *
     * Callers set the initial strength with [applyIntensity] immediately after
     * building, which is the same call a later change makes.
     *
     * GL thread only.
     */
    fun passesFor(id: String?): List<EffectPass> {
        // Null, blank and the cleared-selection sentinels, all meaning the same
        // thing to a renderer: draw the clip unaffected. `videoEffectById` in
        // the Dart catalog takes exactly these three.
        if (id.isNullOrBlank() || id == "none") return emptyList()

        return when (id) {
            "vignette" -> listOf(VignettePass(FullFrameProgram(VignettePass.FRAGMENT)))

            "fisheye" -> listOf(FisheyePass(FullFrameProgram(FisheyePass.FRAGMENT)))

            "glow" -> glowPasses()

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
     * Sets the strength of every pass in [passes] that has one.
     *
     * **No GL context, no thread hop, no link** — each pass holds its strength
     * in a `@Volatile` field and uploads it as a uniform when it next draws. So
     * this is safe to call from whichever thread drives the timeline (playback's
     * main-thread ticker, or the export loop), and cheap enough that varying
     * intensity per frame — which is what Stage 3's envelopes and Stage 4's
     * keyframes do by design — costs nothing but the write.
     *
     * A pass with no strength to set is skipped silently: glow's bright pass has
     * one, its blur halves map it onto a radius, and a future pass may have
     * nothing to vary at all. None of that is the caller's business.
     */
    fun applyIntensity(passes: List<EffectPass>, intensity: Double) {
        val strength = intensity.coerceIn(0.0, 1.0).toFloat()
        for (pass in passes) {
            (pass as? IntensityControlled)?.applyIntensity(strength)
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
     * Each half is wrapped in a [GlowBlurPass] so the intensity reaches its
     * radius without a rebuild.
     */
    private fun glowPasses(): List<EffectPass> {
        val source = GlowSource()

        val bright = GlowBrightPass(FullFrameProgram(GlowBrightPass.FRAGMENT), source)
        // The radius is set by the caller's `applyIntensity`; this is only the
        // pair's starting value, and the two halves must share it — a radius
        // that differed between the axes would be a directional smear, not a
        // gaussian.
        val blur = BlurPass.chain().map { GlowBlurPass(it) }
        val composite = GlowCompositePass(
            FullFrameProgram(GlowCompositePass.FRAGMENT),
            source,
        )

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
                is GlowBlurPass -> pass.release()
                is BlurPass -> pass.release()
                is GlowCompositePass -> pass.release()
                else -> Log.w(TAG, "Effect pass '${pass.id}' has no release path")
            }
        }
    }
}
