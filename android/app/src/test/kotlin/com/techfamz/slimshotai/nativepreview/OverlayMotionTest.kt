package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * An overlay's placement — centre, scale, rotation, opacity — resolved per
 * frame from its keyframes, the same way in the preview and the export.
 *
 * The wire carries each as a **bare number** while nothing is keyframed (the
 * payload every build has read) and as a keyframe map once something is;
 * [AnimatableDouble.fromWire] reads either.
 */
class OverlayMotionTest {

    private val eps = 1e-12

    private fun overlay(vararg extra: Pair<String, Any?>): NativeTimelineOverlay =
        NativeTimelineOverlay.fromMap(
            mapOf(
                "id" to "o",
                "kind" to "image",
                "path" to "/p.png",
                "startSeconds" to 2.0,
                "endSeconds" to 6.0,
            ) + extra,
        )!!

    private fun track(vararg points: Pair<Double, Double>, base: Double = 0.0): Map<String, Any?> =
        mapOf(
            "baseValue" to base,
            "keyframes" to points.map { (p, v) ->
                mapOf("progress" to p, "value" to v, "interpolation" to "linear")
            },
        )

    @Test
    fun `a numeric wire map resolves exactly as it always did`() {
        val o = overlay(
            "centerX" to 0.3,
            "centerY" to 0.7,
            "scale" to 1.5,
            "rotation" to 0.25,
            "opacity" to 0.8,
        )
        assertFalse(o.hasKeyframes)
        for (t in listOf(2.0, 3.3, 5.99)) {
            val s = o.stateAt(t)
            assertEquals(0.3, s.centerX, 0.0)
            assertEquals(0.7, s.centerY, 0.0)
            assertEquals(1.5, s.scale, 0.0)
            assertEquals(0.25, s.rotation, 0.0)
            assertEquals(0.8, s.opacity, 0.0)
            assertEquals(0.0, s.offsetX, 0.0)
        }
    }

    @Test
    fun `absent values take the old defaults`() {
        val s = overlay().restingStateAt(4.0)
        assertEquals(0.5, s.centerX, 0.0)
        assertEquals(0.5, s.centerY, 0.0)
        assertEquals(1.0, s.scale, 0.0)
        assertEquals(0.0, s.rotation, 0.0)
        assertEquals(1.0, s.opacity, 0.0)
    }

    @Test
    fun `a keyframed centre resolves at the overlay's own progress`() {
        val o = overlay("centerX" to track(0.0 to 0.2, 1.0 to 0.6))
        assertTrue(o.hasKeyframes)
        // 3s of a 2s–6s span is progress 0.25.
        assertEquals(0.3, o.restingStateAt(3.0).centerX, eps)
        assertEquals(0.4, o.stateAt(4.0).centerX, eps)
        assertEquals(0.25, o.progressAt(3.0), eps)
    }

    @Test
    fun `a preset fade multiplies a keyframed opacity`() {
        val o = overlay(
            "opacity" to track(0.0 to 0.5, 1.0 to 0.5),
            "animationIn" to "fade_in",
            "animationInSeconds" to 1.0,
        )
        // Half-way through the fade, on a keyframed 0.5.
        assertEquals(0.25, o.stateAt(2.5).opacity, eps)
        assertEquals(0.5, o.restingStateAt(2.5).opacity, eps)
    }

    @Test
    fun `a preset slide adds to a keyframed centre`() {
        val o = overlay(
            "centerX" to track(0.0 to 0.2, 1.0 to 0.6),
            "animationIn" to "slide_left",
            "animationInSeconds" to 1.0,
            "slideOffsetX" to 0.5,
        )
        val s = o.stateAt(2.0)
        // The keyframed centre at the start, and the slide's full travel.
        assertEquals(0.2, s.centerX, eps)
        assertEquals(0.5, s.offsetX, eps)
        // At rest, no slide at all.
        assertEquals(0.0, o.restingStateAt(2.0).offsetX, 0.0)
    }

    @Test
    fun `rotation and scale resolve from their tracks`() {
        val o = overlay(
            "rotation" to track(0.0 to 0.0, 1.0 to 1.0),
            "scale" to track(0.0 to 1.0, 1.0 to 3.0),
            "animationIn" to "zoom_in",
            "animationInSeconds" to 1.0,
        )
        assertEquals(0.5, o.stateAt(4.0).rotation, eps)
        assertEquals(2.0, o.stateAt(4.0).scale, eps)
        // The preset zoom multiplies the keyframed scale: 1.25 x 0.5.
        assertEquals(0.625, o.stateAt(2.5).scale, eps)
    }

    @Test
    fun `the clamps apply to the resolved values`() {
        // A keyframe can carry anything a hand-edited draft holds.
        val o = overlay(
            "opacity" to track(0.0 to 1.5, 1.0 to -1.0),
            "scale" to track(0.0 to -2.0, 1.0 to -2.0),
        )
        assertEquals(1.0, o.restingStateAt(2.0).opacity, 0.0)
        assertEquals(0.0, o.restingStateAt(6.0).opacity, 0.0)
        assertEquals(0.0, o.stateAt(4.0).scale, 0.0)
    }

    @Test
    fun `a span of zero is progress 0, never a division by zero`() {
        val o = overlay().copy(endSeconds = 2.0)
        assertEquals(0.0, o.progressAt(2.0), 0.0)
        assertEquals(0.0, o.copy(endSeconds = 1.0).progressAt(5.0), 0.0)
    }

    @Test
    fun `resolves exactly where the editor does`() {
        val stream = javaClass.getResourceAsStream("/overlay_motion_fixture.json")
            ?: error(
                "overlay_motion_fixture.json missing from test resources. " +
                    "Run: UPDATE_OVERLAY_FIXTURE=1 flutter test " +
                    "test/features/video_editor/logic/timeline/overlay_motion_fixture_test.dart",
            )
        val fixture = FixtureJson.parse(stream.bufferedReader().use { it.readText() })
        val entries = fixture.array("overlays")
        assertEquals("the fixture holds three overlays", 3, entries.size)

        var checked = 0
        for (entry in entries) {
            @Suppress("UNCHECKED_CAST")
            val wire = entry.fields.getValue("wire").toPlain() as Map<String, Any?>
            val o = NativeTimelineOverlay.fromMap(wire)
                ?: error("the fixture's ${wire["id"]} did not parse")
            assertTrue("${o.id} is keyframed", o.hasKeyframes)
            for (sample in entry.array("samples")) {
                val p = sample.double("progress")
                val t = o.startSeconds + p * (o.endSeconds - o.startSeconds)
                val s = o.restingStateAt(t)
                val at = "${o.id} at $p"
                assertEquals("centerX $at", sample.double("centerX"), s.centerX, 1e-9)
                assertEquals("centerY $at", sample.double("centerY"), s.centerY, 1e-9)
                assertEquals("scale $at", sample.double("scale"), s.scale, 1e-9)
                assertEquals("rotation $at", sample.double("rotation"), s.rotation, 1e-9)
                assertEquals("opacity $at", sample.double("opacity"), s.opacity, 1e-9)
                checked++
            }
        }
        assertEquals(21, checked)
    }
}

/** The fixture's parsed tree as the plain maps, lists and numbers `fromMap` reads. */
private fun JsonValue.toPlain(): Any? = when (this) {
    is JsonValue.JsonObject -> fields.mapValues { it.value.toPlain() }
    is JsonValue.JsonArray -> items.map { it.toPlain() }
    is JsonValue.JsonNumber -> value
    is JsonValue.JsonString -> value
    is JsonValue.JsonBool -> value
    JsonValue.JsonNull -> null
}
