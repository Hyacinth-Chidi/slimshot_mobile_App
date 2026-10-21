package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.EffectPassChain

/** One bar drawn at an instant, with what its passes are given. */
internal data class ActiveEffect(
    val bar: NativeTimelineEffect,
    /** Resolved at the bar's own progress, clamped to the 0..1 a shader expects. */
    val intensity: Double,
    /** The shader's clock: over the intro from the bar's start, else the whole bar. */
    val progress: Double,
    /**
     * Seconds since the bar began — the clock of an effect that moves at a real
     * speed. Timeline seconds, never wall clock, so the export draws the same
     * instant the preview does however fast it runs.
     */
    val barSeconds: Double,
)

/**
 * Which effect bars are drawn at an instant — the Dart `effectBarsDrawnAt`,
 * pinned to it by `effect_stack_fixture.json`. Both engines draw by this, on
 * the timeline clock, so a bar is drawn or skipped identically on the canvas
 * and in the file.
 *
 * Bars with `start <= t < end` — half-open, so two bars meeting at a seam
 * never both draw there — whose effect has a cost ([EffectPassCosts]; an
 * unknown one costs nothing and draws nothing), by lane. Each spends its cost
 * out of [EffectPassChain.MAX_EFFECT_PASSES]; a bar that does not fit is
 * skipped **whole** and the walk goes on.
 */
internal object EffectStack {

    fun drawnAt(bars: List<NativeTimelineEffect>, seconds: Double): List<ActiveEffect> {
        var budget = EffectPassChain.MAX_EFFECT_PASSES
        val drawn = ArrayList<ActiveEffect>(2)
        for (bar in bars.filter { it.start <= seconds && seconds < it.end }.sortedBy { it.lane }) {
            val cost = EffectPassCosts.costOf(bar.effectId)
            if (cost == 0 || cost > budget) continue
            budget -= cost
            drawn += ActiveEffect(
                bar = bar,
                intensity = bar.intensity.resolveAt(barProgress(bar, seconds)).coerceIn(0.0, 1.0),
                progress = shaderProgress(bar, seconds),
                barSeconds = seconds - bar.start,
            )
        }
        return drawn
    }

    /**
     * The most bars of each effect drawn at once — how many instances of its
     * passes a timeline needs, so that switching which bars draw never has to
     * build a pass in the render path. Checked once inside each stretch
     * between consecutive bar edges, where the drawn set is constant.
     */
    fun peakInstances(bars: List<NativeTimelineEffect>): Map<String, Int> {
        val edges = bars.flatMap { listOf(it.start, it.end) }.distinct().sorted()
        val peak = HashMap<String, Int>()
        for (i in 0 until edges.size - 1) {
            val counts = drawnAt(bars, (edges[i] + edges[i + 1]) / 2.0)
                .groupingBy { it.bar.effectId }
                .eachCount()
            for ((effectId, count) in counts) {
                if (count > (peak[effectId] ?: 0)) peak[effectId] = count
            }
        }
        return peak
    }

    /** Where [seconds] falls in [bar], 0..1; a bar of no length is already over. */
    fun barProgress(bar: NativeTimelineEffect, seconds: Double): Double {
        val span = bar.duration
        if (span <= 0.0) return 1.0
        return ((seconds - bar.start) / span).coerceIn(0.0, 1.0)
    }

    /** Over [NativeTimelineEffect.introSeconds] from the start, resting at 1; else the whole bar. */
    fun shaderProgress(bar: NativeTimelineEffect, seconds: Double): Double {
        val window = bar.introSeconds ?: bar.duration
        if (window <= 0.0) return 1.0
        return ((seconds - bar.start) / window).coerceIn(0.0, 1.0)
    }
}
