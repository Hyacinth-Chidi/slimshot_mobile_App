package com.techfamz.slimshotai.homewidget

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * The app's end of the home screen widget and the icon's menu
 * (`HomeWidgetSync` and `LaunchChannel` in Dart):
 *
 * - `setLastEdit` — the edit the widget shows, or null for none. Kept in
 *   [HomeWidgetStore] with its cover prepared beside it, then every widget
 *   is redrawn. Answered at once; the work runs in order on a thread of its
 *   own, since a cover is decoded.
 * - `takeLaunchAction` — the tap the app was started with, handed out once.
 * - `launchAction` — a later tap, sent to Dart ([deliver]).
 */
class HomeWidgetChannel(
    context: Context,
    private val channel: MethodChannel,
    start: Map<String, Any?>?,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val channelName = "slimshot_ai/home_widget"
        private const val TAG = "SlimshotWidget"
    }

    private val context: Context = context.applicationContext
    private val mailbox = LaunchMailbox(start)
    private val worker: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "slimshot-home-widget")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setLastEdit" -> {
                val edit = parse(call.arguments)
                result.success(null)
                try {
                    worker.execute { keep(edit) }
                } catch (e: RejectedExecutionException) {
                    // The activity is going; the next launch sends the edit again.
                }
            }
            "takeLaunchAction" -> result.success(mailbox.take())
            else -> result.notImplemented()
        }
    }

    /** A tap that arrived while the app was running. */
    fun deliver(action: Map<String, Any?>) {
        mailbox.arrive(action)?.let { channel.invokeMethod("launchAction", it) }
    }

    /** Lets the work already asked for finish, and takes no more. */
    fun release() = worker.shutdown()

    private class Edit(val stored: StoredEdit, val coverPath: String?)

    private fun parse(arguments: Any?): Edit? {
        val map = arguments as? Map<*, *> ?: return null
        val draftId = map["draftId"] as? String ?: return null
        val editedAt = (map["editedAtMillis"] as? Number)?.toLong() ?: return null
        return Edit(
            StoredEdit(
                draftId = draftId,
                editedAtMillis = editedAt,
                clips = (map["clips"] as? Number)?.toInt() ?: 0,
                lengthSeconds = (map["lengthSeconds"] as? Number)?.toDouble(),
            ),
            map["coverPath"] as? String,
        )
    }

    private fun keep(edit: Edit?) {
        try {
            val cover = HomeWidgetStore.coverFile(context)
            if (edit == null) {
                HomeWidgetStore.clear(context)
                cover.delete()
            } else {
                // Prepared again on every call, never skipped for the same
                // draft: a new cover chosen for an edit keeps its draft id.
                val path = edit.coverPath
                if (path == null || !CoverPicture.prepare(File(path), cover)) cover.delete()
                HomeWidgetStore.save(context, edit.stored)
            }
            ContinueEditingWidget.updateAll(context)
        } catch (e: Exception) {
            Log.w(TAG, "home screen widget not updated", e)
        }
    }
}
