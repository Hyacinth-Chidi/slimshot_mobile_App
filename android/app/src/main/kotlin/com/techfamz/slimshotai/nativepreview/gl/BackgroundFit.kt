package com.techfamz.slimshotai.nativepreview.gl

/**
 * How a background photo sits on the canvas: it **covers** it.
 *
 * A clip is *contained* — scaled so all of it shows, with bars — because the
 * bars are the background. A background photo is the opposite: scaled so the
 * smaller side fills the canvas and the larger is cropped about the centre,
 * since a background with bars would need a background of its own.
 *
 * The answer is the fraction of the photo's own extent that is visible on each
 * axis, centred. The shader maps a canvas coordinate into it as
 * `(uv - 0.5) * fit + 0.5`; the no-clip tail draws the photo through the
 * passthrough program with the *reciprocal* as a contain fit, which lands on
 * the same central region. One function feeds both, so the photo cannot sit
 * differently behind a clip than it does after the last one. Shared by preview
 * and export through the renderer, as every fit rule is.
 */
internal object BackgroundFit {

    /**
     * Visible fraction of a photo of [imageAspect] covering a canvas of
     * [canvasAspect], as `(u, v)`. An unknown shape (`<= 0`) shows the whole
     * photo rather than guessing, the same rule `LaneFit.of` follows.
     */
    fun cover(imageAspect: Double, canvasAspect: Double): Pair<Float, Float> {
        if (imageAspect <= 0.0 || canvasAspect <= 0.0) return Pair(1f, 1f)
        return if (imageAspect > canvasAspect) {
            // Wider than the canvas: full height, a central band of the width.
            Pair((canvasAspect / imageAspect).toFloat(), 1f)
        } else {
            // Taller: full width, a central slice of the height.
            Pair(1f, (imageAspect / canvasAspect).toFloat())
        }
    }
}
