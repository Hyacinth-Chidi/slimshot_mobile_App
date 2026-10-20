package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins [EffectPassCosts] to the Dart catalog's `passCount`, through the
 * fixture the Dart `effect_stack_fixture_test` writes. Both sides spend a
 * frame's pass budget by these numbers, so a stacked bar is drawn by the
 * same rule on the canvas and in the file.
 */
class EffectPassCostsTest {
    private fun fixtureCosts(): Map<String, Int> {
        val source = javaClass.classLoader!!
            .getResourceAsStream("effect_stack_fixture.json")!!
            .bufferedReader()
            .use { it.readText() }
        val costs = FixtureJson.parse(source).fields["passCosts"] as JsonValue.JsonObject
        return costs.fields.mapValues { (it.value as JsonValue.JsonNumber).value.toInt() }
    }

    @Test
    fun `every effect costs what the catalog says`() {
        val costs = fixtureCosts()
        assertEquals(39, costs.size)
        for ((id, cost) in costs) {
            assertEquals(id, cost, EffectPassCosts.costOf(id))
        }
    }

    @Test
    fun `an effect it does not know costs nothing`() {
        assertEquals(0, EffectPassCosts.costOf("nope"))
        assertEquals(0, EffectPassCosts.costOf(null))
        assertEquals(0, EffectPassCosts.costOf(""))
    }
}
