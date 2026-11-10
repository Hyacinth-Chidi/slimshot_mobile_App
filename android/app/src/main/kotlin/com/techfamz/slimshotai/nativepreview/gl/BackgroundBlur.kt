package com.techfamz.slimshotai.nativepreview.gl

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * How the blurred background blurs: its strength, from the background sheet's
 * slider, as a gaussian of a size, drawn on a grid of a size.
 *
 * **It used to read as a mirror** (the owner's report, 2026-11-10). The clip
 * was blurred by `BlurPass`'s full-resolution cap, 1.4% of the short side,
 * twice — a softening, where a background wants the picture's colours and
 * none of its shapes. The slider now runs from a light blur, a little past
 * the old one, to one nine times its size, and starts halfway.
 *
 * **One grid for every frame**: the cover-fitted clip is drawn into a copy
 * [COPY_SHORT_SIDE] texels on its short side, whatever the frame — the
 * preview's ~720px canvas and a 1080 or 2K export alike — so the blur is the
 * same shape in both, texel for texel. That size is what keeps the strongest
 * blur's 16 taps a side close enough not to band, and makes the pass cheap
 * on the low-end target. The blur hides the small copy; bilinear sampling
 * brings it back up.
 *
 * Pure, so the arithmetic is tested on the JVM; the renderer reads it per
 * frame.
 */
internal object BackgroundBlur {

    /** Halfway along the slider: well past the blur that looked like a mirror. */
    const val DEFAULT_STRENGTH = 0.5f

    /**
     * The blur radius per pass at the slider's ends, as a fraction of the
     * short side. Run twice (horizontal and vertical, then again), so the
     * gaussian is √2 times wider than one pass.
     */
    const val MIN_RADIUS_FRACTION = 0.02
    const val MAX_RADIUS_FRACTION = 0.13

    /** The copy's short side, in texels. */
    const val COPY_SHORT_SIDE = 180

    /** The radius per pass for [strength] (0 light, 1 heavy), held to the slider. */
    fun radiusFractionFor(strength: Float): Double {
        val s = strength.coerceIn(0f, 1f).toDouble()
        return MIN_RADIUS_FRACTION + (MAX_RADIUS_FRACTION - MIN_RADIUS_FRACTION) * s
    }

    /**
     * The copy's size for a frame of [viewportWidth] x [viewportHeight]: the
     * frame's shape, [COPY_SHORT_SIDE] on its short side — never larger than
     * the frame itself.
     */
    fun copySize(viewportWidth: Int, viewportHeight: Int): Pair<Int, Int> {
        val short = min(viewportWidth, viewportHeight)
        if (short <= COPY_SHORT_SIDE) return viewportWidth to viewportHeight
        val scale = COPY_SHORT_SIDE.toDouble() / short
        return max(1, (viewportWidth * scale).roundToInt()) to
            max(1, (viewportHeight * scale).roundToInt())
    }

    /**
     * The strength the timeline's canvas carries (`backgroundBlurStrength`),
     * held to the slider, or [DEFAULT_STRENGTH] when it says none. Read here
     * so the preview and the export cannot read it differently.
     */
    fun strengthOf(canvas: Map<*, *>?): Float {
        val value = (canvas?.get("backgroundBlurStrength") as? Number)?.toFloat()
            ?: return DEFAULT_STRENGTH
        if (value.isNaN()) return DEFAULT_STRENGTH
        return value.coerceIn(0f, 1f)
    }
}
