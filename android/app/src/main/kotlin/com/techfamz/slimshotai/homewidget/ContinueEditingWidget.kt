package com.techfamz.slimshotai.homewidget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.BitmapFactory
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import com.techfamz.slimshotai.R
import java.util.Locale
import java.util.TimeZone

/**
 * The "Continue editing" home screen widget: the last edit — its cover, when
 * it was edited, its clips and length — one tap from the editor, or, before
 * any edit, a way to start one. A tap anywhere on the card does what its
 * button says.
 *
 * It draws from [HomeWidgetStore] alone, so it draws with the app closed: on
 * every change the app sends (`HomeWidgetChannel`) and hourly
 * (`updatePeriodMillis`), which is what turns "today" into "yesterday".
 */
class ContinueEditingWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetManager.updateAppWidget(appWidgetIds, viewsFor(context, System.currentTimeMillis()))
    }

    companion object {

        private const val REQUEST_CONTINUE = 1
        private const val REQUEST_NEW_VIDEO = 2

        /** Redraws every widget placed, from what the store holds now. */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(
                ComponentName(context, ContinueEditingWidget::class.java),
            )
            if (ids.isEmpty()) return
            manager.updateAppWidget(ids, viewsFor(context, System.currentTimeMillis()))
        }

        private fun viewsFor(context: Context, now: Long): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_continue_editing)
            val edit = HomeWidgetStore.read(context)
                ?.takeUnless { DraftAge.expired(it.editedAtMillis, now) }
            val tap = if (edit == null) {
                showNoEdit(context, views)
                pendingIntent(context, REQUEST_NEW_VIDEO, LaunchIntents.NEW_VIDEO, null)
            } else {
                showEdit(context, views, edit, now)
                pendingIntent(context, REQUEST_CONTINUE, LaunchIntents.CONTINUE, edit.draftId)
            }
            views.setOnClickPendingIntent(android.R.id.background, tap)
            views.setOnClickPendingIntent(R.id.widget_button, tap)
            return views
        }

        private fun showNoEdit(context: Context, views: RemoteViews) {
            views.setImageViewResource(R.id.widget_cover, R.drawable.widget_placeholder)
            views.setViewVisibility(R.id.widget_placeholder_plus, View.VISIBLE)
            views.setViewVisibility(R.id.widget_length, View.GONE)
            views.setTextViewText(R.id.widget_kicker, context.getString(R.string.widget_kicker_no_edit))
            views.setTextViewText(R.id.widget_title, context.getString(R.string.widget_title_no_edit))
            views.setTextViewText(R.id.widget_sub, context.getString(R.string.widget_sub_no_edit))
            views.setTextViewText(R.id.widget_button, context.getString(R.string.widget_button_start))
        }

        private fun showEdit(context: Context, views: RemoteViews, edit: StoredEdit, now: Long) {
            val cover = HomeWidgetStore.coverFile(context).takeIf { it.isFile }?.let {
                BitmapFactory.decodeFile(it.path)
            }
            if (cover != null) {
                views.setImageViewBitmap(R.id.widget_cover, cover)
            } else {
                // A cover that is gone or will not read: the frame, without the plus.
                views.setImageViewResource(R.id.widget_cover, R.drawable.widget_placeholder)
            }
            views.setViewVisibility(R.id.widget_placeholder_plus, View.GONE)

            val length = edit.lengthSeconds
            if (length != null) {
                views.setTextViewText(R.id.widget_length, WidgetText.length(length))
                views.setViewVisibility(R.id.widget_length, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_length, View.GONE)
            }

            val locale = Locale.getDefault()
            views.setTextViewText(R.id.widget_kicker, context.getString(R.string.widget_kicker))
            views.setTextViewText(
                R.id.widget_title,
                WidgetText.edited(
                    edit.editedAtMillis,
                    now,
                    TimeZone.getDefault(),
                    locale,
                    DateFormat.getBestDateTimePattern(locale, "dMMM"),
                ),
            )
            views.setTextViewText(R.id.widget_sub, WidgetText.clips(edit.clips))
            views.setTextViewText(R.id.widget_button, context.getString(R.string.widget_button_continue))
        }

        private fun pendingIntent(
            context: Context,
            requestCode: Int,
            action: String,
            draftId: String?,
        ): PendingIntent = PendingIntent.getActivity(
            context,
            requestCode,
            LaunchIntents.forMainActivity(context, action, draftId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
