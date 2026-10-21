package com.techfamz.slimshotai.nativepreview.gl.effects

/**
 * A pass told how many seconds its bar has been playing, every frame.
 *
 * [ProgressControlled]'s 0..1 runs across the whole bar, which is right for a
 * look that changes over the bar and wrong for anything with a real speed:
 * rain on a ten-second bar would fall at a third of the speed it falls on a
 * three-second one. This is the other clock — `EffectStack`'s `barSeconds`,
 * timeline seconds since the bar began, **never wall clock**, so the export
 * reaches the same value at the same instant however fast it runs.
 *
 * Uploaded as `uSeconds`; a shader that declares none has the location -1 and
 * the upload is a no-op, so every effect built before the clock existed draws
 * exactly as it did.
 */
internal interface TimeControlled {

    /** Seconds since this pass's bar began. */
    fun applySeconds(seconds: Float)
}
