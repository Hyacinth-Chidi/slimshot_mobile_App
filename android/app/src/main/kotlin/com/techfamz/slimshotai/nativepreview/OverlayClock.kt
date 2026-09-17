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

            // A video overlay is a new picture whenever the clock moves, at
            // rest or not. Over a photo clip nothing else asks for a draw, so
            // without this its footage would freeze; a scrub backwards is a
            // new frame too.
            if (overlay.isVideo && previous != now) return true

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
     * Whether a realtime video overlay's decoder has to **seek** to reach
     * [targetUs], rather than walk there.
     *
     * The decoder only steps forward — it returns early when the target is
     * behind the frame it last showed — which is all the export ever needs,
     * since its clock never runs backwards. A preview playhead does: scrub
     * back and the overlay would keep showing a later frame for ever. And a
     * long jump forward would decode every frame in between, on the GL thread.
     *
     * Deliberately conservative the other way. A seek flushes the codec, so
     * ordinary playback must never trigger one — that is the decoder-flush
     * storm of dead-ends entry 11 — and a decoder that has shown nothing yet
     * is never seeked, because a flush before the first output is what lost
     * the codec's config data in the export's one-clip-never-decoded bug.
     */
    fun shouldSeek(lastRenderedUs: Long, targetUs: Long): Boolean {
        if (lastRenderedUs < 0L) return false
        if (targetUs < lastRenderedUs - BACKWARD_SLACK_US) return true
        return targetUs > lastRenderedUs + FORWARD_JUMP_US
    }

    /** Behind by less than this is the same frame, not a jump. */
    private const val BACKWARD_SLACK_US = 50_000L

    /** Ahead by more than this is cheaper to seek to than to decode through. */
    private const val FORWARD_JUMP_US = 1_500_000L

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
