package com.techfamz.slimshotai.homewidget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * A tap waits for the app's Dart side to listen: the one the app was started
 * with is handed out once, a tap arriving before Dart listens is kept — the
 * last one wins — and after that taps go straight on.
 */
class LaunchMailboxTest {

    private val newVideo = mapOf<String, Any?>("action" to "new_video", "draftId" to null)
    private val compress = mapOf<String, Any?>("action" to "compress_video", "draftId" to null)

    @Test
    fun `the action the app started with is taken once`() {
        val box = LaunchMailbox(newVideo)
        assertEquals(newVideo, box.take())
        assertNull(box.take())
    }

    @Test
    fun `a tap before Dart listens is kept, and the last one wins`() {
        val box = LaunchMailbox(null)
        assertNull(box.arrive(newVideo))
        assertNull(box.arrive(compress))
        assertEquals(compress, box.take())
    }

    @Test
    fun `once Dart listens, taps pass straight on`() {
        val box = LaunchMailbox(null)
        box.take()
        assertEquals(newVideo, box.arrive(newVideo))
        assertNull(box.take())
    }
}
