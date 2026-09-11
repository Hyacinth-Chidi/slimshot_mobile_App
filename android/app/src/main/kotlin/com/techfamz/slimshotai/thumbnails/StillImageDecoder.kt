package com.techfamz.slimshotai.thumbnails

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.Log

/**
 * Decodes a photo into a bitmap, downscaled and turned the right way up.
 *
 * One implementation for every consumer: the filmstrip asks for a tile-sized
 * bitmap, export asks for a canvas-sized one. Copying the decode into the export
 * path would be the easiest way to make an exported photo differ from the one on
 * the filmstrip and in the preview — a rotated photo would land sideways in
 * exactly one of them.
 *
 * **Orientation is applied here.** A phone camera writes the sensor's pixels and
 * an EXIF tag saying how to turn them, and Media3's image decoder — which is what
 * feeds the preview — honours that tag. Anything that decodes with
 * [BitmapFactory] alone and skips it renders the same photo on its side.
 */
internal object StillImageDecoder {

    /**
     * Decodes [path] to fit inside [maxWidth] x [maxHeight], preserving shape.
     *
     * Never upscales: a photo smaller than the box comes back at its own size.
     * Returns null when the file is not an image this device can decode.
     */
    fun decode(path: String, maxWidth: Int, maxHeight: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        // inSampleSize halves on each step, so this only has to get close; the
        // exact fit comes from the scale below. Reading a 12MP photo at full
        // size to draw it into a 720x1280 canvas is pure allocation on a
        // low-end device.
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= maxWidth &&
            bounds.outHeight / (sample * 2) >= maxHeight
        ) {
            sample *= 2
        }

        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val decoded = BitmapFactory.decodeFile(path, options) ?: return null
        return scaleToFit(applyOrientation(path, decoded), maxWidth, maxHeight)
    }

    /**
     * The photo's on-screen shape, with EXIF rotation already applied.
     *
     * Reported rather than derived by callers, because a portrait photo from a
     * phone camera stores landscape pixels: a timeline that trusted the raw
     * bounds would letterbox it as though it were landscape and squash it. This
     * is the same correction [VideoThumbnailProvider] already makes for a video
     * that carries a rotation tag.
     */
    fun bounds(path: String): Pair<Int, Int>? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        return if (quarterTurns(path) % 2 == 1) {
            Pair(bounds.outHeight, bounds.outWidth)
        } else {
            Pair(bounds.outWidth, bounds.outHeight)
        }
    }

    /** Number of 90 degree turns [path]'s EXIF orientation asks for. */
    private fun quarterTurns(path: String): Int {
        return try {
            when (
                ExifInterface(path).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            ) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 1
                ExifInterface.ORIENTATION_ROTATE_180 -> 2
                ExifInterface.ORIENTATION_ROTATE_270 -> 3
                else -> 0
            }
        } catch (error: Exception) {
            // A PNG, or a file with no EXIF block at all. Not an error.
            Log.d(TAG, "No usable EXIF in $path: ${error.message}")
            0
        }
    }

    private fun applyOrientation(path: String, source: Bitmap): Bitmap {
        val turns = quarterTurns(path)
        if (turns == 0) return source

        val matrix = Matrix().apply { postRotate(turns * 90f) }
        return try {
            val rotated = Bitmap.createBitmap(
                source,
                0,
                0,
                source.width,
                source.height,
                matrix,
                true,
            )
            if (rotated !== source) source.recycle()
            rotated
        } catch (error: OutOfMemoryError) {
            Log.w(TAG, "Not enough memory to rotate $path; using it as decoded")
            source
        }
    }

    /** Scales down to fit the box. A bitmap already inside it is returned as is. */
    private fun scaleToFit(source: Bitmap, maxWidth: Int, maxHeight: Int): Bitmap {
        val scale = minOf(
            maxWidth.toFloat() / source.width,
            maxHeight.toFloat() / source.height,
        ).coerceAtMost(1f)
        if (scale >= 1f) return source

        val scaled = Bitmap.createScaledBitmap(
            source,
            (source.width * scale).toInt().coerceAtLeast(1),
            (source.height * scale).toInt().coerceAtLeast(1),
            true,
        )
        if (scaled !== source) source.recycle()
        return scaled
    }

    private const val TAG = "StillImageDecoder"
}
