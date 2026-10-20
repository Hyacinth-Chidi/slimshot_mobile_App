package com.techfamz.slimshotai.nativepreview

/**
 * What each effect costs out of a frame's `EffectPassChain.MAX_EFFECT_PASSES`
 * — the number of passes `EffectShaders.passesFor` builds for it.
 *
 * **A pure table, deliberately not derived from `passesFor`.** That builds
 * and links GL programs on the spot, so it can neither run on the JVM nor be
 * asked "how many" without a context. The Dart catalog's `passCount` holds
 * the same numbers, pinned to this through `effect_stack_fixture.json`, and
 * [EffectStack] spends the budget by them on both sides — so a stacked bar is
 * drawn or skipped by one rule on the canvas and in the file.
 *
 * Zero for an id this build does not know: it draws nothing, so it costs
 * nothing.
 */
internal object EffectPassCosts {

    /** A gaussian is two draws; the glow is a bright pass, two blur halves and a composite. */
    private val MULTI_PASS = mapOf("blur" to 2, "blur_in" to 2, "glow" to 4)

    private val SINGLE_PASS = setOf(
        "vignette", "duotone", "chromatic", "grain", "vhs", "scanlines", "rgb_split", "glitch",
        "fisheye", "ripple", "swirl", "mirror", "light_leak", "sharpen", "fade_in", "cinema_zoom",
        "zoom_in", "super_zoom", "pulse_zoom", "bounce", "spin", "roll", "tilt", "pixel_in",
        "hue_shift", "bw_fade", "steady_in", "shutter", "horizontal_open", "circle_in", "grid",
        "grid_collage", "roulette", "camera_pan", "handheld", "super_shake",
    )

    fun costOf(effectId: String?): Int {
        if (effectId.isNullOrBlank()) return 0
        MULTI_PASS[effectId]?.let { return it }
        return if (effectId in SINGLE_PASS) 1 else 0
    }
}
