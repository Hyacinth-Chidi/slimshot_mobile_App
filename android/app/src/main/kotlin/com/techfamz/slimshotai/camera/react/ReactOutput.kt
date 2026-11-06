package com.techfamz.slimshotai.camera.react

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.util.Log
import com.techfamz.slimshotai.camera.GalleryShots
import java.io.File
import java.io.FileOutputStream

/**
 * Where a live reaction is written: **straight into the gallery's SlimShotAI
 * album** through a pending MediaStore entry and its file descriptor —
 * CameraX's own way, so a long reaction is never copied afterwards — or, where
 * the gallery is refused, the camera's own folder.
 */
internal class ReactOutput private constructor(
    private val context: Context,
    val stream: FileOutputStream,
    private val descriptor: ParcelFileDescriptor?,
    private val uri: Uri?,
    private val file: File?,
) {
    /** The finished file made visible: its path and gallery address; null where it could not be kept. */
    fun publish(): Pair<String, String?>? {
        try {
            descriptor?.close()
        } catch (_: Exception) {
            // Closing twice is harmless: the muxer closed the stream.
        }
        val entry = uri ?: return file?.takeIf { it.exists() && it.length() > 0 }?.let { it.absolutePath to null }
        return try {
            val resolver = context.contentResolver
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.update(entry, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            }
            val path = GalleryShots.pathOf(context, entry) ?: throw IllegalStateException("no path for $entry")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) GalleryShots.scan(context, path, MIME)
            path to entry.toString()
        } catch (error: Exception) {
            Log.w(TAG, "the reaction could not be published", error)
            abandon()
            null
        }
    }

    /** Nothing usable was written: the entry or file goes. */
    fun abandon() {
        try {
            stream.close()
        } catch (_: Exception) {
        }
        try {
            descriptor?.close()
        } catch (_: Exception) {
        }
        uri?.let { GalleryShots.delete(context, it) }
        file?.delete()
    }

    companion object {
        private const val TAG = "SlimshotCamera"
        private const val MIME = "video/mp4"

        /** A gallery entry named for [path] when [toGallery], else [path] itself. */
        fun open(context: Context, path: String, toGallery: Boolean): ReactOutput {
            val file = File(path).also { it.parentFile?.mkdirs() }
            if (toGallery) {
                val resolver = context.contentResolver
                val values = GalleryShots.values(GalleryShots.galleryName(file), MIME)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) values.put(MediaStore.MediaColumns.IS_PENDING, 1)
                val entry = try {
                    resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                } catch (error: Exception) {
                    Log.w(TAG, "the gallery refused the reaction; keeping it in SlimShot", error)
                    null
                }
                if (entry != null) {
                    try {
                        val descriptor = resolver.openFileDescriptor(entry, "rw")
                            ?: throw IllegalStateException("no descriptor for $entry")
                        return ReactOutput(context, FileOutputStream(descriptor.fileDescriptor), descriptor, entry, null)
                    } catch (error: Exception) {
                        Log.w(TAG, "the gallery entry could not be opened; keeping it in SlimShot", error)
                        GalleryShots.delete(context, entry)
                    }
                }
            }
            return ReactOutput(context, FileOutputStream(file), null, null, file)
        }
    }
}
