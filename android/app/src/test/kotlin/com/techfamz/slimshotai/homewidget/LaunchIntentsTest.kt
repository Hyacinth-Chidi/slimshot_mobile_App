package com.techfamz.slimshotai.homewidget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What a tap on the widget or the icon's menu says to the app: the action,
 * and for Continue the draft. Nothing else starts one.
 */
class LaunchIntentsTest {

    @Test
    fun `the three taps cross the channel as the app reads them`() {
        assertEquals(
            mapOf("action" to "continue", "draftId" to "d1"),
            LaunchIntents.toWire(LaunchIntents.CONTINUE, "d1", launchedFromHistory = false),
        )
        assertEquals(
            mapOf("action" to "new_video", "draftId" to null),
            LaunchIntents.toWire(LaunchIntents.NEW_VIDEO, null, launchedFromHistory = false),
        )
        assertEquals(
            mapOf("action" to "compress_video", "draftId" to null),
            LaunchIntents.toWire(LaunchIntents.COMPRESS_VIDEO, null, launchedFromHistory = false),
        )
    }

    @Test
    fun `anything else is no tap`() {
        assertNull(LaunchIntents.toWire(LaunchIntents.CONTINUE, null, launchedFromHistory = false))
        assertNull(LaunchIntents.toWire(LaunchIntents.CONTINUE, "", launchedFromHistory = false))
        assertNull(LaunchIntents.toWire("android.intent.action.SEND", null, launchedFromHistory = false))
        assertNull(LaunchIntents.toWire("android.intent.action.MAIN", null, launchedFromHistory = false))
        assertNull(LaunchIntents.toWire(null, null, launchedFromHistory = false))
    }

    /** Reopened from Recents, Android hands back the intent the app started with. */
    @Test
    fun `a tap is not repeated from Recents`() {
        assertNull(LaunchIntents.toWire(LaunchIntents.NEW_VIDEO, null, launchedFromHistory = true))
        assertNull(LaunchIntents.toWire(LaunchIntents.CONTINUE, "d1", launchedFromHistory = true))
    }
}
