package com.techfamz.slimshotai.homewidget

import android.content.Context
import android.content.Intent
import com.techfamz.slimshotai.MainActivity

/**
 * The taps the home screen widget and the icon's menu send the app, and what
 * the app's Dart side reads from them (`LaunchAction.fromWire`).
 */
object LaunchIntents {

    const val CONTINUE = "com.techfamz.slimshotai.action.CONTINUE"
    const val NEW_VIDEO = "com.techfamz.slimshotai.action.NEW_VIDEO"
    const val COMPRESS_VIDEO = "com.techfamz.slimshotai.action.COMPRESS_VIDEO"
    const val EXTRA_DRAFT_ID = "draftId"

    /**
     * [action] for the app's one activity. Brought forward when it is
     * already running — it gets the tap through `onNewIntent` — rather than
     * started a second time beside the one holding the editor.
     */
    fun forMainActivity(context: Context, action: String, draftId: String?): Intent =
        Intent(context, MainActivity::class.java).apply {
            this.action = action
            if (draftId != null) putExtra(EXTRA_DRAFT_ID, draftId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }

    /**
     * What a tap says over the channel, or null when the intent is no tap.
     * [launchedFromHistory] is Android reopening the app from Recents with
     * the intent it was started with: no tap at all, so nothing repeats.
     */
    fun toWire(action: String?, draftId: String?, launchedFromHistory: Boolean): Map<String, Any?>? {
        if (launchedFromHistory) return null
        return when (action) {
            CONTINUE ->
                if (draftId.isNullOrEmpty()) null
                else mapOf("action" to "continue", "draftId" to draftId)
            NEW_VIDEO -> mapOf("action" to "new_video", "draftId" to null)
            COMPRESS_VIDEO -> mapOf("action" to "compress_video", "draftId" to null)
            else -> null
        }
    }
}
