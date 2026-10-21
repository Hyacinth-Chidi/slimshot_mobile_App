package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.effects.CameraShake
import com.techfamz.slimshotai.nativepreview.gl.effects.CameraShake.Pose
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.sqrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Handheld and Super Shake were reported from the device as not realistic.
 * Both drew a fresh random offset every frame from a hash that, at `mediump`,
 * returned almost nothing — on the device the frame sat at one offset, and
 * where the hash did work it was white noise, a vibration rather than a camera.
 * The motion is now worked out on the CPU from the bar's own seconds, as smooth
 * noise, and these pin what makes it read as a camera.
 */
class CameraShakeTest {

    private val fps = 30.0
    private val portrait = 9.0 / 16.0

    private fun poses(style: CameraShake.Style, intensity: Float, seconds: Double = 20.0) =
        (0 until (seconds * fps).toInt()).map {
            CameraShake.poseAt(style, it / fps, intensity, portrait)
        }

    @Test
    fun `at zero intensity the camera is still`() {
        for (style in listOf(CameraShake.HANDHELD, CameraShake.SUPER_SHAKE)) {
            for (t in listOf(0.0, 0.37, 2.0, 11.5)) {
                assertEquals(Pose.STILL, CameraShake.poseAt(style, t, 0f, portrait))
            }
        }
    }

    @Test
    fun `the same instant always gives the same pose`() {
        val a = CameraShake.poseAt(CameraShake.SUPER_SHAKE, 3.217, 0.7f, portrait)
        val b = CameraShake.poseAt(CameraShake.SUPER_SHAKE, 3.217, 0.7f, portrait)
        assertEquals(a, b)
    }

    @Test
    fun `handheld glides from frame to frame - no jumps`() {
        // White noise moved the frame up to twice its range in one frame. A
        // hand moves the camera a little at a time.
        val style = CameraShake.HANDHELD
        val all = poses(style, 1f)
        val worst = all.zipWithNext { a, b -> max(abs(b.dx - a.dx), abs(b.dy - a.dy)) }.max()
        assertTrue("$worst per frame", worst <= 0.2 * style.amplitude)
    }

    @Test
    fun `handheld wanders across its range and turns`() {
        val style = CameraShake.HANDHELD
        val all = poses(style, 1f)
        val reach = all.maxOf { max(abs(it.dx), abs(it.dy)) }
        val rms = sqrt(all.sumOf { it.dx * it.dx + it.dy * it.dy } / (2 * all.size))
        val turn = all.maxOf { abs(it.radians) }
        assertTrue("reach $reach", reach >= 0.35 * style.amplitude)
        assertTrue("rms $rms", rms >= 0.12 * style.amplitude)
        assertTrue("turn $turn", turn >= 0.3 * style.maxRadians)
    }

    @Test
    fun `super shake moves several times faster than handheld`() {
        fun speed(style: CameraShake.Style) = poses(style, 1f)
            .zipWithNext { a, b -> hypot(b.dx - a.dx, b.dy - a.dy) }
            .average()
        val ratio = speed(CameraShake.SUPER_SHAKE) / speed(CameraShake.HANDHELD)
        assertTrue("ratio $ratio", ratio >= 4.0)
    }

    @Test
    fun `super shake punches in as well as shaking`() {
        val all = poses(CameraShake.SUPER_SHAKE, 1f)
        val cover = CameraShake.coverFor(CameraShake.SUPER_SHAKE, 1f, portrait)
        assertTrue(all.all { it.zoom >= cover - 1e-12 })
        assertTrue(all.any { it.zoom > cover * 1.02 })
        // Handheld never punches.
        val handheld = poses(CameraShake.HANDHELD, 1f)
        val handCover = CameraShake.coverFor(CameraShake.HANDHELD, 1f, portrait)
        assertTrue(handheld.all { abs(it.zoom - handCover) < 1e-12 })
    }

    @Test
    fun `the frame always covers the canvas - no edge ever shows`() {
        for (style in listOf(CameraShake.HANDHELD, CameraShake.SUPER_SHAKE)) {
            for (aspect in listOf(portrait, 1.0, 16.0 / 9.0)) {
                val hx = 0.5 * max(1.0, aspect)
                val hy = 0.5 * max(1.0, 1.0 / aspect)
                for (intensity in listOf(0.25f, 0.5f, 1f)) {
                    for (i in 0 until 600) {
                        val pose = CameraShake.poseAt(style, i / fps, intensity, aspect)
                        for ((px, py) in listOf(hx to hy, -hx to hy, hx to -hy, -hx to -hy)) {
                            val (u, v) = CameraShake.sampleOf(pose, px, py, aspect)
                            assertTrue("$aspect $intensity $i u=$u", u >= -1e-9 && u <= 1 + 1e-9)
                            assertTrue("$aspect $intensity $i v=$v", v >= -1e-9 && v <= 1 + 1e-9)
                        }
                    }
                }
            }
        }
    }

    @Test
    fun `handheld at its default crops the picture by under eight percent`() {
        assertTrue(CameraShake.coverFor(CameraShake.HANDHELD, 0.5f, portrait) <= 1.08)
        assertEquals(1.0, CameraShake.coverFor(CameraShake.HANDHELD, 0f, portrait), 0.0)
    }

    @Test
    fun `a still pose samples the picture where it is`() {
        val (u, v) = CameraShake.sampleOf(Pose.STILL, 0.25, -0.4, portrait)
        assertEquals(0.75, u, 1e-12)
        assertEquals(0.5 - 0.4 / (2 * 0.5 / portrait), v, 1e-12)
    }
}
