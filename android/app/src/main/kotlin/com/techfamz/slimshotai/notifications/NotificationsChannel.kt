package com.techfamz.slimshotai.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.techfamz.slimshotai.MainActivity
import com.techfamz.slimshotai.R
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Notifications sent from the dashboard. Firebase draws them itself while the app is in the
 * background or closed — in [CHANNEL_ID], with the small icon and colour the manifest names — and
 * hands them to Dart while the app is open, where nothing would show them. This draws those, the
 * same way, so a notification looks the same whether the app was open or not.
 */
class NotificationsChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> {
                runCatching {
                    show(call.argument<String>("title") ?: "", call.argument<String>("body") ?: "")
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun show(title: String, body: String) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (!manager.areNotificationsEnabled()) return
        ensureChannel(context)
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_slimshot)
            .setColor(context.getColor(R.color.notification_accent))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        manager.notify(nextId++, notification)
    }

    companion object {
        const val channelName = "slimshot_ai/notifications"

        /**
         * The one notification channel. The manifest names it as Firebase's default, so a
         * notification drawn by Firebase and one drawn here land in the same place, under the
         * same switch in the phone's settings. `push_android_test.dart` pins the two names.
         */
        const val CHANNEL_ID = "slimshot_general"

        private var nextId = 1

        /** Made at every start, so it exists before the first notification arrives. */
        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.notification_channel_name),
                    NotificationManager.IMPORTANCE_HIGH,
                ),
            )
        }
    }
}
