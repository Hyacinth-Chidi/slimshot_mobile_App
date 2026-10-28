package com.techfamz.slimshotai.homewidget

/**
 * Where the widget's cover is cut from the draft's, and how small it is kept.
 * Pure arithmetic, so it is tested off the device; [CoverPicture] draws it.
 */
object CoverCrop {

    /** The cover's height on the phone: twice and a bit the widget's ~110dp at 2x. */
    const val MAX_HEIGHT = 320

    /**
     * The 9:16 rectangle about the middle of a [srcW] × [srcH] picture, as
     * left, top, width, height. The side that is cut is rounded to the
     * nearest pixel, its offset halved down.
     */
    fun centre(srcW: Int, srcH: Int): IntArray =
        if (srcW.toLong() * 16 > srcH.toLong() * 9) {
            val width = Math.round(srcH * 9 / 16.0).toInt().coerceIn(1, srcW)
            intArrayOf((srcW - width) / 2, 0, width, srcH)
        } else {
            val height = Math.round(srcW * 16 / 9.0).toInt().coerceIn(1, srcH)
            intArrayOf(0, (srcH - height) / 2, srcW, height)
        }

    /** The size a [cropW] × [cropH] cut is scaled to: at most [maxH] tall, never enlarged. */
    fun output(cropW: Int, cropH: Int, maxH: Int = MAX_HEIGHT): IntArray {
        if (cropH <= maxH) return intArrayOf(cropW, cropH)
        val width = Math.round(cropW.toDouble() * maxH / cropH).toInt().coerceAtLeast(1)
        return intArrayOf(width, maxH)
    }
}
