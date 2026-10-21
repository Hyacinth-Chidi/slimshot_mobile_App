package com.techfamz.slimshotai.nativepreview.gl.effects

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * What Glitch tears at an instant — planned on the CPU and handed to the
 * shader as a few torn blocks a frame.
 *
 * **Why not in the shader.** It decided each band's tear from
 * `hash11`, which at `mediump` on a GPU that takes it literally (the Infinix's
 * PowerVR) returns almost nothing, so the gate never opened and the effect drew
 * the untouched picture even at 100% (device-reported). The damage is the same
 * for every pixel of a row, so it is planned here, exactly, from the bar's own
 * seconds — the canvas and the file tear on the same frames.
 *
 * **Digital, so stepped.** The plan changes [TICKS_PER_SECOND] times a second
 * and holds between: a corrupt frame is wrong, then wrong differently, never
 * sliding. **In bursts**: time is cut into windows of [TICKS_PER_WINDOW] ticks,
 * a window strikes or stays clean, and inside a striking window most ticks
 * tear — so the damage arrives in clusters with clean picture between, which
 * is what keeps a glitch reading as damage rather than as a texture. The
 * intensity raises how often a window strikes and how far a tear reaches; at
 * full strength nearly every window strikes. **The first window always does**,
 * so a bar shows itself the moment it starts (and the sheet's tile, which plays
 * a bar's opening, shows it), and no more than [MAX_CLEAN_WINDOWS] pass
 * without one.
 *
 * A struck tick tears up to [MAX_BLOCKS] horizontal blocks sideways, each with
 * its colour channels pulled apart, splits the whole frame's channels a little,
 * and now and then swaps the channels of one band — the colour corruption a
 * broken stream shows.
 */
internal object GlitchPlan {

    const val TICKS_PER_SECOND = 12.0
    const val TICKS_PER_WINDOW = 6
    const val MAX_CLEAN_WINDOWS = 3
    const val MAX_BLOCKS = 4

    /** The widest tear, as a fraction of the frame's width. */
    const val MAX_TEAR = 0.12f

    /** The widest channel split inside a block, as a fraction of the width. */
    const val MAX_SPLIT = 0.016f

    /**
     * One tick's damage. [blocks] is [MAX_BLOCKS] runs of `(y0, y1, tear,
     * split)` in texture coordinates — an unused block is `(-1, -1, 0, 0)`,
     * which covers no row — and the swapped band is [swapFrom]..[swapTo],
     * `-1, -1` for none. Exactly the shader's uniforms.
     */
    class Frame(
        val blocks: FloatArray,
        val frameSplit: Float,
        val swapFrom: Float,
        val swapTo: Float,
    ) {
        val torn: Boolean get() = blocks[0] >= 0f
    }

    private const val SALT_WINDOW = 1
    private const val SALT_TICK = 2
    private const val SALT_COUNT = 3
    private const val SALT_SPLIT = 4
    private const val SALT_SWAP = 5
    private const val SALT_BLOCK = 100

    fun at(seconds: Double, intensity: Float): Frame {
        val k = intensity.coerceIn(0f, 1f).toDouble()
        if (k <= 0.0) return clean()
        val tick = floor(max(0.0, seconds) * TICKS_PER_SECOND).toLong()
        val window = Math.floorDiv(tick, TICKS_PER_WINDOW.toLong())
        if (!strikes(window, k)) return clean()
        if (PlanHash.unit(tick, SALT_TICK) >= 0.6 + 0.4 * k) return clean()

        val strength = 0.35 + 0.65 * k
        val count = min(MAX_BLOCKS, 1 + floor(PlanHash.unit(tick, SALT_COUNT) * (1.0 + 3.0 * k)).toInt())
        val blocks = emptyBlocks()
        for (j in 0 until count) {
            val salt = SALT_BLOCK + j * 8
            val centre = PlanHash.unit(tick, salt)
            val reach = PlanHash.unit(tick, salt + 1)
            val height = 0.015 + 0.13 * reach * reach
            val sign = if (PlanHash.unit(tick, salt + 2) < 0.5) -1.0 else 1.0
            blocks[j * 4] = max(0.0, centre - height / 2).toFloat()
            blocks[j * 4 + 1] = min(1.0, centre + height / 2).toFloat()
            blocks[j * 4 + 2] = (sign * (0.02 + 0.10 * PlanHash.unit(tick, salt + 3)) * strength).toFloat()
            blocks[j * 4 + 3] = ((0.004 + 0.012 * PlanHash.unit(tick, salt + 4)) * strength).toFloat()
        }
        val frameSplit = ((0.003 + 0.004 * PlanHash.unit(tick, SALT_SPLIT)) * strength).toFloat()

        var swapFrom = -1f
        var swapTo = -1f
        if (PlanHash.unit(tick, SALT_SWAP) < 0.35 * k) {
            val centre = PlanHash.unit(tick, SALT_SWAP + 1)
            val height = 0.03 + 0.15 * PlanHash.unit(tick, SALT_SWAP + 2)
            swapFrom = max(0.0, centre - height / 2).toFloat()
            swapTo = min(1.0, centre + height / 2).toFloat()
        }
        return Frame(blocks, frameSplit, swapFrom, swapTo)
    }

    /**
     * Whether [window] strikes: the first always does, a run of
     * [MAX_CLEAN_WINDOWS] clean ones forces the next, and otherwise it is a
     * draw weighted by the intensity. Looks back at the draws only, never at
     * forced windows, so it stays a pure function of the window.
     */
    private fun strikes(window: Long, k: Double): Boolean {
        if (window <= 0L) return true
        val chance = 0.3 + 0.6 * k
        if (PlanHash.unit(window, SALT_WINDOW) < chance) return true
        for (back in 1..MAX_CLEAN_WINDOWS) {
            val earlier = window - back
            if (earlier <= 0L || PlanHash.unit(earlier, SALT_WINDOW) < chance) return false
        }
        return true
    }

    private fun emptyBlocks() = FloatArray(MAX_BLOCKS * 4) { if (it % 4 < 2) -1f else 0f }

    private fun clean() = Frame(emptyBlocks(), 0f, -1f, -1f)
}
