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

        // Running. A small steady offset is inaudible; the seek that would
        // "fix" it is a click. Only a real jump is followed — and only while
        // the player is genuinely playing, because a buffering player's
        // position stands still while the target advances, which turns drift
        // correction into a seek loop (fault 9 in the lanes' history).
        val seek = playerIsPlaying &&
            off > DRIFT_TOLERANCE_SECONDS &&
            msSinceLastSeek >= DRIFT_SEEK_COOLDOWN_MS
        return Command(playWhenReady = true, seekToSeconds = targetSeconds.takeIf { seek })
    }

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

    /** The lanes' own numbers, for the lanes' own reasons. */
    private const val DRIFT_TOLERANCE_SECONDS = 0.25
    private const val DRIFT_SEEK_COOLDOWN_MS = 600L

    /** The editor's ticker runs per frame; this is a dozen missed frames. */
    private const val TAIL_CLOCK_STALE_MS = 250L
}
