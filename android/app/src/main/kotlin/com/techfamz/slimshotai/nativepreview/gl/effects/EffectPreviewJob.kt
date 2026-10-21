package com.techfamz.slimshotai.nativepreview.gl.effects

import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/** Who holds the renderer, as a slice finds it. */
internal enum class PreviewHost { READY, EXPORTING, RELEASED }

/** The GL half of an effect preview drawing, run on the GL thread. */
internal interface EffectPreviewCanvas {
    /** Makes the renderer's context current; false when it cannot be. */
    fun makeCurrent(): Boolean

    /** Builds the sample, the atlas, the chain and the passes; false when any is refused. */
    fun setUp(): Boolean

    /** Draws cell [index] — the plain picture when [seconds] is null, else the bar at [seconds]. */
    fun drawCell(index: Int, seconds: Double?)

    /** The whole atlas, read back. */
    fun readBack(): ByteBuffer

    /** Frees whatever [setUp] built, built in part included. */
    fun tearDown()
}

/**
 * One effect tile's atlas, drawn on the GL thread the live canvas shares —
 * **a few cells at a time** ([EffectPreviewSpec.slices]), each slice posted
 * behind whatever the canvas has queued, so a tile never holds the thread
 * for a whole effect.
 *
 * **Answered exactly once, on every path.** A lost answer would leave Dart's
 * queue waiting on it; two answers would answer one method-channel call
 * twice. [onDone] is guarded, and [abandon] — called by the renderer's
 * release, from whatever thread that runs on — answers busy and stops every
 * later slice before it touches GL, since the context is going.
 *
 * Every slice re-checks the host and makes the context current again first:
 * an export may run between two slices and leave its encoder surface current.
 * Whatever a failure leaves built is torn down while the context is still
 * usable; the read-back pixels are encoded off the GL thread ([encode]).
 */
internal class EffectPreviewJob(
    private val spec: EffectPreviewSpec,
    private val canvas: EffectPreviewCanvas,
    private val host: () -> PreviewHost,
    private val post: (Runnable) -> Boolean,
    private val encode: (ByteBuffer, (ByteArray?) -> Unit) -> Unit,
    private val onDone: (EffectPreviewAnswer) -> Unit,
) {
    private val slices = spec.slices()
    private val answered = AtomicBoolean(false)

    @Volatile
    private var abandoned = false

    // GL thread only.
    private var setUpStarted = false
    private var tornDown = false

    /** True once the job has answered. */
    val isDone: Boolean get() = answered.get()

    /** Queues the first slice; a GL thread that will not take it answers busy. */
    fun start() {
        if (!post(Runnable { runSlice(0) })) answer(EffectPreviewAnswer.Busy)
    }

    /** The renderer is going: answer busy now, and touch nothing from here on. */
    fun abandon() {
        abandoned = true
        answer(EffectPreviewAnswer.Busy)
    }

    private fun runSlice(index: Int) {
        if (abandoned || isDone) return
        when (host()) {
            PreviewHost.RELEASED -> {
                answer(EffectPreviewAnswer.Busy)
                return
            }
            PreviewHost.EXPORTING -> {
                tearDownOnce()
                answer(EffectPreviewAnswer.Busy)
                return
            }
            PreviewHost.READY -> Unit
        }
        if (!canvas.makeCurrent()) {
            // Without a current context nothing can be freed here; the
            // context's own teardown takes whatever was built with it.
            answer(EffectPreviewAnswer.Busy)
            return
        }
        try {
            if (index == 0) {
                setUpStarted = true
                if (!canvas.setUp()) {
                    tearDownOnce()
                    answer(EffectPreviewAnswer.Failed)
                    return
                }
            }
            for (cell in slices[index]) canvas.drawCell(cell, spec.frameSeconds(cell))
        } catch (error: Exception) {
            tearDownOnce()
            answer(EffectPreviewAnswer.Failed)
            return
        }
        if (index + 1 < slices.size) {
            if (!post(Runnable { runSlice(index + 1) })) {
                tearDownOnce()
                answer(EffectPreviewAnswer.Busy)
            }
            return
        }
        val pixels = try {
            canvas.readBack()
        } catch (error: Exception) {
            tearDownOnce()
            answer(EffectPreviewAnswer.Failed)
            return
        }
        tearDownOnce()
        encode(pixels) { jpeg ->
            answer(if (jpeg == null) EffectPreviewAnswer.Failed else EffectPreviewAnswer.Atlas(jpeg))
        }
    }

    private fun tearDownOnce() {
        if (!setUpStarted || tornDown) return
        tornDown = true
        try {
            canvas.tearDown()
        } catch (_: Exception) {
            // Nothing more can be freed than was; the answer still goes out.
        }
    }

    private fun answer(result: EffectPreviewAnswer) {
        if (answered.compareAndSet(false, true)) onDone(result)
    }
}
