package com.techfamz.slimshotai.nativepreview.gl.effects

import com.techfamz.slimshotai.nativepreview.gl.EffectPass
import com.techfamz.slimshotai.nativepreview.gl.TransitionRenderer
import kotlin.math.abs

/**
 * Keeps the renderer's effect passes matched to the clip on screen.
 *
 * Both engines need exactly this — resolve the clip's effect, build its passes
 * once, hand them over, delete the old ones — so it is written once rather than
 * copied. Copying it would be the easiest way to make an exported frame's effect
 * differ from the previewed one, which is the failure the shared `composite`
 * exists to prevent.
 *
 * **The change guard is the point, and it guards two different costs.**
 * `setEffectPasses` with an equivalent list every tick would link a fresh
 * program 30-60 times a second and leak the previous one each time — a
 * `glLinkProgram` in the render path is a visible stall, and it is the cost
 * `TransitionShaders.warmUpShaders` exists to keep out of it. The renderer
 * already ignores an unchanged colour matrix; this is the same pattern one
 * level up, where the work is expensive enough that the guard has to sit on the
 * *caller's* side.
 *
 * But the two things a clip can change are not equally expensive, and treating
 * them as if they were is the trap this class exists to avoid: a **new id**
 * needs new programs, while a **new intensity** needs a float written onto the
 * passes already built. Rebuilding on intensity would mean a slider drag
 * re-linking a program on every frame of the drag.
 *
 * ### Threading
 *
 * Callers are on the main thread (playback's ticker) or the export loop's
 * thread. Only the *program* work is posted onto the GL thread, where an EGL
 * context is current, and only that work blocks. An intensity change is a
 * `@Volatile Float` write on the calling thread, read by the GL thread at its
 * next draw — no context needed, and the worst a race can do is show one frame
 * of the previous strength.
 */
internal class ClipEffectController(private val renderer: TransitionRenderer) {

    /**
     * The effect whose programs are currently linked, or null when none is.
     *
     * **This alone decides whether a rebuild happens.** The intensity below is
     * tracked separately because it does not imply one.
     */
    private var appliedId: String? = null

    /** The strength last pushed onto [passes]. Never a reason to rebuild. */
    private var appliedIntensity: Double = 0.0

    /**
     * The live passes, held only so their GL programs can be deleted when they
     * are replaced: `setEffectPasses` drops the renderer's reference, it does
     * not delete a program.
     */
    private var passes: List<EffectPass> = emptyList()

    /**
     * Applies [effectId] at [intensity].
     *
     * **Only a change of *id* rebuilds anything.** An intensity change writes a
     * float onto the passes that are already built — no GL context, no thread
     * hop, no link — because each pass uploads its strength as a uniform when it
     * next draws (see [IntensityControlled]). That distinction is the whole
     * design: dragging the intensity slider moves it once per frame, and
     * rebuilding there would re-link a GL program on every frame of the drag,
     * each one blocking the caller on [TransitionRenderer.callOnGlThread]. It is
     * also what lets a later stage vary intensity per frame at all.
     *
     * An id change still hops to the GL thread and still blocks, which is
     * accepted: it happens on a cut between differently-effected clips or a tap
     * on a tile, not per frame.
     *
     * Intensity is compared with a tolerance because it arrives as a Double that
     * has been through JSON, so an exact comparison would churn the uniform on a
     * value that round-tripped a hair differently. The cost of that churn is now
     * negligible — the guard is kept because a write nobody asked for is still a
     * write, not because it is expensive.
     */
    fun apply(effectId: String?, intensity: Double) {
        val id = effectId?.takeIf { it.isNotBlank() && it != "none" }

        if (id == appliedId) {
            // Same effect. Nothing to build; at most a number to update, and
            // only if it actually moved.
            if (id == null || abs(intensity - appliedIntensity) <= INTENSITY_EPSILON) return
            appliedIntensity = intensity
            EffectShaders.applyIntensity(passes, intensity)
            return
        }

        val previous = passes
        // Cleared before the build so a failure below cannot leave the field
        // naming programs the GL thread has already deleted.
        passes = emptyList()
        appliedId = id
        appliedIntensity = intensity

        if (id == null) {
            // Back to the renderer's single-pass path: no scene target, no
            // chain, the same draw straight to the output that every project
            // without an effect takes.
            renderer.setEffectPasses(emptyList())
            if (previous.isNotEmpty()) {
                renderer.callOnGlThread { EffectShaders.releasePasses(previous) }
            }
            return
        }

        // Both the release and the link happen on the GL thread in one hop: a
        // program built without a current context is a crash rather than a
        // failed link, and deleting the old one first keeps at most one effect's
        // programs alive at a time.
        val built = renderer.callOnGlThread {
            EffectShaders.releasePasses(previous)
            EffectShaders.passesFor(id)
        }
        // Before `setEffectPasses`, so the first frame drawn with these passes
        // already carries the right strength: handing them over at their default
        // and setting it after would show one frame at full intensity.
        EffectShaders.applyIntensity(built, intensity)
        passes = built
        renderer.setEffectPasses(built)
    }

    /**
     * Drops the passes without deleting their programs.
     *
     * For a teardown that releases the renderer: `TransitionRenderer.release`
     * takes the EGL context down and every program with it, so holding the
     * objects past that would leave this naming program ids in a context that
     * no longer exists.
     */
    fun forget() {
        passes = emptyList()
        appliedId = null
        appliedIntensity = 0.0
    }

    private companion object {
        /** Far below a slider step, and far above a JSON round-trip's error. */
        const val INTENSITY_EPSILON = 1e-4
    }
}
