package com.techfamz.slimshotai.homewidget

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The app deletes a draft left for more than 20 whole days
 * (`DraftService._maxAgeDays`); a widget nobody refreshed must not offer one.
 */
class DraftAgeTest {

    private val day = 86_400_000L

    @Test
    fun `an edit expires after more than twenty whole days`() {
        assertFalse(DraftAge.expired(0, 21 * day - 1))
        assertTrue(DraftAge.expired(0, 21 * day))
    }

    @Test
    fun `a clock set back expires nothing`() {
        assertFalse(DraftAge.expired(day, 0))
    }
}
