package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.TransitionShaders
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Layered transitions: each clip drawn once into a layer, the transition
 * reading only the two layers. What a shader *looks* like is a device fact;
 * these pin the structure the renderer relies on.
 */
class TransitionShadersLayeredTest {

    private val shipped = listOf(
        "dissolve", "fadeToBlack", "fadeToWhite", "slide", "push", "wipe",
        "smoothLeft", "smoothRight", "smoothUp", "smoothDown", "zoomIn",
    )

    @Test
    fun `Zoom Blur is drawn and drawn from layers`() {
        assertTrue(TransitionShaders.isSupported("zoomBlur"))
        assertTrue(TransitionShaders.isLayered("zoomBlur"))
    }

    @Test
    fun `the shipped transitions keep their own path`() {
        for (type in shipped) assertFalse(type, TransitionShaders.isLayered(type))
        assertFalse(TransitionShaders.isLayered(null))
        assertFalse(TransitionShaders.isLayered("circleOpen"))
    }

    @Test
    fun `a layered transition reads the two layers through the library's own API`() {
        val source = TransitionShaders.layeredFragmentFor("zoomBlur", light = false)
        assertTrue(source.contains("uniform sampler2D uFrom;"))
        assertTrue(source.contains("uniform sampler2D uTo;"))
        assertTrue(source.contains("vec4 getFromColor(vec2 uv)"))
        assertTrue(source.contains("vec4 getToColor(vec2 uv)"))
        // No external-texture sampling: the clips are already layers.
        assertFalse(source.contains("samplerExternalOES"))
    }

    @Test
    fun `the result is laid over the background, which stays where it is`() {
        val source = TransitionShaders.layeredFragmentFor("zoomBlur", light = false)
        assertTrue(source.contains("vec4 c = transition(vTexCoord);"))
        assertTrue(source.contains("outputColor(vec4(c.rgb + backgroundAt().rgb * (1.0 - c.a), 1.0));"))
    }

    @Test
    fun `the light Zoom Blur differs from the full one only in its step count`() {
        val full = TransitionShaders.layeredFragmentFor("zoomBlur", light = false)
        val light = TransitionShaders.layeredFragmentFor("zoomBlur", light = true)
        assertTrue(full.contains("const int STEPS = 40;"))
        assertTrue(light.contains("const int STEPS = 12;"))
        assertEquals(full, light.replace("const int STEPS = 12;", "const int STEPS = 40;"))
    }

    @Test
    fun `a layer is the clip premultiplied by its coverage, with nothing behind it`() {
        for (isImage in listOf(false, true)) {
            val source = TransitionShaders.layerFragment(isImage)
            assertTrue(source.contains("gl_FragColor = vec4(0.0);"))
            assertTrue(source.contains("gl_FragColor = vec4(graded.rgb * cover, cover);"))
            // The background is laid under the finished transition, never
            // baked into a layer, or it would move with a clip.
            assertFalse(source.substringAfter("void main()").contains("backgroundAt()"))
        }
    }
}
