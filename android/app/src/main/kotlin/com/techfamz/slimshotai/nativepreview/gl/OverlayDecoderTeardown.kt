package com.techfamz.slimshotai.nativepreview.gl

/**
 * Sequences a preview overlay decoder's teardown across two threads.
 *
 * **Device-reported, and it killed the app.** A project with two video overlays
 * crashed after minutes of playback:
 *
 * ```
 * FATAL EXCEPTION: slimshot-overlay-decode
 *   at MediaCodec.releaseOutputBuffer(Native Method)
 *   at ExportClipDecoder.advanceTo, at RealtimeOverlayDecoder.pump
 * ```
 *
 * with `BufferQueue has been abandoned` and `Codec reported err 0xe` just
 * above it: **the surface was freed while the codec was still decoding into
 * it.** The teardown looked ordered — release the decoder, then the lane — but
 * the decoder's `release()` posted the codec release *behind* an in-flight
 * `pump()`, waited 400ms, and returned regardless. The GL thread then deleted
 * the surface under a codec that was still running.
 *
 * **Waiting longer is the wrong fix.** Teardown is requested from the GL
 * thread, and a pump can legitimately run for seconds — `advanceTo` walks up
 * to its step cap at a 10ms dequeue timeout each after a seek. Blocking the
 * render thread on that trades a crash for a freeze.
 *
 * So the surface release is **handed back** instead: the decode thread frees
 * the codec and then calls [onCodecReleased], which runs the block that frees
 * the surface. Nobody waits, and the order is correct by construction.
 *
 * [giveUp] is the backstop for a codec that never answers: the surface is
 * freed anyway, because a stranded lane leaks a texture and the overlay could
 * never reopen. That is the one case where the old race remains possible — it
 * is strictly better than leaking, and it cannot be reached by a codec that is
 * merely slow, only by one that is wedged.
 *
 * Not thread-safe by itself; every method is called on the GL thread except
 * [onCodecReleased], which the decode thread posts back. `@Synchronized`
 * carries that boundary, since the two threads race exactly here.
 */
internal class OverlayDecoderTeardown {

    private var releaseSurface: (() -> Unit)? = null
    private var codecGone = false
    private var surfaceReleased = false

    /**
     * Asks for teardown. [releaseSurface] runs as soon as the codec is known
     * to be gone — immediately if it already is.
     */
    @Synchronized
    fun begin(releaseSurface: () -> Unit) {
        if (surfaceReleased) return
        this.releaseSurface = releaseSurface
        if (codecGone) finish()
    }

    /** The decode thread, reporting that the codec is released. */
    @Synchronized
    fun onCodecReleased() {
        codecGone = true
        // Only when a teardown asked for it: a decoder dropped for its own
        // reasons must not free a surface nobody asked to free.
        if (releaseSurface != null) finish()
    }

    /** The codec never answered. Free the surface rather than leak the lane. */
    @Synchronized
    fun giveUp() {
        if (releaseSurface != null) finish()
    }

    private fun finish() {
        if (surfaceReleased) return
        surfaceReleased = true
        val block = releaseSurface
        releaseSurface = null
        block?.invoke()
    }

    companion object {
        /**
         * Whether a decode loop may take another step.
         *
         * Two reasons it may not, and both were bugs. The `released` flag used
         * to be read *once* at the top of `pump()`, so a long walk after a seek
         * carried on for seconds after teardown was requested — hence
         * [notReleased] being asked every step. And a pump that ran its whole
         * budget in one turn never let the handler see the release message at
         * all, hence [budgetLeft]: the pump yields and re-posts, so a teardown
         * lands within a step rather than a GOP.
         */
        fun mayContinue(notReleased: Boolean, budgetLeft: Int): Boolean =
            notReleased && budgetLeft > 0

        /**
         * Decode steps one pump turn may take before yielding.
         *
         * Small enough that a release request is honoured promptly, large
         * enough that ordinary playback — which needs one step for one frame —
         * never pays for the re-post.
         */
        const val STEPS_PER_TURN = 8
    }
}
