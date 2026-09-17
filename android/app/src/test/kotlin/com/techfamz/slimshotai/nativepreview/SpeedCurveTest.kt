package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Holds the Kotlin [SpeedCurve] to the Dart one through the shared fixture.
 *
 * A clip's source position is resolved in Dart for the filmstrip and the
 * scrub, and in Kotlin for playback and export, so the integral that turns a
 * speed curve into source time exists twice. `speed_curve_fixture.json` is
 * sampled values from the Dart side; a port whose logarithm or inverse drifts
 * fails here rather than shipping a file whose clip lands on different frames
 * than the canvas showed.
 *
 * Regenerate with `dart run tool/generate_speed_curve_fixture.dart` after a
 * deliberate change, and re-run this.
 */
class SpeedCurveTest {

    private fun fixture(): JsonValue.JsonObject {
        val stream = javaClass.classLoader!!.getResourceAsStream("speed_curve_fixture.json")
            ?: error(
                "speed_curve_fixture.json missing from test resources. " +
                    "Run `dart run tool/generate_speed_curve_fixture.dart`.",
            )
        return FixtureJson.parse(stream.bufferedReader().use { it.readText() })
    }

    private fun assertClose(where: String, expected: Double, actual: Double) {
        assertTrue(
            "$where: expected $expected, got $actual",
            abs(expected - actual) <= 1e-6,
        )
    }

    /** The fixture's raw point list, in the wire shape the composer sends. */
    private fun rawPoints(row: JsonValue.JsonObject): List<Map<String, Double>> =
        row.array("points").map { mapOf("x" to it.double("x"), "speed" to it.double("speed")) }

    @Test
    fun `every curve in the fixture parses and its duration factor matches`() {
        val rows = fixture().array("curves")
        assertTrue("fixture has no curves", rows.isNotEmpty())
        for (row in rows) {
            val curve = SpeedCurve.parse(mapOf("points" to rawPoints(row)))
            assertNotNull("curve '${row.string("id")}' failed to parse", curve)
            assertClose(
                "durationFactor of '${row.string("id")}'",
                row.double("durationFactor"),
                curve!!.durationFactor,
            )
        }
    }

    @Test
    fun `speed and time samples match the shared fixture`() {
        for (row in fixture().array("curves")) {
            val id = row.string("id")
            val curve = SpeedCurve.parse(mapOf("points" to rawPoints(row)))!!
            for (s in row.array("samples")) {
                val x = s.double("x")
                assertClose("'$id' speedAtSource($x)", s.double("speed"), curve.speedAtSource(x))
                assertClose("'$id' timeToSource($x)", s.double("time"), curve.timeToSource(x))
            }
        }
    }

    @Test
    fun `inverse samples match the shared fixture`() {
        for (row in fixture().array("curves")) {
            val id = row.string("id")
            val curve = SpeedCurve.parse(mapOf("points" to rawPoints(row)))!!
            for (s in row.array("inverse")) {
                val u = s.double("u")
                assertClose("'$id' sourceAtTime($u)", s.double("x"), curve.sourceAtTime(u))
            }
        }
    }

    @Test
    fun `junk parses to no curve, never a crash`() {
        assertNull(SpeedCurve.parse(null))
        assertNull(SpeedCurve.parse("x"))
        assertNull(SpeedCurve.parse(mapOf("points" to emptyList<Any>())))
        assertNull(SpeedCurve.parse(mapOf("points" to listOf(mapOf("x" to 0.0, "speed" to 1.0)))))
    }

    @Test
    fun `a thin list is sorted and held flat to both ends, as Dart does`() {
        val curve = SpeedCurve.parse(
            mapOf(
                "points" to listOf(
                    mapOf("x" to 0.8, "speed" to 2.0),
                    mapOf("x" to 0.2, "speed" to 1.0),
                ),
            ),
        )!!
        assertEquals(listOf(0.0, 0.2, 0.8, 1.0), curve.xs)
        assertEquals(1.0, curve.speeds.first(), 0.0)
        assertEquals(2.0, curve.speeds.last(), 0.0)
    }

    @Test
    fun `equality is structural, so the engine's soft update can compare clips`() {
        val a = SpeedCurve.parse(mapOf("points" to listOf(mapOf("x" to 0.0, "speed" to 1.0), mapOf("x" to 1.0, "speed" to 2.0))))
        val b = SpeedCurve.parse(mapOf("points" to listOf(mapOf("x" to 0.0, "speed" to 1.0), mapOf("x" to 1.0, "speed" to 2.0))))
        assertEquals(a, b)
    }
}
