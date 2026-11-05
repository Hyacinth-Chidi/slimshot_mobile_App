package com.techfamz.slimshotai.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * What an EXIF orientation asks of a viewer: mirror the stored pixels across
 * the vertical axis (when [flip]), **then** turn them [degrees] clockwise. The
 * eight orientations, read the way the EXIF spec defines them
 * (`ExifTurnTest` checks each against where the stored top-left pixel lands).
 */
internal data class ExifTurn(val flip: Boolean, val degrees: Int) {

    /**
     * A mirrored orientation, which the editor's photo decoders do not read
     * (they take the plain turns only), so the pixels must carry it.
     */
    val needsBaking: Boolean get() = flip

    companion object {
        fun of(orientation: Int): ExifTurn = when (orientation) {
            2 -> ExifTurn(flip = true, degrees = 0)
            3 -> ExifTurn(flip = false, degrees = 180)
            4 -> ExifTurn(flip = true, degrees = 180)
            5 -> ExifTurn(flip = true, degrees = 270)
            6 -> ExifTurn(flip = false, degrees = 90)
            7 -> ExifTurn(flip = true, degrees = 90)
            8 -> ExifTurn(flip = false, degrees = 270)
            else -> ExifTurn(flip = false, degrees = 0)
        }
    }
}

/**
 * A selfie saved mirrored, as it was seen: CameraX writes the mirror into the
 * EXIF orientation rather than the pixels, and the editor's decoders —
 * `StillImageDecoder` for the filmstrip and the export, Media3's for the
 * preview — read only the plain turns, so the photo would land unmirrored, and
 * sideways where the orientation is a mirrored turn (5, 7). Baked here, the
 * file is upright in its pixels and every reader agrees with the review.
 *
 * Only a flipped photo is rewritten; a plain turn stays in the EXIF, which
 * everything reads, and costs nothing. Off the main thread: a full-size decode
 * and encode takes a few hundred milliseconds.
 */
internal object PhotoBaker {
    private const val TAG = "SlimshotCamera"
    private const val JPEG_QUALITY = 95

    fun bakeIfFlipped(file: File) {
        val turn = try {
            ExifTurn.of(
                ExifInterface(file.path).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                ),
            )
        } catch (error: Exception) {
            return
        }
        if (!turn.needsBaking) return

        val source = BitmapFactory.decodeFile(file.path) ?: return
        var baked: Bitmap? = null
        try {
            val matrix = Matrix().apply {
                postScale(-1f, 1f)
                postRotate(turn.degrees.toFloat())
            }
            baked = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
            val part = File(file.parentFile, "${file.name}.part")
            FileOutputStream(part).use { baked.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, it) }
            // A fresh JPEG carries no orientation: upright as it is.
            if (!part.renameTo(file)) {
                part.delete()
                Log.w(TAG, "could not replace ${file.name} with its upright copy")
            }
        } catch (error: OutOfMemoryError) {
            Log.w(TAG, "not enough memory to bake ${file.name}; kept as saved")
        } catch (error: Exception) {
            Log.w(TAG, "could not bake ${file.name}; kept as saved", error)
        } finally {
            if (baked != null && baked !== source) baked.recycle()
            source.recycle()
        }
    }
}
