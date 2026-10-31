package com.techfamz.slimshotai.nativepreview.gl

import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which still textures the preview frees, and which texts it loads ahead.
 *
 * The preview used to keep every still it ever uploaded. Text now comes and
 * goes with the playhead — the editor sends only what is near it, an atlas per
 * look — so a texture whose path has left the list must go, or GPU memory
 * grows with every caption played and every look tried.
 */
class StillResidencyTest {

    private val glyph = mapOf(
        "atlasLeft" to 0.0, "atlasTop" to 0.0, "atlasRight" to 1.0, "atlasBottom" to 1.0,
        "boxLeft" to 0.0, "boxTop" to 0.0, "boxRight" to 1.0, "boxBottom" to 1.0,
        "srcLeft" to 0.0, "srcTop" to 0.0, "srcRight" to 1.0, "srcBottom" to 1.0,
    )

    private fun overlay(
        id: String,
        kind: String,
        path: String,
        start: Double = 0.0,
        end: Double = 10.0,
    ): NativeTimelineOverlay = NativeTimelineOverlay.fromMap(
        mapOf(
            "id" to id,
            "kind" to kind,
            "path" to path,
            "startSeconds" to start,
            "endSeconds" to end,
            "glyphs" to if (kind == "text") listOf(glyph) else null,
        ),
    )!!

    @Test
    fun `a path the new list drops is released once`() {
        val photo = overlay("p", "image", "/a.png")
        val previous = listOf(
            photo,
            overlay("text_b", "text", "/b.png"),
            overlay("text_c", "text", "/b.png"),
        )
        val released = StillResidency.released(previous, listOf(photo))
        assertEquals(listOf("/b.png"), released.map { it.path })
    }

    @Test
    fun `video overlays are never released here`() {
        val video = overlay("v", "video", "/v.mp4")
        assertTrue(StillResidency.released(listOf(video), emptyList()).isEmpty())
    }

    @Test
    fun `an unchanged path stays`() {
        val before = overlay("text_a", "text", "/a.png", start = 1.0)
        val moved = overlay("text_a", "text", "/a.png", start = 2.0)
        assertTrue(StillResidency.released(listOf(before), listOf(moved)).isEmpty())
    }

    @Test
    fun `live first, then by start`() {
        // A text being edited is sent at no opacity: live, but skipped by the
        // draw before it uploads — only the preload ever loads it, so it
        // comes first.
        val list = listOf(
            overlay("text_late", "text", "/5.png", start = 5.0, end = 6.0),
            overlay("p", "image", "/photo.png", start = 0.0, end = 10.0),
            overlay("text_soon", "text", "/3.png", start = 3.0, end = 4.0),
            overlay("text_live", "text", "/live.png", start = 0.0, end = 2.0),
        )
        assertEquals(
            listOf("text_live", "text_soon", "text_late"),
            StillResidency.preloadOrder(list, 1.0).map { it.id },
        )
    }

    @Test
    fun `textsIn keeps only text`() {
        val list = listOf(
            overlay("p", "image", "/p.png"),
            overlay("text_a", "text", "/a.png"),
            overlay("v", "video", "/v.mp4"),
        )
        assertEquals(listOf("text_a"), StillResidency.textsIn(list).map { it.id })
    }
}
