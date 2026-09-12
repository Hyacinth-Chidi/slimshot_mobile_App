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
 * **The change guard is the point.** `setEffectPasses` with an equivalent list
 * every tick would link a fresh program 30-60 times a second and leak the
 * previous one each time — a `glLinkProgram` in the render path is a visible
 * stall, and it is the cost `TransitionShaders.warmUpShaders` exists to keep
 * out of it. The renderer already ignores an unchanged colour matrix; this is
 * the same pattern one level up, where the work is expensive enough that the
 * guard has to sit on the *caller's* side.
 *
 * Callers are on the main thread (playback's ticker) or the export loop; the
 * program work is posted onto the GL thread, where an EGL context is current.
 */
internal class ClipEffectController(private val renderer: TransitionRenderer) {

    /**
     * The effect currently linked, or null when none is.
     *
     * Compared against, never rebuilt from — an effect whose id and intensity
     * both match is already drawing the right picture.
     */
    private var appliedId: String? = null
    private var appliedIntensity: Double = 0.0

    /**
     * The live passes, held only so their GL programs can be deleted when they
     * are replaced: `setEffectPasses` drops the renderer's reference, it does
     * not delete a program.
     */
    private var passes: List<EffectPass> = emptyList()

    /**
     * Applies [effectId] at [intensity], rebuilding only when it has changed.
     *
     * Intensity is compared with a tolerance because it arrives as a Double
     * that has been through JSON: an exact comparison would rebuild the chain
     * on a value that round-tripped a hair differently, which is a link in the
     * render path for a picture nobody could tell apart. The threshold is far
     * below what a slider can express.
     */
    fun apply(effectId: String?, intensity: Double) {
        val id = effectId?.takeIf { it.isNotBlank() && it != "none" }
        if (id == appliedId &&
            (id == null || abs(intensity - appliedIntensity) <= INTENSITY_EPSILON)
        ) {
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
            EffectShaders.passesFor(id, intensity)
        }
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
