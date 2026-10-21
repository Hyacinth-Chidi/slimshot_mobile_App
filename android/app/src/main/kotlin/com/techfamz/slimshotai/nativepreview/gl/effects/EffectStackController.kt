package com.techfamz.slimshotai.nativepreview.gl.effects

import com.techfamz.slimshotai.nativepreview.ActiveEffect
import com.techfamz.slimshotai.nativepreview.EffectStack
import com.techfamz.slimshotai.nativepreview.NativeTimelineEffect
import com.techfamz.slimshotai.nativepreview.gl.EffectPass
import java.util.IdentityHashMap
import kotlin.math.abs

/** What the controller needs of a renderer — `TransitionRenderer` is one. */
internal interface EffectPassSink {
    /** Replaces the frame's effect passes; an empty list is the single-pass path. */
    fun setEffectPasses(passes: List<EffectPass>)

    /** Runs [block] on the GL thread — inline when already there. */
    fun <T> callOnGlThread(block: () -> T): T

    /** Asks for a frame, for a uniform that changed without the pass list changing. */
    fun redrawEffects()
}

/**
 * Keeps the renderer's effect passes matched to the effect bars drawn at the
 * clock, for both engines.
 *
 * **No program is ever linked in the render path.** [setBars] builds, when the
 * bars arrive, every instance of every effect the timeline will draw at once
 * ([EffectStack.peakInstances]) — one blur for two hundred bars that never
 * meet, two vignettes where two overlap — and releases what nothing needs any
 * more. [apply], run every tick, only chooses among the built passes and
 * pushes each bar's strength and clock as uniforms; crossing a bar's edge
 * costs a list swap. A `glLinkProgram` in the render path is a visible hitch,
 * exactly what `TransitionShaders.warmUpShaders` exists to keep out of it.
 *
 * Stacking through one ping-pong chain is sound because the one effect that
 * reads an earlier texture back — Glow's composite reads the frame its bright
 * pass saw — costs the whole four-pass budget, so it never shares a frame.
 *
 * [build], [release] and the two uniform setters default to [EffectShaders];
 * a test passes its own, since real passes link GL programs.
 */
internal class EffectStackController(
    private val sink: EffectPassSink,
    private val build: (String) -> List<EffectPass> = { EffectShaders.passesFor(it) },
    private val release: (List<EffectPass>) -> Unit = { EffectShaders.releasePasses(it) },
    private val setIntensity: (List<EffectPass>, Double) -> Unit =
        { passes, value -> EffectShaders.applyIntensity(passes, value) },
    private val setProgress: (List<EffectPass>, Double) -> Unit =
        { passes, value -> EffectShaders.applyProgress(passes, value) },
) {
    /** Built instances by effect id; an instance is one effect's passes. */
    private val pools = HashMap<String, MutableList<List<EffectPass>>>()

    /** The instances handed to the renderer, in order. */
    private var applied: List<List<EffectPass>> = emptyList()

    /**
     * Whether [applied] is what the renderer holds. Not at first: the export's
     * controller is a second one on the preview's renderer, which may still
     * hold the preview's passes, so its first frame must hand its own list
     * over even when that list is empty — or the file's opening frames take
     * the effect under the paused playhead.
     */
    private var rendererKnown = false

    private val lastIntensity = IdentityHashMap<List<EffectPass>, Double>()
    private val lastProgress = IdentityHashMap<List<EffectPass>, Double>()

    /**
     * Builds what [bars] will need and releases what they will not, in one
     * GL hop — and no hop at all when nothing changes, which is most calls: a
     * bar dragged across the timeline sends a new list every frame.
     */
    fun setBars(bars: List<NativeTimelineEffect>) {
        val need = EffectStack.peakInstances(bars)
        val toBuild = ArrayList<String>()
        for ((id, count) in need) {
            repeat(count - (pools[id]?.size ?: 0)) { toBuild += id }
        }
        val toRelease = ArrayList<List<EffectPass>>()
        for ((id, instances) in pools) {
            val keep = need[id] ?: 0
            if (instances.size > keep) toRelease += instances.subList(keep, instances.size)
        }
        if (toBuild.isEmpty() && toRelease.isEmpty()) return

        // A pass about to be released must leave the renderer first, or the
        // next frame would draw a deleted program.
        if (applied.any { instance -> toRelease.any { it === instance } }) {
            applied = emptyList()
            sink.setEffectPasses(emptyList())
            rendererKnown = true
        }
        sink.callOnGlThread {
            for (instance in toRelease) release(instance)
            for (id in toBuild) {
                pools.getOrPut(id) { ArrayList() } += build(id)
            }
        }
        for ((id, instances) in pools.entries.toList()) {
            val keep = need[id] ?: 0
            if (instances.size > keep) {
                instances.subList(keep, instances.size).forEach {
                    lastIntensity.remove(it)
                    lastProgress.remove(it)
                }
                instances.subList(keep, instances.size).clear()
            }
            if (instances.isEmpty()) pools.remove(id)
        }
    }

    /**
     * Draws [active] — [EffectStack.drawnAt] at the clock. Each bar takes the
     * next free instance of its effect; one without an instance (the bars
     * changed and [setBars] has not been told) is skipped rather than built
     * here. Uniforms are set before the list is handed over, so the first
     * frame drawn with a pass already carries its bar's strength.
     */
    fun apply(active: List<ActiveEffect>) {
        val used = HashMap<String, Int>()
        val chosen = ArrayList<List<EffectPass>>(active.size)
        var uniformsMoved = false
        for (effect in active) {
            val id = effect.bar.effectId
            val index = used[id] ?: 0
            val instance = pools[id]?.getOrNull(index) ?: continue
            used[id] = index + 1
            chosen += instance
            if (changed(lastIntensity[instance], effect.intensity)) {
                lastIntensity[instance] = effect.intensity
                setIntensity(instance, effect.intensity)
                uniformsMoved = true
            }
            if (changed(lastProgress[instance], effect.progress)) {
                lastProgress[instance] = effect.progress
                setProgress(instance, effect.progress)
                uniformsMoved = true
            }
        }
        if (!rendererKnown || !sameInstances(chosen, applied)) {
            applied = chosen
            sink.setEffectPasses(chosen.flatten())
            rendererKnown = true
        } else if (uniformsMoved && chosen.isNotEmpty()) {
            sink.redrawEffects()
        }
    }

    /** Hands the current passes over again — after an export used the renderer. */
    fun reassert() {
        sink.setEffectPasses(applied.flatten())
    }

    /** Draws no effect. */
    fun clear() = apply(emptyList())

    /** Releases every built pass, on the GL thread, after taking them off the renderer. */
    fun release() {
        applied = emptyList()
        sink.setEffectPasses(emptyList())
        rendererKnown = true
        val all = pools.values.flatten()
        if (all.isNotEmpty()) sink.callOnGlThread { all.forEach(release) }
        forget()
    }

    /**
     * Drops every pass without releasing it — for a teardown that takes the
     * EGL context, and every program with it, down anyway.
     */
    fun forget() {
        pools.clear()
        applied = emptyList()
        rendererKnown = false
        lastIntensity.clear()
        lastProgress.clear()
    }

    private fun changed(previous: Double?, next: Double) =
        previous == null || abs(previous - next) > EPSILON

    private fun sameInstances(a: List<List<EffectPass>>, b: List<List<EffectPass>>): Boolean =
        a.size == b.size && a.indices.all { a[it] === b[it] }

    private companion object {
        /** Far below a slider step, and far above a JSON round-trip's error. */
        const val EPSILON = 1e-6
    }
}
