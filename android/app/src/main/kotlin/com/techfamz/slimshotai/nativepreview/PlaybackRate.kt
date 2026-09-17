package com.techfamz.slimshotai.nativepreview

import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.roundToLong

/**
 * What the preview hands ExoPlayer for a clip: a rate, and the pitch to go
 * with it. Pure arithmetic, kept out of the engine so it can be unit-tested.
 *
 * **Pitch follows speed, because that is what the export does.** The export's
 * audio path is a resampler: it reads the source faster or slower, so the
 * sound drops through a slow section and rises through a fast one, like tape.
 * The preview used to send ExoPlayer a bare speed, which leaves pitch at 1 and
 * makes Media3's Sonic *time-stretch* instead — a different sound, and one
 * that restarts its stretcher on every rate change, which on a speed curve was
 * an audible glitch several times a second. Device-reported as "the export
 * sounds right and the preview does not".
 *
 * With pitch equal to speed, Sonic's `processStreamInput` computes
 * `speed / pitch == 1`, skips `changeSpeed` entirely and runs only
 * `adjustRate` — a plain resample, the export's own operation. Checked against
 * Media3's source rather than assumed.
 *
 * The preview still steps the rate where the export glides sample by sample,
 * so a faint roughness can remain on the steepest ramps. Closing that fully
 * means the preview no longer playing through ExoPlayer.
 */
internal object PlaybackRate {

    /**
     * Neighbouring rates differ by this **ratio**, not by a fixed amount.
     *
     * The first version stepped by a fixed 0.05. That is 2.5% at 2x and 12.5%
     * at 0.4x — over a semitone per step, in exactly the slow-motion range a
     * ramp spends its time in, and with pitch now following speed each step
     * is heard as a pitch jump. A ratio sounds the same size at any speed; 3%
     * is about half a semitone.
     *
     * Still a step rather than the exact value, for the reason the fixed step
     * existed: a curve changes every tick, and a new `PlaybackParameters`
     * sixty times a second is the audio-pipeline churn of fault 10.
     */
    const val STEP_RATIO = 1.03

    /**
     * Whether a clip with a **flat** speed also lets pitch follow it.
     *
     * True, so one rule holds everywhere: the preview sounds like the export.
     * A 2x clip exports with a raised voice, and a preview that kept the voice
     * natural would be promising a file the export does not deliver — the
     * more harmful of the two mismatches. Set false to shift pitch on curved
     * clips only; the real fix for natural-pitch speed-ups is a time-stretcher
     * in the *export*, at which point this becomes a per-clip choice.
     */
    const val FLAT_SPEED_SHIFTS_PITCH = true

    /** The range Media3's audio sink accepts for pitch; it clamps beyond it. */
    const val MIN_PITCH = 0.1f
    const val MAX_PITCH = 8f

    private val LOG_STEP = ln(STEP_RATIO)

    /**
     * [exact] snapped to the nearest rung of a ladder whose rungs are
     * [STEP_RATIO] apart, with 1.0 exactly on a rung so natural speed stays
     * natural. Anything that is not a usable rate is 1.0, never a zero or a
     * NaN handed to a player.
     */
    fun quantise(exact: Double): Double {
        if (!exact.isFinite() || exact <= 0.0) return 1.0
        val rung = (ln(exact) / LOG_STEP).roundToLong()
        return exp(rung * LOG_STEP).coerceIn(SpeedCurve.MIN_SPEED, SpeedCurve.MAX_SPEED)
    }

    /** The pitch to send with [speed]. See the class comment for why. */
    fun pitchFor(speed: Double, curved: Boolean): Float {
        if (!speed.isFinite() || speed <= 0.0) return 1f
        if (!curved && !FLAT_SPEED_SHIFTS_PITCH) return 1f
        return speed.toFloat().coerceIn(MIN_PITCH, MAX_PITCH)
    }
}
