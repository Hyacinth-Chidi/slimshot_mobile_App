package com.techfamz.slimshotai.homewidget

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.roundToLong

/**
 * The "Continue editing" widget's words. Worked out when the widget draws —
 * hourly, and whenever the last edit changes — so "today" is said for exactly
 * as long as it is true.
 */
object WidgetText {

    private const val DAY_MS = 86_400_000L

    /**
     * "Edited today", "Edited yesterday", else "Edited 12 Oct". Days are
     * calendar days in [zone], never 24-hour spans: an edit at 23:59 is
     * yesterday's at 00:01. [datePattern] is the locale's own
     * (`DateFormat.getBestDateTimePattern(locale, "dMMM")`).
     */
    fun edited(
        editedAtMillis: Long,
        nowMillis: Long,
        zone: TimeZone,
        locale: Locale,
        datePattern: String,
    ): String = when (dayOf(nowMillis, zone) - dayOf(editedAtMillis, zone)) {
        0L -> "Edited today"
        1L -> "Edited yesterday"
        else -> "Edited " +
            SimpleDateFormat(datePattern, locale)
                .apply { timeZone = zone }
                .format(Date(editedAtMillis))
    }

    /** The edit's length in whole seconds: "0:42", "12:05", "1:02:03". */
    fun length(seconds: Double): String {
        val total = if (seconds.isFinite() && seconds > 0) seconds.roundToLong() else 0L
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val rest = total % 60
        return if (hours > 0) {
            String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, rest)
        } else {
            String.format(Locale.ROOT, "%d:%02d", minutes, rest)
        }
    }

    fun clips(count: Int): String = if (count == 1) "1 clip" else "$count clips"

    /** The calendar day [millis] falls on in [zone], counted from 1970. */
    private fun dayOf(millis: Long, zone: TimeZone): Long =
        Math.floorDiv(millis + zone.getOffset(millis), DAY_MS)
}
