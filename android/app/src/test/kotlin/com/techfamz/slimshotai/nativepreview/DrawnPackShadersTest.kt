package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.effects.DrawnPack
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The drawn pack — thunder, rain, snow, embers, light rays, lens flare,
 * sparkle, neon — is GLSL compiled at runtime, so a mistake is a black frame on
 * a device, never a build error. What a JVM test can hold, it holds here: each
 * shader keeps time in real seconds (rain must not fall slower on a longer
 * bar), scales by its intensity (0 must be the untouched picture), asks for
 * high precision where the GPU has it (a clock in seconds outgrows `mediump`
 * within a minute), and never uses the sin-fract hash that overflows `mediump`.
 *
 * Each source is also written to `<java.io.tmpdir>/slimshot-shader-dump/` as a `#version 100`
 * fragment, so `glslangValidator -S frag` can compile-check every one of them
 * off the device — the step the transitions shipped behind.
 */
class DrawnPackShadersTest {

    private val ids = listOf(
        "thunder", "rain", "snow", "embers",
        "light_rays", "lens_flare", "sparkle", "neon_edge",
    )

    @Test
    fun `the pack is the eight effects the catalog offers`() {
        assertEquals(ids, DrawnPack.IDS)
    }

    @Test
    fun `every effect in the pack costs one pass`() {
        for (id in ids) assertEquals(id, 1, EffectPassCosts.costOf(id))
    }

    @Test
    fun `every shader keeps time in seconds and scales by its intensity`() {
        for (id in ids) {
            val source = DrawnPack.fragmentFor(id)
            assertNotNull(id, source)
            source!!
            assertTrue("$id declares uSeconds", source.contains("uniform float uSeconds;"))
            assertTrue("$id reads uSeconds", source.split("uSeconds").size - 1 >= 2)
            assertTrue("$id declares uIntensity", source.contains("uniform float uIntensity;"))
            assertTrue("$id reads uIntensity", source.split("uIntensity").size - 1 >= 2)
            assertTrue("$id writes gl_FragColor", source.contains("gl_FragColor"))
        }
    }

    @Test
    fun `every shader asks for high precision where the GPU has it`() {
        for (id in ids) {
            val source = DrawnPack.fragmentFor(id)!!
            assertTrue(id, source.contains("#ifdef GL_FRAGMENT_PRECISION_HIGH"))
            assertTrue(id, source.contains("precision highp float;"))
        }
    }

    @Test
    fun `no shader uses the hash that overflows mediump or an ES 3 call`() {
        for (id in ids) {
            val source = DrawnPack.fragmentFor(id)!!
            assertFalse("$id: sin-fract hash", source.contains("43758"))
            assertFalse("$id: texture() is ES 3", Regex("""\btexture\(""").containsMatchIn(source))
        }
    }

    @Test
    fun `an unknown id has no shader`() {
        assertEquals(null, DrawnPack.fragmentFor("from_the_future"))
    }

    @Test
    fun `every shader is written out for glslang`() {
        // The system temp folder, not the module's `build/`: Gradle redirects
        // the build dir to the root `build/`, so `android/app/build` would be
        // a stray untracked folder in the repo.
        val dir = File(System.getProperty("java.io.tmpdir"), "slimshot-shader-dump").apply { mkdirs() }
        for (id in ids) {
            File(dir, "$id.frag").writeText("#version 100\n" + DrawnPack.fragmentFor(id)!!)
        }
        assertEquals(ids.size, ids.count { File(dir, "$it.frag").exists() })
    }
}
