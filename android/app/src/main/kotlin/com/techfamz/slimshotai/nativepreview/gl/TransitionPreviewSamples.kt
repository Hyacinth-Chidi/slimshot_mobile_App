package com.techfamz.slimshotai.nativepreview.gl

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader

/**
 * The two pictures a transition tile plays between: a warm sunset and a cool
 * mountain range, drawn in code — no asset to ship and no licence to carry —
 * and different enough in colour and shape that every kind of transition
 * reads between them.
 *
 * **Stored upside down.** GL takes a bitmap's first row as the bottom of the
 * texture while the transition shaders sample with y running up, so each
 * picture is drawn flipped to come out the right way round.
 */
internal object TransitionPreviewSamples {

    /** The outgoing picture and the incoming one, at [width] x [height]. */
    fun pair(width: Int, height: Int): Pair<Bitmap, Bitmap> =
        Pair(sunset(width, height), mountains(width, height))

    private fun canvasFor(bitmap: Bitmap): Canvas = Canvas(bitmap).apply {
        scale(1f, -1f, bitmap.width / 2f, bitmap.height / 2f)
    }

    private fun sunset(width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = canvasFor(bitmap)
        val w = width.toFloat()
        val h = height.toFloat()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, 0f, h, 0xFFFF8A3D.toInt(), 0xFFC2185B.toInt(), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, w, h, paint)
        paint.shader = null
        paint.color = 0xFFFFE082.toInt()
        canvas.drawCircle(w * 0.32f, h * 0.36f, minOf(w, h) * 0.17f, paint)
        paint.color = 0xFF4A148C.toInt()
        val hill = Path().apply {
            moveTo(0f, h)
            lineTo(0f, h * 0.72f)
            quadTo(w * 0.35f, h * 0.58f, w * 0.65f, h * 0.70f)
            quadTo(w * 0.85f, h * 0.78f, w, h * 0.66f)
            lineTo(w, h)
            close()
        }
        canvas.drawPath(hill, paint)
        return bitmap
    }

    private fun mountains(width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = canvasFor(bitmap)
        val w = width.toFloat()
        val h = height.toFloat()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, 0f, h, 0xFF26C6DA.toInt(), 0xFF1A237E.toInt(), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, w, h, paint)
        paint.shader = null
        paint.color = 0xFF90A4AE.toInt()
        canvas.drawPath(triangle(w * 0.05f, h, w * 0.45f, h * 0.38f, w * 0.85f, h), paint)
        paint.color = 0xFFE0F7FA.toInt()
        canvas.drawPath(triangle(w * 0.40f, h, w * 0.75f, h * 0.30f, w * 1.10f, h), paint)
        return bitmap
    }

    private fun triangle(x1: Float, y1: Float, x2: Float, y2: Float, x3: Float, y3: Float) = Path().apply {
        moveTo(x1, y1)
        lineTo(x2, y2)
        lineTo(x3, y3)
        close()
    }
}
