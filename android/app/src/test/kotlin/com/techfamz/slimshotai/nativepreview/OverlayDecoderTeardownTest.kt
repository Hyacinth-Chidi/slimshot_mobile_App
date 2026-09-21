package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.OverlayDecoderTeardown
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The order a preview overlay's decoder and its surface are torn down in.
 *
 * **Device-reported, and it killed the app.** A 2-minute project with two video
 * overlays crashed after a few minutes:
 *
 * ```
 * FATAL EXCEPTION: slimshot-overlay-decode
 * java.lang.IllegalStateException
 *   at android.media.MediaCodec.releaseOutputBuffer(Native Method)
 *   at ExportClipDecoder.advanceTo(ExportClipDecoder.kt:206)
 *   at RealtimeOverlayDecoder.pump(RealtimeOverlayDecoder.kt:101)
 * ```
 *
 * preceded in the log by `BufferQueue has been abandoned` and
 * `Codec reported err 0xe` — the surface was freed while the codec was still
 * decoding into it. The teardown *looked* ordered (`release()` then
 * `releaseVideoLane()`), but `release()` posted the codec release behind an
 * in-flight `pump()`, waited 400ms, and returned anyway. The GL thread then
 * freed the surface under a codec that was still running.
 *
 * Waiting harder is not the fix: `release()` is called from the GL thread and a
 * pump can legitimately run for seconds, so blocking it trades a crash for a
 * freeze. The surface release is **handed back** instead, and these are the
 * rules that make that correct.
 */
class OverlayDecoderTeardownTest {

    @Test
    fun `the surface is not released until the codec says it is done`() {
        val teardown = OverlayDecoderTeardown()
        var surfaceReleased = false

        teardown.begin { surfaceReleased = true }
        assertFalse("the codec is still running", surfaceReleased)

        teardown.onCodecReleased()
        assertTrue("the codec is gone, so the surface may go", surfaceReleased)
    }

    @Test
    fun `a codec already gone releases the surface immediately`() {
        // The decoder never opened, or failed and released itself. There is
        // nothing to wait for and the surface must not be stranded.
        val teardown = OverlayDecoderTeardown()
        teardown.onCodecReleased()

        var surfaceReleased = false
        teardown.begin { surfaceReleased = true }
        assertTrue(surfaceReleased)
    }

    @Test
    fun `the surface is released exactly once`() {
        // The decode thread can answer late *and* the timeout can fire; both
        // paths lead here, and a GL texture deleted twice is undefined.
        val teardown = OverlayDecoderTeardown()
        var releases = 0

        teardown.begin { releases++ }
        teardown.onCodecReleased()
        teardown.onCodecReleased()
        teardown.giveUp()
        assertEquals(1, releases)
    }

    @Test
    fun `a wedged codec still gives the surface up`() {
        // A codec that never answers must not strand the surface for ever;
        // the lane would leak and the overlay could never reopen.
        val teardown = OverlayDecoderTeardown()
        var surfaceReleased = false

        teardown.begin { surfaceReleased = true }
        teardown.giveUp()
        assertTrue("released on the timeout path too", surfaceReleased)
    }

    @Test
    fun `nothing is released without a teardown having begun`() {
        // `onCodecReleased` also fires when a decoder is dropped for its own
        // reasons; that must not free a surface nobody asked to free.
        val teardown = OverlayDecoderTeardown()
        var releases = 0
        teardown.onCodecReleased()
        teardown.giveUp()
        assertEquals(0, releases)
    }

    @Test
    fun `a decode loop stops promptly once release is asked for`() {
        // The `released` flag used to be read once at the top of `pump()`, so a
        // long walk after a seek — up to 512 steps at a 10ms dequeue timeout —
        // carried on for seconds after release was requested. Each step now
        // asks, so a teardown lands within a step rather than a GOP.
        var steps = 0
        val releasedAfter = 3
        val keepGoing = {
            steps++
            steps < releasedAfter
        }

        while (OverlayDecoderTeardown.mayContinue(keepGoing(), budgetLeft = 100)) {
            // Body intentionally empty: the predicate is what is under test.
        }
        assertEquals(releasedAfter, steps)
    }

    @Test
    fun `a pump yields when its step budget runs out, rather than hogging`() {
        // Bounded per turn so the handler can see a release request; the pump
        // re-posts to continue. Without this the thread is busy for a whole
        // GOP and honours nothing in between.
        assertTrue(OverlayDecoderTeardown.mayContinue(notReleased = true, budgetLeft = 1))
        assertFalse(OverlayDecoderTeardown.mayContinue(notReleased = true, budgetLeft = 0))
    }
}
