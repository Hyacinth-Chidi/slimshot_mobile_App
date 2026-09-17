package com.techfamz.slimshotai.nativepreview

/**
 * When an overlay obliges the preview to redraw, and whose clock it reads.
 *
 * Pure decisions, kept out of the engine so they can be tested: the engine
 * itself only runs on a device.
 */
internal object OverlayClock {

    /**
     * Whether the picture can differ between [previous] and [now] because of
     * an overlay.
     *
     * The engine ticks ~60 times a second. Redrawing on every tick merely
     * because an overlay exists would double the GL work for a sticker sitting
     * still over 30fps video, and keep the GPU awake over a paused photo —
     * which is the opposite of why overlays moved off the widget layer. A
     * redraw is owed only where the drawn result actually changes: the instant
     * an overlay appears or disappears, and every step inside an animation
     * window.
     *
     * Order-free on purpose: a scrub runs the playhead backwards, and a
     * crossing is a crossing in either direction.
     */
    fun needsRedraw(
        overlays: List<NativeTimelineOverlay>,
        previous: Double,
        now: Double,
    ): Boolean {
        if (overlays.isEmpty()) return false
        val from = minOf(previous, now)
        val to = maxOf(previous, now)

        for (overlay in overlays) {
            // Appearing or disappearing between the two instants.
            if (crosses(overlay.startSeconds, from, to)) return true
            if (crosses(overlay.endSeconds, from, to)) return true

            if (!overlay.contains(now)) continue

            // Inside an animation window the overlay is different every frame.
            //
            // The window's own far edge is a boundary like any other: the step
            // that *leaves* the window is the one that lands on rest, and
            // testing only `now` against the window skips it — the overlay
            // would park one frame short of its final opacity, which a test
            // caught. So the edge is crossed, not merely contained.
            if (overlay.animationIn != null && overlay.animationInSeconds > 0.0) {
                val edge = overlay.startSeconds + overlay.animationInSeconds
                if (now < edge || crosses(edge, from, to)) return true
            }
            if (overlay.animationOut != null && overlay.animationOutSeconds > 0.0) {
                val edge = overlay.endSeconds - overlay.animationOutSeconds
                if (now > edge || crosses(edge, from, to)) return true
            }
            // A loop animation is never at rest.
            if (overlay.animationLoop != null) return true
        }
        return false
    }

    private fun crosses(boundary: Double, from: Double, to: Double): Boolean =
        boundary > from && boundary <= to

    /**
     * The clock an overlay should read, when Flutter offers one.
     *
     * Past the last video frame the engine's clock parks and the editor's
     * ticker walks the playhead through the tail, so an overlay outliving the
     * video would freeze at the engine's final position. Flutter therefore
     * sends its own position — but **only past the engine's own end** is it
     * allowed to win. Inside the video two clocks writing one playhead is
     * dead-ends entry 12, and this is where that would happen again.
     *
     * Null means "use the engine's clock", which is every ordinary frame.
     */
    fun override(requested: Double, engineDuration: Double): Double? {
        if (!requested.isFinite()) return null
        if (requested <= engineDuration) return null
        return requested
    }
}
