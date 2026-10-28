package com.techfamz.slimshotai.homewidget

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import com.techfamz.slimshotai.thumbnails.StillImageDecoder
import java.io.File
import java.io.FileOutputStream
import kotlin.math.ceil

/**
 * The widget's cover, prepared once when the last edit changes: decoded small
 * and the right way up ([StillImageDecoder]), cut to 9:16, its corners
 * rounded — a widget cannot clip a picture on older Android — and kept as a
 * small PNG, so the hourly redraw never decodes the draft's own cover and a
 * large bitmap never reaches the launcher.
 */
internal object CoverPicture {

    /** The mockup's corner: 14 on a cover 110 tall. */
    private const val CORNER_FRACTION = 14f / 110f

    /** Writes the cover to [out]; false, and no [out], when [source] will not decode. */
    fun prepare(source: File, out: File): Boolean {
        val picture = try {
            draw(source)
        } catch (e: Exception) {
            null
        } catch (e: OutOfMemoryError) {
            null
        }
        if (picture == null) {
            out.delete()
            return false
        }
        val part = File(out.path + ".part")
        return try {
            FileOutputStream(part).use { picture.compress(Bitmap.CompressFormat.PNG, 100, it) }
            // Whole or not at all: the widget may draw from it at any moment.
            if (part.renameTo(out)) {
                true
            } else {
                part.delete()
                out.delete()
                false
            }
        } catch (e: Exception) {
            part.delete()
            out.delete()
            false
        } finally {
            picture.recycle()
        }
    }

    private fun draw(source: File): Bitmap? {
        if (!source.isFile) return null
        val (width, height) = StillImageDecoder.bounds(source.path) ?: return null
        val crop = CoverCrop.centre(width, height)
        val size = CoverCrop.output(crop[2], crop[3])
        // Decoded at about twice the cover's size, so scaling down stays sharp.
        val scale = minOf(1.0, 2.0 * size[1] / crop[3])
        val decoded = StillImageDecoder.decode(
            source.path,
            maxOf(1, ceil(width * scale).toInt()),
            maxOf(1, ceil(height * scale).toInt()),
        ) ?: return null

        val cut = CoverCrop.centre(decoded.width, decoded.height)
        val cover = Bitmap.createBitmap(size[0], size[1], Bitmap.Config.ARGB_8888)
        val bounds = RectF(0f, 0f, size[0].toFloat(), size[1].toFloat())
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            shader = BitmapShader(decoded, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
                setLocalMatrix(
                    Matrix().apply {
                        setRectToRect(
                            RectF(
                                cut[0].toFloat(),
                                cut[1].toFloat(),
                                (cut[0] + cut[2]).toFloat(),
                                (cut[1] + cut[3]).toFloat(),
                            ),
                            bounds,
                            Matrix.ScaleToFit.FILL,
                        )
                    },
                )
            }
        }
        val radius = size[1] * CORNER_FRACTION
        Canvas(cover).drawRoundRect(bounds, radius, radius, paint)
        decoded.recycle()
        return cover
    }
}
