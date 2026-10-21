package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.effects.EffectPreviewAnswer
import com.techfamz.slimshotai.nativepreview.gl.effects.EffectPreviewCanvas
import com.techfamz.slimshotai.nativepreview.gl.effects.EffectPreviewJob
import com.techfamz.slimshotai.nativepreview.gl.effects.EffectPreviewSpec
import com.techfamz.slimshotai.nativepreview.gl.effects.PreviewHost
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The effect preview job runs on the GL thread the live canvas shares, a few
 * cells at a time, and must answer **exactly once** on every path — a lost
 * answer would leave the Dart side waiting — while never touching GL after the
 * renderer is released and always freeing what it built while it still can.
 */
class EffectPreviewJobTest {

    private class FakeCanvas : EffectPreviewCanvas {
        val calls = mutableListOf<String>()
        var makeCurrentResult = true
        var setUpResult = true
        var throwAtCell: Int? = null

        override fun makeCurrent(): Boolean {
            calls += "current"
            return makeCurrentResult
        }

        override fun setUp(): Boolean {
            calls += "setUp"
            return setUpResult
        }

        override fun drawCell(index: Int, seconds: Double?) {
            calls += "cell $index"
            if (index == throwAtCell) throw IllegalStateException("cell")
        }

        override fun readBack(): ByteBuffer {
            calls += "readBack"
            return ByteBuffer.allocate(4)
        }

        override fun tearDown() {
            calls += "tearDown"
        }
    }

    private val spec = EffectPreviewSpec(160, 144, 5, 25, 15)
    private val canvas = FakeCanvas()
    private val queue = ArrayDeque<Runnable>()
    private var acceptPosts = true
    private var host = PreviewHost.READY
    private var encoded: ByteArray? = byteArrayOf(1, 2, 3)
    private val answers = mutableListOf<EffectPreviewAnswer>()

    private val job = EffectPreviewJob(
        spec = spec,
        canvas = canvas,
        host = { host },
        post = { runnable -> if (acceptPosts) queue.addLast(runnable); acceptPosts },
        encode = { _, done -> done(encoded) },
        onDone = { answers += it },
    )

    private fun runNext() = queue.removeFirst().run()

    private fun runAll() {
        while (queue.isNotEmpty()) runNext()
    }

    private fun cellsDrawn() = canvas.calls.filter { it.startsWith("cell ") }

    @Test
    fun `a normal run draws every cell once, reads back once, tears down once, answers an atlas`() {
        job.start()
        runAll()
        assertEquals((0 until 25).map { "cell $it" }, cellsDrawn())
        assertEquals(1, canvas.calls.count { it == "readBack" })
        assertEquals(1, canvas.calls.count { it == "tearDown" })
        assertEquals(1, answers.size)
        assertTrue((answers.single() as EffectPreviewAnswer.Atlas).jpeg.contentEquals(byteArrayOf(1, 2, 3)))
        assertTrue(job.isDone)
    }

    @Test
    fun `no slice draws more than 4 cells`() {
        job.start()
        while (queue.isNotEmpty()) {
            val before = cellsDrawn().size
            runNext()
            assertTrue(cellsDrawn().size - before <= 4)
        }
    }

    @Test
    fun `every slice makes the context current before drawing`() {
        job.start()
        while (queue.isNotEmpty()) {
            val before = canvas.calls.size
            runNext()
            assertEquals("current", canvas.calls[before])
        }
    }

    @Test
    fun `setUp refused - torn down, Failed`() {
        canvas.setUpResult = false
        job.start()
        runAll()
        assertTrue(cellsDrawn().isEmpty())
        assertEquals(1, canvas.calls.count { it == "tearDown" })
        assertEquals(listOf<EffectPreviewAnswer>(EffectPreviewAnswer.Failed), answers)
    }

    @Test
    fun `a cell that throws - torn down, Failed, no read-back`() {
        canvas.throwAtCell = 9
        job.start()
        runAll()
        assertFalse(canvas.calls.contains("cell 10"))
        assertFalse(canvas.calls.contains("readBack"))
        assertEquals(1, canvas.calls.count { it == "tearDown" })
        assertEquals(listOf<EffectPreviewAnswer>(EffectPreviewAnswer.Failed), answers)
    }

    @Test
    fun `encode giving null - Failed`() {
        encoded = null
        job.start()
        runAll()
        assertEquals(listOf<EffectPreviewAnswer>(EffectPreviewAnswer.Failed), answers)
    }

    @Test
    fun `exporting at a slice - torn down, Busy`() {
        job.start()
        runNext()
        host = PreviewHost.EXPORTING
        runAll()
        assertEquals(4, cellsDrawn().size)
        assertEquals(1, canvas.calls.count { it == "tearDown" })
        assertEquals(listOf<EffectPreviewAnswer>(EffectPreviewAnswer.Busy), answers)
    }

    @Test
    fun `released at a slice - Busy, and that slice makes no canvas call`() {
        job.start()
        runNext()
        val before = canvas.calls.size
        host = PreviewHost.RELEASED
        runAll()
        assertEquals(before, canvas.calls.size)
        assertEquals(listOf<EffectPreviewAnswer>(EffectPreviewAnswer.Busy), answers)
    }

    @Test
    fun `makeCurrent refused - Busy, no tearDown`() {
        job.start()
        runNext()
        canvas.makeCurrentResult = false
        runAll()
        assertFalse(canvas.calls.contains("tearDown"))
        assertEquals(listOf<EffectPreviewAnswer>(EffectPreviewAnswer.Busy), answers)
    }

    @Test
    fun `a refused post mid-job - torn down, Busy`() {
        job.start()
        acceptPosts = false
        runNext()
        assertEquals(1, canvas.calls.count { it == "tearDown" })
        assertEquals(listOf<EffectPreviewAnswer>(EffectPreviewAnswer.Busy), answers)
    }

    @Test
    fun `a refused first post - Busy, no canvas call`() {
        acceptPosts = false
        job.start()
        assertTrue(canvas.calls.isEmpty())
        assertEquals(listOf<EffectPreviewAnswer>(EffectPreviewAnswer.Busy), answers)
    }

    @Test
    fun `abandon mid-job answers busy and touches nothing`() {
        job.start()
        runNext()
        val before = canvas.calls.size
        job.abandon()
        runAll()
        assertEquals(before, canvas.calls.size)
        assertEquals(listOf<EffectPreviewAnswer>(EffectPreviewAnswer.Busy), answers)
    }

    @Test
    fun `abandon after the atlas changes nothing`() {
        job.start()
        runAll()
        job.abandon()
        assertEquals(1, answers.size)
        assertTrue(answers.single() is EffectPreviewAnswer.Atlas)
    }

    @Test
    fun `the frames are drawn at their own times`() {
        val seconds = mutableListOf<Double?>()
        val timing = object : EffectPreviewCanvas by canvas {
            override fun drawCell(index: Int, seconds2: Double?) {
                seconds += seconds2
            }
        }
        val timed = EffectPreviewJob(spec, timing, { host }, { queue.addLast(it); true },
            { _, done -> done(byteArrayOf(1)) }, { answers += it })
        timed.start()
        runAll()
        assertEquals((0 until 25).map { spec.frameSeconds(it) }, seconds)
    }
}
