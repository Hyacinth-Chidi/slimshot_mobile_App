package com.techfamz.slimshotai.nativepreview

/**
 * How a clip sits inside the project canvas.
 *
 * Shared by preview and export so a clip is letterboxed identically in both.
 * Copying this formula into the export path would be the easiest possible way
 * to make an exported frame differ from the previewed one — the difference
 * would be a few pixels of bar, which is exactly the kind of thing nobody
 * notices until a user does.
 */
internal object LaneFit {

    /**
     * Fraction of the canvas the clip occupies once scaled to *contain*.
     *
     * `(1, 1)` fills the frame. A clip wider than the canvas keeps full width
     * and gets bars above and below; a taller one keeps full height and gets
     * bars left and right. An unprobed clip (aspect `<= 0`) fills the frame,
     * because guessing a shape would letterbox it wrongly.
     */
    fun of(clipAspect: Double, canvasAspect: Double): Pair<Float, Float> {
        if (canvasAspect <= 0.0 || clipAspect <= 0.0) return Pair(1f, 1f)

        return if (clipAspect > canvasAspect) {
            Pair(1f, (canvasAspect / clipAspect).toFloat())
        } else {
            Pair((clipAspect / canvasAspect).toFloat(), 1f)
        }
    }

    /**
     * Shape of what a lane actually shows: a frame of [frameAspect] narrowed by
     * its content rect (`[left, top, width, height]` as source fractions).
     *
     * **The fit is of the content, not the frame.** The shader samples through
     * the rect, so what reaches the canvas has the frame's shape times the
     * rect's own proportions. Fitting by the frame's shape while sampling
     * through a differently shaped rect squeezes the picture into a box of the
     * wrong shape — the per-clip crop's first device-visible fault, and why a
     * custom project crop exported stretched while the preview compensated with
     * a reshaped Flutter box. An unprobed frame stays `0.0` so [of] fills the
     * canvas as before; a junk rect falls back to the frame's own shape rather
     * than inventing one.
     */
    fun contentAspect(frameAspect: Double, contentRect: FloatArray): Double {
        if (frameAspect <= 0.0) return 0.0
        if (contentRect.size < 4) return frameAspect
        val w = contentRect[2]
        val h = contentRect[3]
        if (w <= 0f || h <= 0f) return frameAspect
        return frameAspect * (w.toDouble() / h.toDouble())
    }
}
