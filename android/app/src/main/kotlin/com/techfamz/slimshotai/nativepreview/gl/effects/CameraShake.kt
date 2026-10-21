package com.techfamz.slimshotai.nativepreview.gl.effects

import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.sin

/**
 * Where a shaken camera points at an instant — Handheld's and Super Shake's
 * motion, worked out on the CPU and handed to the shader as one pose a frame.
 *
 * **Why not in the shader.** Both used to draw a fresh offset per frame from
 * `hash21(uProgress * rate)`. At `mediump` on a GPU that takes it literally
 * (the Infinix's PowerVR) that hash returns almost nothing, so the frame sat at
 * one fixed offset; where it did work it was white noise — every frame
 * unrelated to the last, a vibration rather than a camera (device-reported:
 * "not realistic"). The motion is the same for every pixel of a frame, so it
 * belongs on the CPU, in doubles, exact on every device and testable here.
 *
 * **Smooth noise, in seconds.** Each axis is a few octaves of value noise —
 * random levels at a regular beat, eased between with a quintic so the
 * velocity never jumps — at frequencies chosen for the motion: a hand sways at
 * well under 2Hz with a faint tremor on top; a shake jolts at 5 to 11Hz. The
 * clock is the bar's own seconds (`barSeconds`), timeline time and never wall
 * clock, so a shake has the same speed on a short bar as a long one and the
 * file shakes exactly as the canvas did.
 *
 * **The frame never shows an edge.** A fixed zoom per intensity and canvas
 * shape ([coverFor]) is worked out from the largest offset and turn the noise
 * can reach, so no pose ever samples outside the picture; Super Shake's punch
 * only zooms further in.
 */
internal object CameraShake {

    /**
     * One frame of a shaken camera: an offset in fractions of the frame's short
     * side, a turn in radians, and the zoom the frame is drawn at (≥ 1).
     */
    data class Pose(val dx: Double, val dy: Double, val radians: Double, val zoom: Double) {
        companion object {
            val STILL = Pose(0.0, 0.0, 0.0, 1.0)
        }
    }

    /** One layer of the noise: its rate and its share of the motion. */
    class Octave(val hertz: Double, val weight: Double)

    /** A kind of shake, at intensity 1. */
    class Style(
        /** The furthest the frame travels on each axis, in short sides. */
        val amplitude: Double,
        /** The furthest it turns, in radians. */
        val maxRadians: Double,
        /** The most it punches in, as a fraction of its zoom. */
        val punch: Double,
        val travel: List<Octave>,
        val roll: List<Octave>,
        val punchHertz: Double,
    )

    /**
     * A person holding the camera: a slow sway under 2Hz, a little faster
     * correction on top, and a faint 8.5Hz tremor — the physiological one —
     * with a turn of under two degrees. At the catalog's 0.5 the frame drifts
     * about 1% of its short side and turns about a quarter of a degree.
     */
    val HANDHELD = Style(
        amplitude = 0.045,
        maxRadians = 0.028,
        punch = 0.0,
        travel = listOf(Octave(0.6, 1.0), Octave(1.4, 0.5), Octave(3.1, 0.22), Octave(8.5, 0.06)),
        roll = listOf(Octave(0.45, 1.0), Octave(1.1, 0.45)),
        punchHertz = 0.0,
    )

    /**
     * A hard shake: jolts at 5 and 11Hz over a 2Hz heave, turns of up to three
     * and a half degrees, and punches in by up to 5% now and then. Drawn with a
     * shutter's blur along its own motion ([EXPOSURE_SECONDS]), which is what a
     * camera shaken this fast records.
     */
    val SUPER_SHAKE = Style(
        amplitude = 0.06,
        maxRadians = 0.061,
        punch = 0.05,
        travel = listOf(Octave(2.0, 0.35), Octave(5.0, 1.0), Octave(11.0, 0.55)),
        roll = listOf(Octave(4.0, 1.0), Octave(9.0, 0.5)),
        punchHertz = 3.0,
    )

    /** How long a frame's exposure is: a half-open shutter at 30fps. */
    const val EXPOSURE_SECONDS = 1.0 / 60.0

    private const val SEED_X = 11
    private const val SEED_Y = 23
    private const val SEED_ROLL = 37
    private const val SEED_PUNCH = 41

