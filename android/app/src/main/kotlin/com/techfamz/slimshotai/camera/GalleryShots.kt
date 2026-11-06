package com.techfamz.slimshotai.camera

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.IOException

/**
 * The camera's shots in the phone's gallery: the **SlimShotAI** album, where
 * the app's exports and compressions already go, so everything SlimShot makes
 * is in one place — visible to every gallery, picker and backup, and kept if
 * the app is uninstalled.
 *
 * Android 11 and up let an app write the gallery and read its own files back
 * by path with no permission. Android 10 and older need storage access for
 * both ([needsPermission]); refused, the camera keeps shots in its own folder.
 * A shot is found again by its content address (deleting goes through it) and
 * its path (what the viewer and the editor read).
 */
internal object GalleryShots {
    const val ALBUM = "SlimShotAI"
    private const val TAG = "SlimshotCamera"

    val needsPermission: Boolean get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.R

    /** The name a shot takes in the gallery: `SlimShot_IMG_…jpg`. */
    fun galleryName(file: File): String = "SlimShot_${file.name}"

    /** Where a new shot named [name] goes in the album. */
    fun values(name: String, mime: String): ContentValues = ContentValues().apply {
        put(MediaStore.MediaColumns.DISPLAY_NAME, name)
        put(MediaStore.MediaColumns.MIME_TYPE, mime)
        put(MediaStore.Images.ImageColumns.DATE_TAKEN, System.currentTimeMillis())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$ALBUM")
        } else {
            @Suppress("DEPRECATION")
            val album = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), ALBUM)
            album.mkdirs()
            @Suppress("DEPRECATION")
            put(MediaStore.MediaColumns.DATA, File(album, name).absolutePath)
        }
    }

    /**
     * Moves a finished photo into the album. Null when the gallery would not
     * take it — the photo then stays where it is, not lost.
     */
    fun publishPhoto(context: Context, file: File): Pair<String, Uri>? = publish(context, file, "image/jpeg")

    /**
     * Moves a finished video into the album — a REACT reaction, rendered
     * after the take. Null when the gallery would not take it; the file then
     * stays where it is.
     */
    fun publishVideo(context: Context, file: File): Pair<String, Uri>? = publish(context, file, "video/mp4")

    private fun publish(context: Context, file: File, mime: String): Pair<String, Uri>? {
        val resolver = context.contentResolver
        val values = values(galleryName(file), mime)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) values.put(MediaStore.MediaColumns.IS_PENDING, 1)
        val collection = if (mime.startsWith("video/")) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val uri = try {
            resolver.insert(collection, values)
        } catch (error: Exception) {
            Log.w(TAG, "the gallery refused ${file.name}", error)
            null
        } ?: return null
        return try {
            resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
                ?: throw IOException("no output stream for $uri")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            }
            val path = pathOf(context, uri) ?: throw IOException("no path for $uri")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) scan(context, path, mime)
            file.delete()
            Pair(path, uri)
        } catch (error: Exception) {
            Log.w(TAG, "could not save ${file.name} to the gallery", error)
            try {
                resolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            null
        }
    }

    /** The file behind a gallery address. */
    fun pathOf(context: Context, uri: Uri): String? = try {
        @Suppress("DEPRECATION")
        context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    } catch (error: Exception) {
        Log.w(TAG, "no path for $uri", error)
        null
    }

    /** Older galleries learn of a file written by path only when it is scanned. */
    fun scan(context: Context, path: String, mime: String) {
        MediaScannerConnection.scanFile(context, arrayOf(path), arrayOf(mime), null)
    }

    /** Deletes a shot from the gallery, file and all. False where the phone would not. */
    fun delete(context: Context, uri: Uri): Boolean = try {
        context.contentResolver.delete(uri, null, null) > 0
    } catch (error: Exception) {
        Log.w(TAG, "could not delete $uri", error)
        false
    }
}
