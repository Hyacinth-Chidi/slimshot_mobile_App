package com.techfamz.slimshotai.nativepreview

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.min

/**
 * Speed as a function of where in the footage a clip is — the Kotlin port of
 * Dart's `SpeedCurve`, arithmetic for arithmetic.
 *
 * Speed interpolates linearly between points over the clip's **source**
 * fraction, so each segment integrates in closed form: reaching source
 * fraction `x` takes `∫ dx / v(x)` of timeline (a logarithm where the speed
 * ramps, a division where it is flat), and the source frame due at a timeline
 * instant is that integral's inverse (an exponential). Both engines resolve a
 * curved clip's source position through [sourceAtTime]; the preview
 * additionally sets the player's rate to [speedAtSource] as it goes.
 *
 * `speed_curve_fixture.json` pins this to the Dart side. A change here that
 * is not a change there is a clip landing on different frames in the file
 * than on the canvas.
 *
 * Structural equality is deliberate: the engine's soft timeline update
 * compares clips field by field to decide whether anything that *plays*
 * changed, and a curve is one of those fields.
 */
data class SpeedCurve(val xs: List<Double>, val speeds: List<Double>) {

    init {
        require(xs.size == speeds.size && xs.size >= 2) { "a curve needs two points" }
    }

    /** Playback rate at source fraction [x]. */
    fun speedAtSource(x: Double): Double {
        val xc = x.coerceIn(0.0, 1.0)
        for (i in 1 until xs.size) {
            if (xc <= xs[i]) {
                val w = xs[i] - xs[i - 1]
                if (w <= 0.0) return speeds[i]
                return speeds[i - 1] + (speeds[i] - speeds[i - 1]) * ((xc - xs[i - 1]) / w)
            }
        }
        return speeds.last()
    }

    /** Timeline per second of source span needed to reach source fraction [x]. */
    fun timeToSource(x: Double): Double {
        val xc = x.coerceIn(0.0, 1.0)
        var total = 0.0
        for (i in 1 until xs.size) {
            if (xc <= xs[i - 1]) break
            val w = xs[i] - xs[i - 1]
            if (w <= 0.0) continue
            total += segmentTime(i, w, min(xc, xs[i]) - xs[i - 1])
            if (xc <= xs[i]) break
        }
        return total
    }

    /** The clip's timeline length as a multiple of its source length. */
    val durationFactor: Double get() = timeToSource(1.0)

    /** Source fraction due after [u] of timeline per second of source span. */
    fun sourceAtTime(u: Double): Double {
        if (u <= 0.0) return 0.0
        var remaining = u
        for (i in 1 until xs.size) {
            val w = xs[i] - xs[i - 1]
            if (w <= 0.0) continue
            val segTime = segmentTime(i, w, w)
            if (remaining <= segTime) {
                return (xs[i - 1] + segmentSource(i, w, remaining)).coerceIn(xs[i - 1], xs[i])
            }
            remaining -= segTime
        }
        return 1.0
    }

    /** `∫ dx / (v₀ + slope·x)` over [dx] of the segment ending at point [i]. */
    private fun segmentTime(i: Int, w: Double, dx: Double): Double {
        val v0 = speeds[i - 1]
        val v1 = speeds[i]
        if (abs(v1 - v0) < FLAT_SPEED_DELTA) return dx / v0
        val slope = (v1 - v0) / w
        return ln((v0 + slope * dx) / v0) / slope
    }

    /** The inverse of [segmentTime]: source travelled in [t] of timeline. */
    private fun segmentSource(i: Int, w: Double, t: Double): Double {
        val v0 = speeds[i - 1]
        val v1 = speeds[i]
        if (abs(v1 - v0) < FLAT_SPEED_DELTA) return t * v0
        val slope = (v1 - v0) / w
        return v0 * (exp(slope * t) - 1.0) / slope
    }

    companion object {
        const val MIN_SPEED = 0.1
        const val MAX_SPEED = 10.0

        /** Same threshold as Dart's `_kFlatSpeedDelta`. */
        private const val FLAT_SPEED_DELTA = 1e-9

        /**
         * The wire's `{points: [{x, speed}, …]}` into a curve, cleaned the way
         * Dart's `SpeedCurve.fromJson` cleans it: unreadable points dropped,
         * `x` clamped to 0..1 and speeds to the range, sorted, held flat out
         * to both ends. Null for anything that is not a curve — absent, junk,
         * fewer than two points — never a throw.
         */
        fun parse(raw: Any?): SpeedCurve? {
            val map = raw as? Map<*, *> ?: return null
            val list = map["points"] as? List<*> ?: return null
            val pts = ArrayList<Pair<Double, Double>>()
            for (e in list) {
                val m = e as? Map<*, *> ?: continue
                val x = (m["x"] as? Number)?.toDouble() ?: continue
                val v = (m["speed"] as? Number)?.toDouble() ?: continue
                if (!x.isFinite() || !v.isFinite()) continue
                pts.add(x.coerceIn(0.0, 1.0) to v.coerceIn(MIN_SPEED, MAX_SPEED))
            }
            if (pts.size < 2) return null
            pts.sortBy { it.first }
            if (pts.first().first > 0.0) pts.add(0, 0.0 to pts.first().second)
            if (pts.last().first < 1.0) pts.add(1.0 to pts.last().second)
            return SpeedCurve(pts.map { it.first }, pts.map { it.second })
        }
    }
}
