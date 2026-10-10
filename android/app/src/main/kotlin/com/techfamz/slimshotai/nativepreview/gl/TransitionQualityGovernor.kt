package com.techfamz.slimshotai.nativepreview.gl

/**
 * Whether the preview should draw heavy transitions in their light version.
 *
 * Decided from this phone's own frames, never from a list of phones: the
 * median wall time of the last [WINDOW] layered-transition frames against
 * [BUDGET_MS]. A median, so the first frame of a window — which pays for a
 * layer allocation or a shader link — cannot decide it alone. Once light, the
 * preview stays light for the session; the caller says so once.
 *
 * Preview only. The export is not realtime, so a slow frame there only makes
 * the export take longer, and it always draws the full version.
 *
 * Pure, so it can be tested: the renderer only feeds it.
 */
internal class TransitionQualityGovernor {

    private val recent = ArrayDeque<Long>()

    /** True once the preview has dropped to the light versions. */
    var light = false
        private set

    /** Records one layered frame's wall time; true on the frame that tips it to light. */
    fun record(frameMs: Long): Boolean {
        if (light) return false
        recent.addLast(frameMs)
        if (recent.size > WINDOW) recent.removeFirst()
        if (recent.size < WINDOW) return false
        val median = recent.sorted()[WINDOW / 2]
        if (median <= BUDGET_MS) return false
        light = true
        return true
    }

    companion object {
        /** Frames the decision looks at. */
        const val WINDOW = 12

        /**
         * About 22 frames a second. Under it a heavy transition stutters
         * visibly; over it the light version would only cost detail.
         */
        const val BUDGET_MS = 45L
    }
}
