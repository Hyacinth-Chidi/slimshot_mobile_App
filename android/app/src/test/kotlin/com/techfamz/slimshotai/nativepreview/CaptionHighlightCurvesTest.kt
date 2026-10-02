package com.techfamz.slimshotai.nativepreview

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Kotlin port of `caption_highlight_catalog.dart`, held to the shared
 * fixture `tool/generate_caption_highlight_fixture.dart` writes. A drifted
 * port is a file whose highlight differs from the canvas's with nothing on
 * screen explaining it.
 */
class CaptionHighlightCurvesTest {

    private val tolerance = 1e-5

    private fun fixture(): JsonValue.JsonObject {
        val stream = javaClass.getResourceAsStream("/caption_highlight_fixture.json")
            ?: error(
                "caption_highlight_fixture.json missing from test resources. " +
                    "Run: dart run tool/generate_caption_highlight_fixture.dart",
            )
        return FixtureJson.parse(stream.bufferedReader().use { it.readText() })
    }

    private fun near(where: String, expected: Double, actual: Double) {
        // NaN must fail, and a tolerance check alone lets it through.
        if (!actual.isFinite() || abs(expected - actual) > tolerance) {
            throw AssertionError("$where: expected $expected but was $actual")
        }
    }

    @Test
    fun `highlight samples match the shared fixture`() {
        val root = fixture()
        val sets = root.array("sets").map { set ->
            set.double("span") to set.array("words").map {
                CaptionHighlightCurves.WordSpan(it.double("start"), it.double("end"))
            }
        }
        val samples = root.array("samples")
        assertTrue("fixture has no samples", samples.isNotEmpty())

        for (row in samples) {
            val style = row.string("style")
            val (span, words) = sets[row.int("set")]
            val t = row.double("t")
            val i = row.int("i")
            val where = "$style set=${row.int("set")} t=$t i=$i"

            val s = CaptionHighlightCurves.stateAt(style, t, words, i, span)
            assertEquals("$where highlighted", row.bool("highlighted"), s.highlighted)
            near("$where fill", row.double("fill"), s.fill)
            near("$where scale", row.double("scale"), s.scale)
            near("$where opacity", row.double("opacity"), s.opacity)
            near("$where pill", row.double("pill"), s.pill)
        }
    }

    @Test
    fun `an unknown style rests`() {
        val s = CaptionHighlightCurves.stateAt(
            "sparkle",
            0.2,
            listOf(CaptionHighlightCurves.WordSpan(0.1, 0.4)),
            0,
            1.0,
        )
        assertEquals(CaptionHighlightCurves.RESTING, s)
    }
}
