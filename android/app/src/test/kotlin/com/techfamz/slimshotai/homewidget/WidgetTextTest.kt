package com.techfamz.slimshotai.homewidget

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * The widget's words, worked out when it draws: when the edit was made, in
 * the phone's own days, its length and its clips.
 */
class WidgetTextTest {

    private val lagos = TimeZone.getTimeZone("Africa/Lagos")

    private fun at(zone: TimeZone, y: Int, m: Int, d: Int, h: Int, min: Int): Long =
        Calendar.getInstance(zone).apply {
            clear()
            set(y, m - 1, d, h, min)
        }.timeInMillis

    private fun edited(then: Long, now: Long) =
        WidgetText.edited(then, now, lagos, Locale.UK, "d MMM")

    @Test
    fun `today and yesterday are calendar days, not 24-hour spans`() {
        assertEquals(
            "Edited today",
            edited(at(lagos, 2026, 10, 28, 0, 1), at(lagos, 2026, 10, 28, 23, 59)),
        )
        assertEquals(
            "Edited yesterday",
            edited(at(lagos, 2026, 10, 27, 23, 59), at(lagos, 2026, 10, 28, 0, 1)),
        )
        assertEquals(
            "Edited 12 Oct",
            edited(at(lagos, 2026, 10, 12, 9, 0), at(lagos, 2026, 10, 28, 9, 0)),
        )
    }

    @Test
    fun `the day is the phone's, not UTC's`() {
        // 23:30 UTC on the 27th is 00:30 on the 28th in Lagos.
        val utc = TimeZone.getTimeZone("UTC")
        assertEquals(
            "Edited today",
            edited(at(utc, 2026, 10, 27, 23, 30), at(lagos, 2026, 10, 28, 10, 0)),
        )
    }

    @Test
    fun `a new year's yesterday is last year's last day`() {
        assertEquals(
            "Edited yesterday",
            edited(at(lagos, 2026, 12, 31, 22, 0), at(lagos, 2027, 1, 1, 8, 0)),
        )
    }

    @Test
    fun `lengths are whole seconds, with hours from an hour`() {
        assertEquals(
            listOf("0:42", "12:05", "1:02:03", "0:00"),
            listOf(41.6, 725.0, 3723.0, 0.2).map(WidgetText::length),
        )
    }

    @Test
    fun `one clip, several clips`() {
        assertEquals("1 clip", WidgetText.clips(1))
        assertEquals("4 clips", WidgetText.clips(4))
    }
}
