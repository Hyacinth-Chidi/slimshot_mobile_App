package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.TransitionShaders
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The engine draws exactly the transitions the Dart catalog offers.
 *
 * Twin of `transition_names_fixture_test.dart`: both read
 * `transition_names.json`, so a transition added on one side only fails a
 * test instead of shipping as a hard cut.
 */
class TransitionNamesFixtureTest {

    private fun fixtureNames(): Set<String> {
        val source = javaClass.classLoader!!
            .getResourceAsStream("transition_names.json")!!
            .bufferedReader()
            .use { it.readText() }
        val root = FixtureJson.parse(source)
        val list = root.fields["transitions"] as JsonValue.JsonArray
        return list.items.map { (it as JsonValue.JsonString).value }.toSet()
    }

    @Test
    fun `the shader registry draws every transition the catalog offers`() {
        assertEquals(fixtureNames(), TransitionShaders.supportedTypes)
    }
}
