package com.techfamz.slimshotai.nativepreview.gl

import kotlin.math.abs

/**
 * The timeline instant the preview's overlays are drawn at: the picture's own.
 *
 * **Why not the clock as the engine reads it.** Measured on the Infinix, video
 * frames reach the renderer ~42 ms before they are shown — ExoPlayer releases
 * each frame early, stamped with the moment it is due on screen — while the
 * engine timed overlays by its clock at the instant it ticked. So an overlay
 * the engine drew trailed the picture it was composited with by just that
 * much: moving captions into the engine alone would not have put them on
 * their words.
 *
 * - **Over video**, an overlay is drawn at the instant of the frame it is
 *   composited with: the clock carried to that frame's due time.
 * - **Where no fresh frame says** — a photo clip, the tail — at the clock
 *   carried to now, plus the lead the video frames showed (nothing before
 *   any did), so a caption over a photo meets the screen when the picture
 *   would.
 * - **Paused**, at the clock itself.
 *
 * The clock is carried from when its value last *changed*, not from when it
 * was read: over a photo ExoPlayer can hold one position for most of a
 * second, and carried from each read the text would stand still with it.
 * That is `smoothedPosition`'s rule for the playhead, here for the picture.
 *
 * Every method is synchronized: the engine writes the clock from the main
 * thread, the renderer reads it and feeds it frames on the GL thread.
 */
internal class PictureClock {

    private var sample = 0.0
    private var sampleAtNs = 0L
    private var hasSample = false
    private var advancing = false

    private var frameDueNs = 0L
    private var frameLatchedNs = 0L
    private var hasFrame = false

    private var leadNs = 0.0

    /** The engine's clock, [seconds] as read at [readNs]; [advancing] as the engine judges it. */
    @Synchronized
    fun onClock(seconds: Double, readNs: Long, advancing: Boolean) {
        val resumed = advancing && !this.advancing
        if (!advancing || resumed || !hasSample || abs(seconds - sample) > SAMPLE_EPSILON_SECONDS) {
            sample = seconds
            sampleAtNs = readNs
            hasSample = true
        }
        this.advancing = advancing
    }

    /**
     * A new frame of the clock's lane, due on screen at [dueNs] (its
     * `SurfaceTexture` timestamp) and latched at [latchedNs].
     *
     * Only frames latched while playing teach the lead, and only a lead a
     * frame could have: a seek's frame is shown at once, and a timestamp far
     * from now measures nothing about the screen.
     */
    @Synchronized
    fun onVideoFrame(dueNs: Long, latchedNs: Long) {
        frameDueNs = dueNs
        frameLatchedNs = latchedNs
        hasFrame = true
        if (!advancing) return
        val lead = dueNs - latchedNs
        if (lead < 0L || lead > MAX_LEAD_NS) return
        leadNs = if (hasLead) leadNs + LEAD_SMOOTHING * (lead - leadNs) else lead.toDouble()
        hasLead = true
    }

    private var hasLead = false

    /**
     * The clock's lane shows no video — a photo, or no lane at all in the
     * tail. The last video frame may still be recent, but it is no longer the
     * picture, and taking it for one would leave the draws to frames that are
     * not coming.
     */
    @Synchronized
    fun onNoVideo() {
        hasFrame = false
    }

    /** The timeline instant to draw the overlays at, at [nowNs]. */
    @Synchronized
    fun overlayTime(nowNs: Long): Double {
        if (!advancing) return sample
        if (isFresh(nowNs)) return carried(frameDueNs)
        return carried(nowNs) + leadNs / 1e9
    }

    /**
     * Whether video frames are driving the draws: each new one asks for a
     * draw and is drawn at its own instant, so a tick asking as well would
     * only draw the same picture again.
     */
    @Synchronized
    fun framesDriveDraws(nowNs: Long): Boolean = advancing && isFresh(nowNs)

    private fun isFresh(nowNs: Long): Boolean {
        if (!hasFrame) return false
        val age = nowNs - frameLatchedNs
        return age in 0..FRESH_FRAME_NS && abs(frameDueNs - nowNs) <= MAX_LEAD_NS
    }

    private fun carried(atNs: Long): Double = sample + (atNs - sampleAtNs) / 1e9

    companion object {
        /** A frame latched longer ago than this is no longer the picture: a photo is on screen. */
        const val FRESH_FRAME_NS = 100_000_000L

        /** No frame is released further ahead of the screen than this. */
        const val MAX_LEAD_NS = 150_000_000L

        /** How quickly the learned lead follows a change in it. */
        const val LEAD_SMOOTHING = 0.2

        /** A clock that moved by less than this has not moved. */
        const val SAMPLE_EPSILON_SECONDS = 0.001
    }
}
