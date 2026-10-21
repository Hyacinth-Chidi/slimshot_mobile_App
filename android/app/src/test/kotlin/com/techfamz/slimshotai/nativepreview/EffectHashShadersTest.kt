package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.effects.EffectShaderLib
import com.techfamz.slimshotai.nativepreview.gl.effects.GlitchPass
import com.techfamz.slimshotai.nativepreview.gl.effects.GrainPass
import com.techfamz.slimshotai.nativepreview.gl.effects.GridPass
import com.techfamz.slimshotai.nativepreview.gl.effects.HandheldPass
import com.techfamz.slimshotai.nativepreview.gl.effects.SteadyInPass
import com.techfamz.slimshotai.nativepreview.gl.effects.SuperShakePass
import com.techfamz.slimshotai.nativepreview.gl.effects.VhsPass
import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The effects' shared hash, `fract(sin(x) * 43758.5)`, returns almost nothing
 * at `mediump` on a GPU that takes it literally (the Infinix's PowerVR does):
 * a 16-bit float near 43758 is stored to the nearest 32, so the fraction is
 * gone. Glitch never tore, the shakes sat still, grain was a flat darkening.
 * Shaders run only on a device, so what a JVM test can hold is the text: the
 * hash asks for high precision where the GPU has it, and the three effects
 * rebuilt on CPU-planned uniforms no longer hash at all. Every shader touched
 * is written out for `glslangValidator -S frag`.
 */
class EffectHashShadersTest {

    @Test
    fun `the shared hash is computed in high precision where the GPU has it`() {
        val common = EffectShaderLib.COMMON
        val hash = common.substring(common.indexOf("float hash11"))
        assertTrue(common.contains("#ifdef GL_FRAGMENT_PRECISION_HIGH"))
        assertTrue(hash.contains("highp"))
    }

    @Test
    fun `glitch and the two shakes take their plan as uniforms and hash nothing`() {
        for ((name, source) in listOf(
            "glitch" to GlitchPass.FRAGMENT,
            "handheld" to HandheldPass.FRAGMENT,
            "super_shake" to SuperShakePass.FRAGMENT,
        )) {
            assertFalse(name, source.contains("hash11(") || source.contains("hash21("))
            assertFalse("$name reads a per-clip clock", source.contains("uProgress"))
        }
        assertTrue(GlitchPass.FRAGMENT.contains("uniform vec4 uBlock3;"))
        assertTrue(GlitchPass.FRAGMENT.contains("uniform vec4 uGlitch;"))
        assertTrue(HandheldPass.FRAGMENT.contains("uniform vec4 uPose;"))
        assertTrue(SuperShakePass.FRAGMENT.contains("uniform vec4 uPosePrev;"))
    }

    @Test
    fun `every shader touched is written out for glslang`() {
        val dir = File(System.getProperty("java.io.tmpdir"), "slimshot-shader-dump").apply { mkdirs() }
        val shaders = mapOf(
            "glitch" to GlitchPass.FRAGMENT,
            "handheld" to HandheldPass.FRAGMENT,
            "super_shake" to SuperShakePass.FRAGMENT,
            "grain" to GrainPass.FRAGMENT,
            "vhs" to VhsPass.FRAGMENT,
            "steady_in" to SteadyInPass.FRAGMENT,
            "grid" to GridPass.fragmentFor(GridPass.CELLS),
        )
        for ((name, source) in shaders) {
            File(dir, "$name.frag").writeText("#version 100\n$source")
        }
        assertTrue(shaders.keys.all { File(dir, "$it.frag").exists() })
    }
}