    /** The camera at [seconds] into its bar, for a canvas of [aspect] (width / height). */
    fun poseAt(style: Style, seconds: Double, intensity: Float, aspect: Double): Pose {
        val k = intensity.coerceIn(0f, 1f).toDouble()
        if (k <= 0.0) return Pose.STILL
        val t = max(0.0, seconds)
        val dx = style.amplitude * k * fbm(t, style.travel, SEED_X)
        val dy = style.amplitude * k * fbm(t, style.travel, SEED_Y)
        val radians = style.maxRadians * k * fbm(t, style.roll, SEED_ROLL)
        var zoom = coverFor(style, intensity, aspect)
        if (style.punch > 0.0) {
            // Mostly near zero, now and then a hit: the noise lifted to 0..1
            // and cubed.
            val lift = (noise(t * style.punchHertz, SEED_PUNCH) + 1.0) * 0.5
            zoom *= 1.0 + style.punch * k * lift * lift * lift
        }
        return Pose(dx, dy, radians, zoom)
    }

    /**
     * The zoom that keeps the frame covering the canvas through every pose
     * [style] can reach at [intensity]: the picture is drawn this much larger,
     * so its edges stay off screen however far it travels and turns.
     *
     * A corner of the canvas samples `R(-θ)(p - d) / zoom`; its x lands within
     * `|p.x| + |d| + sin|θ| (|p.y| + |d|)`, so the zoom must reach that over the
     * half-width — and likewise for y.
     */
    fun coverFor(style: Style, intensity: Float, aspect: Double): Double {
        val k = intensity.coerceIn(0f, 1f).toDouble()
        if (k <= 0.0) return 1.0
        val (hx, hy) = halfExtents(aspect)
        val d = style.amplitude * k
        val s = sin(style.maxRadians * k)
        val zx = (hx + d + s * (hy + d)) / hx
        val zy = (hy + d + s * (hx + d)) / hy
        return max(1.0, max(zx, zy))
    }

    /**
     * The texture coordinate the canvas point ([px], [py]) — short sides from
     * the centre — samples under [pose]. **The shader's arithmetic**, step for
     * step (`shakeUv` in the shake shaders), kept here so the cover can be
     * checked against it.
     */
    fun sampleOf(pose: Pose, px: Double, py: Double, aspect: Double): Pair<Double, Double> {
        val (hx, hy) = halfExtents(aspect)
        val qx = (px - pose.dx) / pose.zoom
        val qy = (py - pose.dy) / pose.zoom
        val c = cos(pose.radians)
        val s = sin(pose.radians)
        val rx = c * qx + s * qy
        val ry = -s * qx + c * qy
        return Pair(rx / (2 * hx) + 0.5, ry / (2 * hy) + 0.5)
    }

    /** Half the canvas's width and height, in short sides. */
    private fun halfExtents(aspect: Double): Pair<Double, Double> {
        val a = if (aspect > 0.0) aspect else 1.0
        return Pair(0.5 * max(1.0, a), 0.5 * max(1.0, 1.0 / a))
    }

    /** Octaves of [noise] summed by weight, within -1..1. */
    private fun fbm(t: Double, octaves: List<Octave>, seed: Int): Double {
        var sum = 0.0
        var weights = 0.0
        for ((i, octave) in octaves.withIndex()) {
            // Each octave offset in time, so their beats never fall together.
            sum += octave.weight * noise(t * octave.hertz + i * 17.37, seed + i * 31)
            weights += octave.weight
        }
        return if (weights > 0.0) sum / weights else 0.0
    }

    /**
     * Value noise in -1..1: a random level at every whole [t], eased between
     * with the quintic `6x⁵ - 15x⁴ + 10x³`, whose first and second derivatives
     * vanish at the beats — so the motion's speed and its change never jump.
     */
    fun noise(t: Double, seed: Int): Double {
        val i = floor(t)
        val f = t - i
        val a = PlanHash.signed(i.toLong(), seed)
        val b = PlanHash.signed(i.toLong() + 1, seed)
        val eased = f * f * f * (f * (f * 6.0 - 15.0) + 10.0)
        return a + (b - a) * eased
    }
}
