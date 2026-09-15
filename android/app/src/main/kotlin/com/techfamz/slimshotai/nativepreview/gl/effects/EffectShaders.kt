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
 * catalog and the shaders be filled in at different times.
 *
 * **Every catalog id now resolves to a shader.** The third case above is
 * therefore currently empty, and it stays in place deliberately: it is what
 * makes adding a catalog entry ahead of its shader a safe intermediate state
 * rather than a crash, which is how the twelve static looks and the timed intros
 * were each landed in their own batch.
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

            // -- static grades ------------------------------------------------
            //
            // The catalog's original continuous looks: colour and coordinate
            // work applied to the whole clip, the same shape as `vignette` and
            // `fisheye` above. None declares `introSeconds`, so `uProgress` runs
            // across the clip — which most of them ignore and a few use to move
            // noise or a bloom, never to settle.
            "duotone" -> listOf(DuotonePass(FullFrameProgram(DuotonePass.FRAGMENT)))

            // **Deliberately a different shader from `rgb_split`.** Chromatic
            // aberration scales its channel displacement with the square of the
            // distance from the centre — a lens artefact, registered in the
            // middle and worst at the corners. The split below is a uniform
            // offset. Written the same way the two would be one effect at two
            // strengths; written these two ways they read as glass and as
            // damage.
            "chromatic" -> listOf(ChromaticPass(FullFrameProgram(ChromaticPass.FRAGMENT)))

            // The first pass in the catalog to need a uniform beyond intensity
            // and aspect: a 3x3 convolution has to know how big a texel is, and
            // ES 2.0 has no `textureSize()`. It supplies one through
            // `SingleFramePass.bindExtraUniforms`, which existed for exactly
            // this and had no caller until now.
            "sharpen" -> listOf(SharpenPass(FullFrameProgram(SharpenPass.FRAGMENT)))

            // -- retro artefacts ----------------------------------------------
            //
            // Every one of these needs pseudo-randomness and every one takes it
            // from `EffectShaderLib`'s deterministic hash — of the pixel, and of
            // `uProgress` where the noise should move. Never `Random()`, never a
            // frame counter: export runs faster than realtime, so anything
            // stateful draws a different picture in the file than on the canvas.
            "grain" -> listOf(GrainPass(FullFrameProgram(GrainPass.FRAGMENT)))

            "vhs" -> listOf(VhsPass(FullFrameProgram(VhsPass.FRAGMENT)))

            "scanlines" -> listOf(ScanlinesPass(FullFrameProgram(ScanlinesPass.FRAGMENT)))

            "rgb_split" -> listOf(RgbSplitPass(FullFrameProgram(RgbSplitPass.FRAGMENT)))

            "glitch" -> listOf(GlitchPass(FullFrameProgram(GlitchPass.FRAGMENT)))

            // -- distortions --------------------------------------------------
            //
            // [FisheyePass]'s family: these perturb the sampling coordinate
            // rather than the colour, in an aspect-corrected space, and clamp
            // back into 0..1 before sampling.
            "ripple" -> listOf(RipplePass(FullFrameProgram(RipplePass.FRAGMENT)))

            "swirl" -> listOf(SwirlPass(FullFrameProgram(SwirlPass.FRAGMENT)))

            "mirror" -> listOf(MirrorPass(FullFrameProgram(MirrorPass.FRAGMENT)))

            // -- light --------------------------------------------------------
            "light_leak" -> listOf(LightLeakPass(FullFrameProgram(LightLeakPass.FRAGMENT)))

            // **The discriminator for glow, as well as an effect in its own
            // right.** Glow was reported as rendering nothing, with two
            // candidate causes: [BlurPass]'s 16-tap loop being the only loop any
            // shader here runs — spec-legal on ES 2.0 under the
            // constant-index-expression rule, but with no driver precedent in
            // this app — or the bloom simply being too small to see. Glow was
            // the only effect depending on [BlurPass], so the two were
            // indistinguishable. Wiring blur separates them: if blur visibly
            // blurs, the loop is fine and the bloom's size was the cause.
            //
            // The wiring is due regardless — `blur` is in the Dart catalog and
            // was falling to the "no shader yet" branch.
            "blur" -> BlurPass.chain().map { StandaloneBlurPass(it) }

            "glow" -> glowPasses()

            // The first timed effect. Structurally an ordinary single-frame
            // pass — the clock is a uniform every pass already carries, so
            // nothing about the registry, the chain or the release path had to
            // learn what an intro is.
            "fade_in" -> listOf(FadeInPass(FullFrameProgram(FadeInPass.FRAGMENT)))

            // -- timed intros: zoom ------------------------------------------
            //
            // One geometry, five curves. Every one lands on scale 1.0 at
            // progress 1, so the settled clip is the untouched frame — progress
            // stays at 1 for the rest of the clip, so a curve ending anywhere
            // else would leave a permanent magnification.
            "cinema_zoom" ->
                listOf(CinemaZoomPass(FullFrameProgram(CinemaZoomPass.FRAGMENT)))

            "zoom_in" -> listOf(ZoomInPass(FullFrameProgram(ZoomInPass.FRAGMENT)))

            "super_zoom" -> listOf(SuperZoomPass(FullFrameProgram(SuperZoomPass.FRAGMENT)))

            "pulse_zoom" -> listOf(PulseZoomPass(FullFrameProgram(PulseZoomPass.FRAGMENT)))

            "bounce" -> listOf(BouncePass(FullFrameProgram(BouncePass.FRAGMENT)))

            // -- timed intros: motion ----------------------------------------
            //
            // These move the frame off its own edge, so they sample through
            // `sampleFrame` — background outside the picture, never a clamped
            // smear — and push in slightly while they move, the cover zoom
            // decaying to exactly 1.0 with the motion.
            "spin" -> listOf(SpinPass(FullFrameProgram(SpinPass.FRAGMENT)))

            "roll" -> listOf(RollPass(FullFrameProgram(RollPass.FRAGMENT)))

            "tilt" -> listOf(TiltPass(FullFrameProgram(TiltPass.FRAGMENT)))

            "steady_in" -> listOf(SteadyInPass(FullFrameProgram(SteadyInPass.FRAGMENT)))

            // -- timed intros: resolve ---------------------------------------
            "pixel_in" -> listOf(PixelInPass(FullFrameProgram(PixelInPass.FRAGMENT)))

            "hue_shift" -> listOf(HueShiftPass(FullFrameProgram(HueShiftPass.FRAGMENT)))

            "bw_fade" -> listOf(BwFadePass(FullFrameProgram(BwFadePass.FRAGMENT)))

            // The one intro that is not a single pass: a gaussian is separable,
            // so it is [BlurPass]'s two halves with the radius driven off
            // progress rather than a second blur shader.
            "blur_in" -> BlurPass.chain().map { BlurInPass(it) }

            // -- reveals from black ------------------------------------------
            //
            // **Not transitions.** A transition is an overlap between two clips
            // and cannot exist on the first clip of a timeline; a reveal is a
            // property of one clip, so it works there — which is the case a user
            // opening a video actually wants.
            "shutter" -> listOf(ShutterPass(FullFrameProgram(ShutterPass.FRAGMENT)))

            "horizontal_open" ->
                listOf(HorizontalOpenPass(FullFrameProgram(HorizontalOpenPass.FRAGMENT)))

            "circle_in" -> listOf(CircleInPass(FullFrameProgram(CircleInPass.FRAGMENT)))

            // One implementation, two cell counts. A second copy of the shader
            // for the denser grid would drift from this one.
            "grid" -> listOf(
                GridPass("grid", FullFrameProgram(GridPass.fragmentFor(GridPass.CELLS))),
            )

            "grid_collage" -> listOf(
                GridPass(
                    "grid_collage",
                    FullFrameProgram(GridPass.fragmentFor(GridPass.COLLAGE_CELLS)),
                ),
            )

            "roulette" -> listOf(RoulettePass(FullFrameProgram(RoulettePass.FRAGMENT)))

            // -- continuous looks --------------------------------------------
            //
            // No `introSeconds`, so `uProgress` runs across the whole clip and
            // these never settle — which is the point of them. Every
            // displacement is a pure function of that progress, never
            // `Random()`: export runs faster than realtime, so anything stateful
            // would draw a different picture in the file than on the canvas.
            "camera_pan" -> listOf(CameraPanPass(FullFrameProgram(CameraPanPass.FRAGMENT)))

            "handheld" -> listOf(HandheldPass(FullFrameProgram(HandheldPass.FRAGMENT)))

            "super_shake" -> listOf(SuperShakePass(FullFrameProgram(SuperShakePass.FRAGMENT)))

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
     * Tells every pass in [passes] that has a clock how far its effect has
     * played, 0..1.
     *
     * The twin of [applyIntensity], and cheap for the same reasons: a
     * `@Volatile Float` write, no GL context, no thread hop, no link. That it
     * costs nothing is not an optimisation here but the feature — this is
     * called on **every frame**, where an intensity change is occasional, so
     * anything more expensive would put that cost squarely in the render path.
     *
     * A pass with no clock is skipped silently. Most of the catalog is static
     * and will never read it.
     */
    fun applyProgress(passes: List<EffectPass>, progress: Double) {
        val value = progress.coerceIn(0.0, 1.0).toFloat()
        for (pass in passes) {
            (pass as? ProgressControlled)?.applyProgress(value)
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
        //
        // **The bloom is blurred at half resolution**, which is what makes it
        // large enough to see: the 16-tap kernel's radius cap is a sampling
        // density limit, so the way past it is fewer pixels rather than more
        // taps. The horizontal half owns the downscaled buffer and the vertical
        // half reads it back up to full size; see [GlowBlurPass].
        val halves = BlurPass.chain()
        val horizontal = GlowBlurPass(halves[0], ownsDownscale = true)
        val vertical = GlowBlurPass(halves[1], ownsDownscale = false)
        horizontal.shareDownscaleWith(vertical)

        val composite = GlowCompositePass(
            FullFrameProgram(GlowCompositePass.FRAGMENT),
            source,
        )

        return listOf(bright, horizontal, vertical, composite)
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
                // **The wrappers must come before [BlurPass].** Each delegates
                // the interface to a `BlurPass` but is not one, so a branch
                // order that tested the bare pass first would never be reached
                // by either — and a wrapper falling through to the `else` leaks
                // its program, and in `GlowBlurPass`'s case its downscale target
                // too, on every effect change.
                is GlowBlurPass -> pass.release()
                is StandaloneBlurPass -> pass.release()
                is BlurInPass -> pass.release()
                is BlurPass -> pass.release()
                is GlowCompositePass -> pass.release()
                else -> Log.w(TAG, "Effect pass '${pass.id}' has no release path")
            }
        }
    }
}
