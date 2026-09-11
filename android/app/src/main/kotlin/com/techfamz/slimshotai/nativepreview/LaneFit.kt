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
}
