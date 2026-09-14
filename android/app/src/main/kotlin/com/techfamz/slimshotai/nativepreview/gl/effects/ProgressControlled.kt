package com.techfamz.slimshotai.nativepreview.gl.effects

/**
 * A pass that is told how far its effect has played, every frame.
 *
 * [IntensityControlled] is the same shape and exists for the same reason, but
 * the two are separate interfaces because the values behave differently enough
 * that conflating them would hide a cost:
 *
 * * An **intensity** changes when the user drags a slider — rarely, in bursts.
 * * A **progress** changes on **every single frame**, by definition.
 *
 * That difference is why progress could never be a constructor argument. An
 * intensity baked into a pass costs a `glLinkProgram` per frame of a slider
 * drag, which is bad; a progress baked in would cost one per frame of
 * *playback*, on a blocking thread hop, forever — the render path doing nothing
 * but re-linking. So it is a uniform on exactly the same footing as intensity:
 * a `@Volatile Float` written by whichever thread drives the timeline and read
 * by the GL thread at its next draw.
 *
 * **The value is always the clip's own position through its effect's window**,
 * 0 at the first frame and 1 at the last, never a frame count and never wall
 * clock time. Export renders faster than realtime, so a self-timed effect draws
 * a different picture in the file than on the canvas. `NativeTimelineClip.
 * effectProgressAt` is the one place it is computed.
 *
 * Every pass gets this whether it uses it or not, through [SingleFramePass] and
 * [FullFrameProgram]. A shader that declares no `uProgress` has the uniform
 * location -1, which `glUniform1f` treats as a no-op — so a static look renders
 * exactly as it did before the clock existed.
 */
internal interface ProgressControlled {

    /**
     * Sets how far this pass's effect has played, 0..1.
     *
     * Named `applyProgress` rather than `setProgress` for the same reason
     * [IntensityControlled.applyIntensity] is: the latter is the JVM signature
     * Kotlin already generates for a `var progress`, and an implementation
     * holding both would not compile.
     */
    fun applyProgress(progress: Float)
}
