package com.techfamz.slimshotai.camera.react

import kotlin.math.floor

/**
 * Camera frames that never made it into the file — the recorder fell behind
 * and the camera's texture kept only the latest — told from the gaps between
 * the frames that did. A gap is measured against the camera's **own** rate
 * (the median of its recent gaps), so a camera that slows to 15 fps in low
 * light is not a choppy take. Nothing is counted until a few gaps are known.
 */
internal class MissedFrames {

    private var last: Long? = null
    private val gaps = ArrayDeque<Long>()

    var frames: Int = 0
        private set
    var missed: Int = 0
        private set

    fun onFrame(timestampNanos: Long) {
        frames++
        val previous = last
        last = timestampNanos
        if (previous == null) return
        val gap = timestampNanos - previous
        if (gap <= 0) return
        if (gaps.size >= MIN_HISTORY) {
            val interval = median()
            if (gap > interval * 3 / 2) {
                missed += (floor(gap.toDouble() / interval + 0.5).toInt() - 1).coerceAtLeast(0)
            }
        }
        gaps.addLast(gap)
        if (gaps.size > HISTORY) gaps.removeFirst()
    }

    private fun median(): Long {
        val sorted = gaps.sorted()
        return sorted[sorted.size / 2]
    }

    private companion object {
        const val HISTORY = 30
        const val MIN_HISTORY = 3
    }
}
