package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins [EffectStack] to the Dart `effectBarsDrawnAt`: every case of
 * `effect_stack_fixture.json` — bars as the composer sends them, and what
 * Dart draws at a few instants — must be drawn the same here. The usual
 * caveat holds: the fixture catches divergence tomorrow, not a wrong rule
 * today.
 */
class EffectStackTest {
    private fun fixture(): JsonValue.JsonObject {
        val source = javaClass.classLoader!!
            .getResourceAsStream("effect_stack_fixture.json")!!
            .bufferedReader()
            .use { it.readText() }
        return FixtureJson.parse(source)
    }

    @Test
    fun `every fixture case draws the bars Dart draws`() {
        val cases = fixture().array("cases")
        assertEquals(10, cases.size)
        var checked = 0
        for (case in cases) {
            val name = case.string("name")
            val bars = (case.fields["bars"] as JsonValue.JsonArray).items.mapNotNull {
                NativeTimelineEffect.fromMap(it.toPlainMap())
            }
            for (sample in case.array("samples")) {
                val seconds = sample.double("seconds")
                val expected = sample.array("drawn")
                val drawn = EffectStack.drawnAt(bars, seconds)
                assertEquals("$name @ $seconds: ids", expected.map { it.string("id") }, drawn.map { it.bar.id })
                for ((want, got) in expected.zip(drawn)) {
                    assertEquals("$name @ $seconds: intensity", want.double("intensity"), got.intensity, 1e-6)
                    assertEquals("$name @ $seconds: progress", want.double("progress"), got.progress, 1e-6)
                    assertEquals("$name @ $seconds: barSeconds", want.double("barSeconds"), got.barSeconds, 1e-6)
                    checked++
                }
            }
        }
        assertEquals(true, checked > 15)
    }

    private fun bar(id: String, effect: String, start: Double, end: Double, lane: Int = 0) =
        NativeTimelineEffect(
            id = id,
            effectId = effect,
            start = start,
            end = end,
            lane = lane,
            intensity = AnimatableDouble.fromWire(0.7),
            introSeconds = null,
        )

    @Test
    fun `bars that never meet share one instance of their effect`() {
        val bars = (0 until 200).map { bar("b$it", "blur", it * 2.0, it * 2.0 + 1.0) }
        assertEquals(mapOf("blur" to 1), EffectStack.peakInstances(bars))
    }

    @Test
    fun `two bars of one effect at once need two instances`() {
        val bars = listOf(bar("a", "vignette", 0.0, 5.0), bar("b", "vignette", 2.0, 6.0, lane = 1))
        assertEquals(mapOf("vignette" to 2), EffectStack.peakInstances(bars))
    }

    @Test
    fun `a bar the budget skips is not counted`() {
        val bars = listOf(bar("g", "glow", 0.0, 5.0), bar("v", "vignette", 0.0, 5.0, lane = 1))
        assertEquals(mapOf("glow" to 1), EffectStack.peakInstances(bars))
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

private fun JsonValue.toPlainMap(): Map<*, *> = toPlain() as Map<*, *>
