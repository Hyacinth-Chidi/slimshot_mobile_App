package com.techfamz.slimshotai.homewidget

import android.content.Context
import android.content.SharedPreferences
import java.io.File

/** The last edit, as the widget shows it. */
data class StoredEdit(
    val draftId: String,
    val editedAtMillis: Long,
    val clips: Int,
    val lengthSeconds: Double?,
)

/**
 * What the widget draws from, kept by the widget itself so it draws with the
 * app closed: the last edit, and its cover prepared once beside it.
 */
object HomeWidgetStore {

    private const val FILE = "slimshot_home_widget"
    private const val DRAFT_ID = "draftId"
    private const val EDITED_AT = "editedAtMillis"
    private const val CLIPS = "clips"
    private const val LENGTH = "lengthSeconds"

    fun save(context: Context, edit: StoredEdit) {
        prefs(context).edit()
            .putString(DRAFT_ID, edit.draftId)
            .putLong(EDITED_AT, edit.editedAtMillis)
            .putInt(CLIPS, edit.clips)
            .apply {
                if (edit.lengthSeconds != null) putString(LENGTH, edit.lengthSeconds.toString())
                else remove(LENGTH)
            }
            .commit()
    }

    fun read(context: Context): StoredEdit? {
        val prefs = prefs(context)
        val draftId = prefs.getString(DRAFT_ID, null) ?: return null
        return StoredEdit(
            draftId = draftId,
            editedAtMillis = prefs.getLong(EDITED_AT, 0L),
            clips = prefs.getInt(CLIPS, 0),
            lengthSeconds = prefs.getString(LENGTH, null)?.toDoubleOrNull(),
        )
    }

    fun clear(context: Context) {
        prefs(context).edit().clear().commit()
    }

    /** The cover, cut and rounded for the widget ([CoverPicture]). */
    fun coverFile(context: Context): File = File(context.filesDir, "home_widget_cover.png")

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
}
