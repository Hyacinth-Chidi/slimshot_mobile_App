package com.techfamz.slimshotai.nativepreview.gl

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader

/**
 * The picture an effect tile plays its effect on: a city at dusk.
 *
 * **Not the transitions' sunset**, and the reason is what each tile has to
 * show. A transition is judged by how one picture becomes another, so two
 * simple pictures serve; an effect is judged by what it does *to* a picture,
 * and the sunset — a smooth gradient, a disc, a hill — gave most effects
 * nothing to work on (the user's report: the effects barely showed). This
 * scene carries what every kind of effect needs:
 *
 * * **highlights** — the moon, stars, lit windows — for sparkle, glow and
 *   light leaks;
 * * **edges** — the skyline — for neon, sharpen and chromatic split;
 * * **a full range of tones** — a dusk sky from deep blue to orange, near-black
 *   buildings — for grades, duotone, vignette and grain;
 * * **saturated colour** — two neon signs — for colour shifts;
 * * **a regular grid** — the windows — so a fisheye, ripple or swirl visibly
 *   bends something straight.
 *
 * Drawn in code at the cell's size, so it costs the app nothing and is crisp
 * at any size. Stored **upside down**, as the transitions' samples are, so
 * GL's bottom-up rows come out upright once the atlas is read back and flipped.
 */
internal object EffectPreviewSample {

    fun city(width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap).apply { scale(1f, -1f, width / 2f, height / 2f) }
        val w = width.toFloat()
        val h = height.toFloat()
        val m = minOf(w, h)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        // A dusk sky: deep blue overhead, violet, warm orange at the horizon.
        paint.shader = LinearGradient(
            0f, 0f, 0f, h,
            intArrayOf(0xFF1E2A78.toInt(), 0xFF8A3F9E.toInt(), 0xFFF59A45.toInt()),
            floatArrayOf(0f, 0.36f, 0.66f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, 0f, w, h, paint)

        // The moon and its glow.
        val moonX = w * 0.78f
        val moonY = h * 0.2f
        paint.shader = RadialGradient(
            moonX, moonY, m * 0.2f,
            intArrayOf(0x99FFE9B0.toInt(), 0x00FFE9B0),
            null,
            Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(moonX, moonY, m * 0.2f, paint)
        paint.shader = null
        paint.color = 0xFFFFF3C4.toInt()
        canvas.drawCircle(moonX, moonY, m * 0.07f, paint)

        // A few stars.
        paint.color = 0xFFFFFFFF.toInt()
        for ((sx, sy) in STARS) canvas.drawCircle(w * sx, h * sy, maxOf(1f, m * 0.012f), paint)

        // The skyline, its windows lit on a deterministic pattern.
        for ((index, building) in BUILDINGS.withIndex()) {
            val left = w * building.left
            val right = w * building.right
            val top = h * building.top
            val bottom = h * WATER
            paint.color = building.colour
            canvas.drawRect(left, top, right, bottom, paint)
            val cols = maxOf(2, ((right - left) / 7f).toInt())
            val rows = maxOf(2, ((bottom - top) / 8f).toInt())
            val windowW = maxOf(1.5f, w * 0.018f)
            val windowH = maxOf(1.5f, h * 0.022f)
            for (row in 0 until rows) {
                for (col in 0 until cols) {
                    val hash = (index * 7919 + row * 104729 + col * 1299709) % 97
                    if (hash < 40) continue
                    val wx = left + (col + 0.3f) * (right - left) / cols
                    val wy = top + (row + 0.35f) * (bottom - top) / rows
                    val colour = if (hash % 5 == 0) 0xFF8FE6FF.toInt() else 0xFFFFD36E.toInt()
                    paint.color = colour
                    canvas.drawRect(wx, wy, wx + windowW, wy + windowH, paint)
                    // Its reflection, squashed into the water and dimmed.
                    val reflectY = h * WATER + (h * WATER - wy) * 0.35f
                    if (reflectY < h) {
                        paint.color = (colour and 0x00FFFFFF) or 0x73000000
                        canvas.drawRect(wx, reflectY, wx + windowW, reflectY + maxOf(1f, h * 0.012f), paint)
                    }
                }
            }
        }

        // Two neon signs: the scene's saturated colour.
        paint.color = 0xFFFF3B5C.toInt()
        canvas.drawRect(w * 0.27f, h * 0.6f, w * 0.35f, h * 0.64f, paint)
        paint.color = 0xFF2EE6C8.toInt()
        canvas.drawRect(w * 0.64f, h * 0.5f, w * 0.76f, h * 0.535f, paint)

        // The water, under the reflections drawn with the windows.
        paint.color = 0xB3101533.toInt()
        canvas.drawRect(0f, h * WATER, w, h, paint)
        return bitmap
    }

    private class Building(val left: Float, val right: Float, val top: Float, val colour: Int)

    private const val WATER = 0.84f

    private val STARS = listOf(
        0.12f to 0.1f, 0.3f to 0.06f, 0.45f to 0.16f, 0.6f to 0.08f, 0.92f to 0.36f, 0.2f to 0.3f,
    )

    private val BUILDINGS = listOf(
        Building(0.0f, 0.13f, 0.5f, 0xFF272C52.toInt()),
        Building(0.11f, 0.25f, 0.36f, 0xFF1B1F3B.toInt()),
        Building(0.25f, 0.37f, 0.55f, 0xFF343A6B.toInt()),
        Building(0.36f, 0.52f, 0.28f, 0xFF22264A.toInt()),
        Building(0.52f, 0.63f, 0.46f, 0xFF2E3463.toInt()),
        Building(0.62f, 0.8f, 0.4f, 0xFF1B1F3B.toInt()),
        Building(0.8f, 0.9f, 0.58f, 0xFF343A6B.toInt()),
        Building(0.88f, 1.0f, 0.44f, 0xFF272C52.toInt()),
    )
}
