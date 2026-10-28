package com.techfamz.slimshotai.homewidget

/**
 * The app deletes a draft left for more than [MAX_DAYS] whole days
 * (`DraftService._maxAgeDays` in Dart — if one changes, the other must). A
 * widget nobody has refreshed since draws such an edit as no edit, rather
 * than offering one the app no longer has.
 */
object DraftAge {

    const val MAX_DAYS = 20

    private const val DAY_MS = 86_400_000L

    fun expired(editedAtMillis: Long, nowMillis: Long): Boolean =
        (nowMillis - editedAtMillis) / DAY_MS > MAX_DAYS
}
