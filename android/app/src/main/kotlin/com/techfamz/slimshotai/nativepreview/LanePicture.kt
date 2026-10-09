package com.techfamz.slimshotai.nativepreview

/**
 * Whether a lane keeps the picture it is showing when its media is replaced.
 *
 * Pure, kept out of the engine so it can be tested: the engine itself only
 * runs on a device.
 */
internal object LanePicture {

    /** No lane: nothing on screen (the tail, the first timeline), or no rebuild. */
    const val NONE = -1

    /**
     * Whether loading new media into [lane] leaves its current picture up until
     * the re-prepared decoder's first frame replaces it.
     *
     * Only for the lane the user is looking at, through a rebuild that leaves
     * it on screen. An edit that changes what plays — a speed curve, a flat
     * speed, a trim, a split — rebuilds the lanes, and a lane's texture still
     * holds the very frame on screen; dropping it painted the background until
     * the new decoder delivered, device-reported as the canvas flashing when a
     * curve preset was tapped. Held, the picture stays until the frame at the
     * new position lands, as it does on any seek.
     *
     * Every other load drops it. A lane prepared off screen — a transition's
     * incoming lane, the prewarmed second lane, a lane crossing a gap — holds
     * another clip's last frame, and a transition would blend that in the
     * moment the window opens.
     */
    fun keepsPicture(lane: Int, shownBeforeRebuild: Int, shownAfter: Int): Boolean =
        lane != NONE && lane == shownBeforeRebuild && lane == shownAfter
}
