package com.techfamz.slimshotai.nativepreview

import kotlin.math.ceil

/**
 * Turns timeline seconds into the whole milliseconds ExoPlayer seeks and
 * reports in, and back, **without the clock ever falling short**.
 *
 * Pure, kept out of the engine so it can be tested: the engine itself only
 * runs on a device.
 *
 * A split leaves a cut between two milliseconds, and transitions, speeds
 * and trims leave clip starts between them too; the player has only whole
 * ones. Rounding down — what the engine did — read the clock back up to a
 * millisecond of source *before* where it had been put (ten at 0.1x):
 *
 * - parked on a split's cut, the clock read as inside the transition ending
 *   there, while `seek` had decided it was past it, and the engine handed the
 *   clock back and forth between the two lanes for good — playback stopped
 *   at the cut and never crossed it;
 * - the outgoing clip ended a fraction of a millisecond short of the
 *   window's end, so a transition played up to never closed;
 * - paused, the clock stood just before the playhead, so an overlay added
 *   there was not live until played into.
 *
 * Device-reported, all three, and reproduced on the emulator with the
 * engine's clock logged. `LaneClockTest` holds the logged numbers.
 */
internal object LaneClock {

    /**
     * Where to seek [clip]'s player for [timelineSeconds]: rounded **up** to
     * the next whole millisecond of source, so reading it back is never
     * before the target. A hair of float noise above a whole millisecond is
     * not a millisecond more.
     */
    fun seekMs(clip: NativeTimelineClip, timelineSeconds: Double): Long {
        val ms = clip.sourceOffsetAt(timelineSeconds) * 1000.0
        return ceil(ms - FLOAT_NOISE_MS).toLong().coerceAtLeast(0L)
    }

    /**
     * The timeline instant [clip]'s player stands at. A player that has
     * [ended] has played its clip to the end, wherever its whole-millisecond
     * position stopped: its clip's end, exactly — not the millisecond before
     * it, which is still inside a transition ending there.
     */
    fun timelineSeconds(clip: NativeTimelineClip, playerPositionMs: Long, ended: Boolean): Double {
        if (ended) return clip.timelineEnd
        return clip.timelineStart + clip.timelineOffsetForSource(playerPositionMs / 1000.0)
    }

    private const val FLOAT_NOISE_MS = 1e-6
}
