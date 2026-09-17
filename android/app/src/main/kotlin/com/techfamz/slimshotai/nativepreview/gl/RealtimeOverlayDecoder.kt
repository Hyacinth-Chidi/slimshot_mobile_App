package com.techfamz.slimshotai.nativepreview.gl

import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import com.techfamz.slimshotai.export.ExportClipDecoder
import com.techfamz.slimshotai.nativepreview.OverlayClock
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * A preview video overlay's decoder, on a thread of its own.
 *
 * **Device-reported, and the reason this exists:** with a video overlay on
 * screen the *main clip* played slowly, and dragging an overlay crawled. The
 * first realtime version stepped the overlay's `ExportClipDecoder` inside the
 * preview's draw, on the GL thread — the way the export does. That is right
 * for the export, which is not realtime and owns that thread anyway. In the
 * preview a single decode step can block for `DEQUEUE_TIMEOUT_US` (10ms), many
 * times over, on the one thread that also has to present the clip lanes'
 * frames; every millisecond spent here was a millisecond the main picture
 * waited.
 *
 * So the draw never decodes. It says which frame it wants ([request]) and
 * carries on; this thread walks the decoder there, and the frame lands on the
 * overlay's `SurfaceTexture`, whose arrival asks for the redraw that shows it.
 * **Latest request wins**: if playback moves on while a step is running, the
 * next step aims at the new target rather than working through stale ones.
 *
 * Opening the codec happens here too — tens of milliseconds that used to be a
 * visible hitch the moment an overlay appeared.
 *
 * The `ExportClipDecoder` is confined to this thread. It is not thread-safe
 * and does not need to be.
 */
internal class RealtimeOverlayDecoder(
    val path: String,
    private val surface: Surface,
    private val startUs: Long,
) {
    private val thread = HandlerThread("slimshot-overlay-decode").apply { start() }
    private val handler = Handler(thread.looper)

    /** Thread-confined to [thread]. */
    private var decoder: ExportClipDecoder? = null

    private val targetUs = AtomicLong(NO_TARGET)
    private val pumpQueued = AtomicBoolean(false)

    /** The codec could not be opened; the overlay is not drawable. */
    @Volatile
    var failed = false
        private set

    /** Width over height as displayed; 0 until the codec is open. */
    @Volatile
    var displayAspect = 0.0
        private set

    @Volatile
    private var released = false

    init {
        handler.post {
            if (released) return@post
            val opened = ExportClipDecoder(path, surface)
            if (opened.open(startUs)) {
                decoder = opened
                displayAspect = opened.displayAspect
                // A request may have arrived while the codec was opening.
                if (targetUs.get() != NO_TARGET) schedulePump()
            } else {
                opened.release()
                failed = true
            }
        }
    }

    /** The frame the next draw wants. Never blocks; safe from any thread. */
    fun request(sourceUs: Long) {
        if (released || failed) return
        targetUs.set(sourceUs)
        schedulePump()
    }

    private fun schedulePump() {
        if (pumpQueued.compareAndSet(false, true)) handler.post(::pump)
    }

    private fun pump() {
        pumpQueued.set(false)
        if (released) return
        val active = decoder ?: return
        val target = targetUs.get()
        if (target == NO_TARGET) return

        // The decoder only walks forward; a playhead that jumped needs a seek.
        // See [OverlayClock.shouldSeek] for why ordinary playback never does.
        if (OverlayClock.shouldSeek(active.lastRenderedUs, target)) active.seekTo(target)

        val rendered = active.advanceTo(target)
        // One call decodes a bounded number of steps. After a seek the target
        // can be a whole GOP away, so keep going until it is reached — aiming
        // at whatever the newest target is by then.
        val latest = targetUs.get()
        val behind = !active.isFinished && active.lastRenderedUs < latest
        if ((!rendered && behind) || latest != target) schedulePump()
    }

    /**
     * Stops the thread and frees the codec, **before returning**: the caller
     * releases the surface next, and a codec still writing into a released
     * surface is an error storm. Bounded, so a wedged codec cannot hang the
     * GL thread.
     */
    fun release() {
        if (released) return
        released = true
        handler.removeCallbacksAndMessages(null)
        handler.post {
            decoder?.release()
            decoder = null
        }
        thread.quitSafely()
        try {
            thread.join(RELEASE_WAIT_MS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    private companion object {
        const val NO_TARGET = Long.MIN_VALUE
        const val RELEASE_WAIT_MS = 400L
    }
}
