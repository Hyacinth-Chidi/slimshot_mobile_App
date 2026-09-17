package com.techfamz.slimshotai.nativepreview

import kotlin.math.abs

/**
 * What a video overlay's sound does on each engine tick.
 *
 * Pure decisions, kept out of [OverlayAudioPlayers] so they can be tested: the
 * players themselves only run on a device. Every rule here is one the clip
 * lanes already learned the hard way, restated for a player that carries
 * sound and nothing else.
 */
internal object OverlayAudioSync {

    /** What to do with one overlay's player this tick. */
    data class Command(
        val playWhenReady: Boolean,
        /** Source seconds to seek to, or null to leave the position alone. */
        val seekToSeconds: Double?,
    )

    /**
     * Whether [overlay] should hold a player at [clock].
     *
     * Only while it can be heard, or is about to be: a player is a thread and
     * an audio decoder, and a project may carry many overlays along its
     * length. Held from [PREROLL_SECONDS] ahead so the first sound is not
     * late by the time it takes to prepare a player.
     */
    fun wantsPlayer(overlay: NativeTimelineOverlay, clock: Double): Boolean {
        if (!overlay.hasAudibleSound) return false
        return clock >= overlay.startSeconds - PREROLL_SECONDS && clock < overlay.endSeconds
    }

    fun decide(
        advancing: Boolean,
        /** The clock is inside the overlay's window, not merely ahead of it. */
        inWindow: Boolean,
        playWhenReady: Boolean,
        /** `ExoPlayer.isPlaying`: ready, playing, and not buffering. */
        playerIsPlaying: Boolean,
        playerPositionSeconds: Double,
        targetSeconds: Double,
        msSinceLastSeek: Long,
    ): Command {
        val off = abs(playerPositionSeconds - targetSeconds)

        if (!inWindow || !advancing) {
            // Silent, and parked where it will be needed — its first sample
            // ahead of the window, the scrubbed instant while paused — so that
            // starting is a bare `play()`. The short cooldown keeps a scrub
            // from issuing a seek per gesture frame; the tick after it lands
            // the final position.
            val seek = off > PARKED_TOLERANCE_SECONDS && msSinceLastSeek >= PARKED_SEEK_COOLDOWN_MS
            return Command(playWhenReady = false, seekToSeconds = targetSeconds.takeIf { seek })
        }

        if (!playWhenReady) {
            // Starting. Already parked on the instant is the common case and
            // must not seek again: that is a buffer flush exactly when the
            // sound is due.
            return Command(
                playWhenReady = true,
                seekToSeconds = targetSeconds.takeIf { off > START_TOLERANCE_SECONDS },
            )
        }

        // Running. **Ordinary drift is lived with, not corrected** — this is
        // the crackling the device reported. The overlay player and the clip
        // lane are two independent ExoPlayers with no shared clock, so they
        // really do drift apart over a long overlay; the lanes answer that by
        // seeking, which costs a dropped video frame nobody notices, but every
        // audio seek flushes the codec and is heard. A few tenths of a second
        // of skew against the picture is invisible; a click every time is not.
        //
        // Only a jump too large to be drift — a scrub, a loop round, a clip
        // boundary — earns the flush, and only while the player is genuinely
        // playing, because a buffering player's position stands still while
        // the target advances (the seek loop of fault 9).
        val seek = playerIsPlaying &&
            off > JUMP_SECONDS &&
            msSinceLastSeek >= JUMP_SEEK_COOLDOWN_MS
        return Command(playWhenReady = true, seekToSeconds = targetSeconds.takeIf { seek })
    }

    /**
     * [current] moved [step] ticks toward [target].
     *
     * **Device-reported as crackling**, and this is the second half of it. A
     * player whose gain jumps from 0 to full — or full to 0 — between two
     * buffers is a step discontinuity in the waveform, which is exactly what a
     * click is. Every start, stop and seek did that. Ramping over
     * [RAMP_TICKS] engine ticks (~80ms) removes the edge while staying far too
     * short to read as a fade-in.
     *
     * The target is *reached exactly*, never approached asymptotically: a gain
     * that settles at 0.999 leaves a player audible when it should be silent,
     * and one that settles near 0 leaves it quietly on for ever.
     */
    fun rampedGain(current: Float, target: Float, step: Int): Float {
        if (step <= 0) return current
        val delta = target - current
        // Rounding is why this compares with a slack rather than exactly: a
        // ramp assembled from `step / RAMP_TICKS` strides lands a few 1e-8
        // short of its target, and 3e-8 of gain is inaudible but is *not*
        // zero — so `mayStop` would refuse for ever and the player could
        // never stop or take its seek. Caught by the test, on the way down.
        val stride = step.toFloat() / RAMP_TICKS
        if (abs(delta) <= stride + SETTLE_EPSILON) return target
        return (current + stride * if (delta > 0f) 1f else -1f).coerceIn(0f, 1f)
    }

    /**
     * Whether a player at [currentGain] may be stopped now.
     *
     * Pausing at full gain is the same click as starting at it, so a stop
     * waits for the ramp to reach silence first.
     */
    fun mayStop(currentGain: Float): Boolean = currentGain <= 0f

    /** Engine ticks a gain change is spread over. 5 × 16ms ≈ 80ms. */
    const val RAMP_TICKS = 5

    /** Float slack so the last stride lands on the target exactly. */
    private const val SETTLE_EPSILON = 1e-4f

    /** The project's volume times the overlay's own; zero once muted. */
    fun gain(masterVolume: Float, overlay: NativeTimelineOverlay): Float =
        (masterVolume * overlay.effectiveVolume.toFloat()).coerceIn(0f, 1f)

    /**
     * Whether the tail's clock is running.
     *
     * Past the last clip the engine is parked and not "playing"; the editor's
     * ticker walks the playhead and sends each position. A message *is* the
     * evidence of motion, so the sound runs while they keep arriving and stops
     * when they stop — paused, backgrounded, a dropped call — without relying
     * on a second message to say so.
     */
    fun tailIsAdvancing(msSinceTailClock: Long): Boolean =
        msSinceTailClock in 0..TAIL_CLOCK_STALE_MS

    const val PREROLL_SECONDS = 1.0

    private const val PARKED_TOLERANCE_SECONDS = 0.1
    private const val PARKED_SEEK_COOLDOWN_MS = 120L
    private const val START_TOLERANCE_SECONDS = 0.05

    /**
     * Past this the clock has *jumped* rather than drifted, so the sound is in
     * the wrong place and a flush is the lesser evil. Deliberately much looser
     * than the lanes' 0.25s: a video reseek costs a frame, an audio one costs
     * a click.
     */
    private const val JUMP_SECONDS = 0.5

    /** So a pathological case is an occasional tick, never a rattle. */
    private const val JUMP_SEEK_COOLDOWN_MS = 2_000L

    /** The editor's ticker runs per frame; this is a dozen missed frames. */
    private const val TAIL_CLOCK_STALE_MS = 250L
}
