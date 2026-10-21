package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.EffectPass
import com.techfamz.slimshotai.nativepreview.gl.RenderTarget
import com.techfamz.slimshotai.nativepreview.gl.effects.EffectPassSink
import com.techfamz.slimshotai.nativepreview.gl.effects.EffectStackController
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The stack controller builds every pass a timeline needs when its bars
 * arrive, so the render path only ever chooses among built passes — a
 * program linked mid-playback is a visible hitch at a bar's edge.
 */
class EffectStackControllerTest {

    private class FakePass(override val id: String) : EffectPass {
        var intensity = -1.0
        var progress = -1.0
        override fun render(
            sourceTextureId: Int,
            target: RenderTarget?,
            viewportWidth: Int,
            viewportHeight: Int,
            passIndex: Int,
        ) = Unit
    }

    private class FakeSink : EffectPassSink {
        val handed = mutableListOf<List<EffectPass>>()
        /** The intensities each pass held at the moment it was handed over. */
        val intensitiesWhenHanded = mutableListOf<List<Double>>()
        var redraws = 0
        override fun setEffectPasses(passes: List<EffectPass>) {
            handed += passes
            intensitiesWhenHanded += passes.map { (it as FakePass).intensity }
        }
        override fun <T> callOnGlThread(block: () -> T): T = block()
        override fun redrawEffects() {
            redraws++
        }
    }

    private val builds = mutableListOf<String>()
    private val released = mutableListOf<EffectPass>()
    private val sink = FakeSink()
    private val controller = EffectStackController(
        sink = sink,
        build = { id -> builds += id; listOf(FakePass(id)) },
        release = { passes -> released += passes },
        setIntensity = { passes, v -> passes.forEach { (it as FakePass).intensity = v } },
        setProgress = { passes, v -> passes.forEach { (it as FakePass).progress = v } },
    )

    private fun bar(id: String, effect: String, start: Double, end: Double, lane: Int = 0) =
        NativeTimelineEffect(
            id = id,
            effectId = effect,
            start = start,
            end = end,
            lane = lane,
            intensity = AnimatableDouble.fromWire(0.5),
            introSeconds = null,
        )

    private fun at(bars: List<NativeTimelineEffect>, t: Double) = EffectStack.drawnAt(bars, t)

    /**
     * The export's controller is a second one on the preview's renderer, which
     * may still hold the preview's passes — a bar under the paused playhead.
     * A fresh controller does not know what the renderer holds, so its first
     * frame must say, even with nothing to draw; otherwise every exported
     * frame before the first bar is drawn with the preview's effect.
     */
    @Test
    fun `a fresh controller's first apply hands its passes over even when there are none`() {
        controller.setBars(listOf(bar("a", "blur", 3.0, 8.0)))
        controller.apply(emptyList())
        assertEquals(listOf(emptyList<EffectPass>()), sink.handed)
        controller.apply(emptyList())
        assertEquals("only the first frame needs to say it", 1, sink.handed.size)
    }

    @Test
    fun `two hundred bars of one effect that never meet build it once`() {
        val bars = (0 until 200).map { bar("b$it", "blur", it * 2.0, it * 2.0 + 1.0) }
        controller.setBars(bars)
        assertEquals(listOf("blur"), builds)
    }

    @Test
    fun `two bars of one effect at once build it twice`() {
        controller.setBars(listOf(bar("a", "vignette", 0.0, 5.0), bar("b", "vignette", 1.0, 6.0, lane = 1)))
        assertEquals(listOf("vignette", "vignette"), builds)
    }

    @Test
    fun `playing a whole timeline through never builds anything`() {
        val bars = listOf(
            bar("a", "vignette", 0.0, 2.0),
            bar("b", "grain", 1.0, 3.0, lane = 1),
            bar("c", "vignette", 4.0, 6.0),
        )
        controller.setBars(bars)
        val built = builds.size
        var t = 0.0
        while (t < 7.0) {
            controller.apply(at(bars, t))
            t += 1.0 / 30.0
        }
        assertEquals(built, builds.size)
    }

    @Test
    fun `the same bars at the same values hand nothing over again`() {
        val bars = listOf(bar("a", "vignette", 0.0, 5.0))
        controller.setBars(bars)
        controller.apply(at(bars, 1.0))
        controller.apply(at(bars, 1.0))
        assertEquals(1, sink.handed.size)
    }

    @Test
    fun `a moving clock redraws without handing the passes over again`() {
        val bars = listOf(bar("a", "vignette", 0.0, 5.0))
        controller.setBars(bars)
        controller.apply(at(bars, 1.0))
        val redraws = sink.redraws
        controller.apply(at(bars, 2.0))
        assertEquals(1, sink.handed.size)
        assertEquals(redraws + 1, sink.redraws)
    }

    @Test
    fun `a pass holds its bar's strength before it is handed over`() {
        val bars = listOf(bar("a", "vignette", 0.0, 5.0))
        controller.setBars(bars)
        controller.apply(at(bars, 1.0))
        assertEquals(listOf(0.5), sink.intensitiesWhenHanded.last())
        val pass = sink.handed.last().single() as FakePass
        assertEquals(0.2, pass.progress, 1e-9)
    }

    @Test
    fun `leaving every bar hands over an empty list`() {
        val bars = listOf(bar("a", "vignette", 0.0, 5.0))
        controller.setBars(bars)
        controller.apply(at(bars, 1.0))
        controller.apply(at(bars, 9.0))
        assertTrue(sink.handed.last().isEmpty())
    }

    @Test
    fun `a bar that goes releases what nothing needs any more`() {
        controller.setBars(listOf(bar("a", "vignette", 0.0, 5.0), bar("b", "grain", 0.0, 5.0, lane = 1)))
        controller.setBars(listOf(bar("a", "vignette", 0.0, 5.0)))
        assertEquals(listOf("grain"), released.map { it.id })
    }

    @Test
    fun `a released pass is taken off the renderer first`() {
        val bars = listOf(bar("b", "grain", 0.0, 5.0))
        controller.setBars(bars)
        controller.apply(at(bars, 1.0))
        controller.setBars(emptyList())
        assertTrue(sink.handed.last().isEmpty())
    }

    @Test
    fun `reassert hands the current passes over again`() {
        val bars = listOf(bar("a", "vignette", 0.0, 5.0))
        controller.setBars(bars)
        controller.apply(at(bars, 1.0))
        controller.reassert()
        assertEquals(2, sink.handed.size)
        assertEquals(sink.handed[0], sink.handed[1])
    }
}
