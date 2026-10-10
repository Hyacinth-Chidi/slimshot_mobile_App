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

    private val part2a = listOf(
        "slideScaleLeft", "slideScaleRight", "slideScaleUp", "slideScaleDown",
        "splitIn", "splitOut", "bounce", "swirl", "spinAway", "zoomInOut",
        "whipPan", "shake", "zoomBounce", "dreamyZoom", "motionBlur", "defocus",
    )

    @Test
    fun `every part-2a transition is drawn, and drawn from layers`() {
        for (type in part2a) {
            assertTrue(type, TransitionShaders.isSupported(type))
            assertTrue(type, TransitionShaders.isLayered(type))
            val source = TransitionShaders.layeredFragmentFor(type, light = false)
            assertTrue(type, Regex("""vec4 transition\(vec2 \w+\)""").containsMatchIn(source))
            // The library's uniforms became constants: a uniform nothing binds
            // reads as zero on a device, which silently breaks a port.
            assertFalse(type, Regex("""uniform (bool|float|vec2|vec4) (?!uProgress|uCanvasAspect|uBackground|uColor)""")
                .containsMatchIn(source))
        }
    }

    @Test
    fun `the four slide-and-scale directions differ only in their direction`() {
        val left = TransitionShaders.layeredFragmentFor("slideScaleLeft", light = false)
        for (type in listOf("slideScaleRight", "slideScaleUp", "slideScaleDown")) {
            val other = TransitionShaders.layeredFragmentFor(type, light = false)
            val differing = left.lines().zip(other.lines()).count { (a, b) -> a != b }
            assertEquals(type, 1, differing)
        }
    }

    @Test
    fun `only the step-heavy transitions have a light version`() {
        for (type in listOf("zoomBlur", "motionBlur", "whipPan")) {
            assertTrue(type, TransitionShaders.hasLightVersion(type))
            assertTrue(
                type,
                TransitionShaders.layeredFragmentFor(type, light = true) !=
                    TransitionShaders.layeredFragmentFor(type, light = false),
            )
        }
        for (type in part2a - setOf("motionBlur", "whipPan")) {
            assertFalse(type, TransitionShaders.hasLightVersion(type))
        }
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

    private val part2b = listOf(
        "overexposure", "filmBurn", "flash",
        "glitchMemories", "lostSignal", "tvStatic", "datamosh", "glitchDisplace", "flicker",
        "revolveLeft", "revolveRight", "cubeLeft", "cubeRight",
    )

    @Test
    fun `every part-2b transition is drawn, and drawn from layers`() {
        for (type in part2b) {
            assertTrue(type, TransitionShaders.isSupported(type))
            assertTrue(type, TransitionShaders.isLayered(type))
            val source = TransitionShaders.layeredFragmentFor(type, light = false)
            assertTrue(type, Regex("""vec4 transition\(vec2 \w+\)""").containsMatchIn(source))
            assertFalse(type, Regex("""uniform (bool|float|vec2|vec4) (?!uProgress|uCanvasAspect|uBackground|uColor)""")
                .containsMatchIn(source))
        }
    }

    @Test
    fun `no layered transition hashes with sin-fract`() {
        // fract(sin(x) * 43758.5) keeps no fraction in mediump, and the glitch
        // ports lean on their hash for every block they tear.
        for (type in TransitionShaders.supportedTypes.filter { TransitionShaders.isLayered(it) }) {
            for (light in listOf(false, true)) {
                val source = TransitionShaders.layeredFragmentFor(type, light)
                assertFalse(type, source.contains("43758"))
            }
        }
    }

    @Test
    fun `the hashing ports ask for highp where the GPU has it`() {
        for (type in listOf("filmBurn", "lostSignal", "tvStatic", "datamosh", "flicker")) {
            val source = TransitionShaders.layeredFragmentFor(type, light = false)
            assertTrue(type, source.contains("#ifdef GL_FRAGMENT_PRECISION_HIGH\nprecision highp float;\n#endif"))
            assertTrue(type, source.contains("float slimHash(vec2 p)"))
        }
    }

    @Test
    fun `the left and right revolves and cubes differ only in their direction`() {
        for ((left, right) in listOf("revolveLeft" to "revolveRight", "cubeLeft" to "cubeRight")) {
            val a = TransitionShaders.layeredFragmentFor(left, light = false).lines()
            val b = TransitionShaders.layeredFragmentFor(right, light = false).lines()
            assertEquals(left, a.size, b.size)
            assertEquals(left, 1, a.zip(b).count { (x, y) -> x != y })
        }
    }

    @Test
    fun `the part-2b light versions are the step-heavy ones`() {
        for (type in listOf("filmBurn", "revolveLeft", "revolveRight")) {
            assertTrue(type, TransitionShaders.hasLightVersion(type))
        }
        for (type in part2b - setOf("filmBurn", "revolveLeft", "revolveRight")) {
            assertFalse(type, TransitionShaders.hasLightVersion(type))
        }
    }

    // ------------------------------------------------ Film Burn's cost

    private fun varyings(source: String): Map<String, String> =
        Regex("""varying (?:highp |mediump |lowp )?(vec[234]|float) (\w+);""")
            .findAll(source).associate { it.groupValues[2] to it.groupValues[1] }

    @Test
    fun `film burn places its blotches once per vertex, not once per pixel`() {
        // Thirteen blotches, each placed by two noise lookups of sixteen hashes
        // and fourteen pows: the same answer for every pixel of a frame, so
        // the preview could not keep up while the export, which waits, could.
        val vertex = TransitionShaders.layeredVertexFor("filmBurn")
        assertTrue(vertex.contains("smoothRandom("))
        assertTrue(vertex.contains("vBurnSpots0 = "))
        val fragment = TransitionShaders.layeredFragmentFor("filmBurn", light = false)
        val perPixel = fragment.substringAfter("vec4 transition(vec2 p)")
        // Only the gentle zoom still asks for noise per pixel.
        assertEquals(1, Regex("""smoothRandom\(""").findAll(perPixel).count())
        assertTrue(perPixel.contains("vBurnSpots0.xy"))
        assertTrue(perPixel.contains("vBurnSpotLast"))
    }

    @Test
    fun `every other transition keeps the shared vertex shader`() {
        for (type in TransitionShaders.supportedTypes - "filmBurn") {
            assertEquals(type, TransitionShaders.VERTEX_SHADER, TransitionShaders.layeredVertexFor(type))
        }
    }

    @Test
    fun `film burn's two stages agree on what they share`() {
        val vertex = TransitionShaders.layeredVertexFor("filmBurn")
        val fragment = TransitionShaders.layeredFragmentFor("filmBurn", light = false)
        // A uniform in both stages must carry one precision, or the link fails;
        // the fragment header declares uProgress mediump.
        assertTrue(vertex.contains("uniform mediump float uProgress;"))
        assertEquals(varyings(vertex), varyings(fragment))
        // Seven rows of the eight every GLES2 device guarantees: six vec4 and
        // the two vec2 packed into one.
        val vec4s = varyings(vertex).values.count { it == "vec4" }
        val vec2s = varyings(vertex).values.count { it == "vec2" }
        assertEquals(7, vec4s + (vec2s + 1) / 2)
    }

    @Test
    fun `film burn's light version keeps every blotch`() {
        // Dropping blotches made them vanish the moment the speed check
        // switched mid-transition. Only the blur's tap count may differ.
        val full = TransitionShaders.layeredFragmentFor("filmBurn", light = false)
        val light = TransitionShaders.layeredFragmentFor("filmBurn", light = true)
        assertTrue(full.contains("const int STEPS = 50;"))
        assertEquals(full, light.replace("const int STEPS = 12;", "const int STEPS = 50;"))
    }
}
