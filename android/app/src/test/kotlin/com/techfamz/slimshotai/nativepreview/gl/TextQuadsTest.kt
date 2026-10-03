package com.techfamz.slimshotai.nativepreview.gl

import com.techfamz.slimshotai.nativepreview.CaptionHighlightCurves
import com.techfamz.slimshotai.nativepreview.FracRect
import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay
import com.techfamz.slimshotai.nativepreview.TextGlyphState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What a text overlay's quads are, frame by frame — the export's half of the
 * caption highlight, held to what the canvas painter draws.
 *
 * The fixture: four glyphs, two words ("ab" 0–0.5s, "cd" 0.5–1.0s), on an
 * overlay from 10s to 12s. Glyph `i` is placed at `0.1 + 0.2i` across the
 * box, 0.15 wide; its cell's `src` covers the middle 80%, so the full cell is
 * 0.1875 wide and starts 0.01875 before the glyph.
 */
class TextQuadsTest {

    private val eps = 1e-9

    private fun glyph(i: Int, word: Int, lit: Boolean): Map<String, Any> {
        val left = 0.1 + 0.2 * i
        return buildMap {
            put("atlasLeft", 0.1 * i)
            put("atlasTop", 0.0)
            put("atlasRight", 0.1 * i + 0.08)
            put("atlasBottom", 0.5)
            put("boxLeft", left)
            put("boxTop", 0.2)
            put("boxRight", left + 0.15)
            put("boxBottom", 0.8)
            put("srcLeft", 0.1)
            put("srcTop", 0.1)
            put("srcRight", 0.9)
            put("srcBottom", 0.9)
            if (lit) {
                put("litAtlasLeft", 0.1 * i)
                put("litAtlasTop", 0.5)
                put("litAtlasRight", 0.1 * i + 0.08)
                put("litAtlasBottom", 1.0)
            }
            if (word >= 0) put("word", word)
        }
    }

    private fun word(start: Double, end: Double, left: Double, right: Double, rtl: Boolean = false, pill: Int? = null) =
        buildMap<String, Any> {
            put("start", start)
            put("end", end)
            put("left", left)
            put("top", 0.2)
            put("right", right)
            put("bottom", 0.8)
            put("rtl", rtl)
            if (pill != null) {
                put("pillAtlasLeft", 0.5 + 0.2 * pill)
                put("pillAtlasTop", 0.0)
                put("pillAtlasRight", 0.6 + 0.2 * pill)
                put("pillAtlasBottom", 0.4)
                put("pillLeft", left - 0.02)
                put("pillTop", 0.18)
                put("pillRight", right + 0.02)
                put("pillBottom", 0.82)
            }
        }

    private fun overlay(
        style: String? = null,
        rtl: Boolean = false,
        background: Boolean = false,
    ): NativeTimelineOverlay {
        val lit = style == "colour" || style == "pop" || style == "karaoke"
        val pills = style == "pill"
        val map = buildMap<String, Any> {
            put("id", "t")
            put("kind", "text")
            put("path", "/atlas.png")
            put("startSeconds", 10.0)
            put("endSeconds", 12.0)
            put(
                "glyphs",
                listOf(
                    glyph(0, if (style != null) 0 else -1, lit),
                    glyph(1, if (style != null) 0 else -1, lit),
                    glyph(2, if (style != null) 1 else -1, lit),
                    glyph(3, if (style != null) 1 else -1, lit),
                ),
            )
            if (style != null) {
                put(
                    "highlight",
                    mapOf(
                        "style" to style,
                        "words" to listOf(
                            word(0.0, 0.5, 0.1, 0.45, rtl, if (pills) 0 else null),
                            word(0.5, 1.0, 0.5, 0.85, false, if (pills) 1 else null),
                        ),
                    ),
                )
            }
            put("backgroundLeft", 0.05)
            put("backgroundTop", 0.1)
            put("backgroundRight", 0.95)
            put("backgroundBottom", 0.9)
            if (background) {
                put("backgroundAtlasLeft", 0.0)
                put("backgroundAtlasTop", 0.6)
                put("backgroundAtlasRight", 0.4)
                put("backgroundAtlasBottom", 0.9)
            }
        }
        return NativeTimelineOverlay.fromMap(map)!!
    }

    private fun cellOf(i: Int): FracRect {
        val width = 0.15 / 0.8
        val height = 0.6 / 0.8
        val left = 0.1 + 0.2 * i - 0.1 * width
        val top = 0.2 - 0.1 * height
        return FracRect(left, top, left + width, top + height)
    }

    private fun baseOf(i: Int) = FracRect(0.1 * i, 0.0, 0.1 * i + 0.08, 0.5)
    private fun litOf(i: Int) = FracRect(0.1 * i, 0.5, 0.1 * i + 0.08, 1.0)

    private fun near(where: String, expected: FracRect, actual: FracRect) {
        for ((name, e, a) in listOf(
            Triple("left", expected.left, actual.left),
            Triple("top", expected.top, actual.top),
            Triple("right", expected.right, actual.right),
            Triple("bottom", expected.bottom, actual.bottom),
        )) {
            assertEquals("$where $name", e, a, 1e-6)
        }
    }

    private fun quadsAt(o: NativeTimelineOverlay, t: Double, motion: TextGlyphState = TextGlyphState()) =
        TextQuads.glyphs(o, t) { motion }

    @Test
    fun `parses each glyph's lit cell and word, the highlight and the box cell`() {
        val o = overlay(style = "karaoke", background = true)
        near("lit", litOf(1), o.glyphs[1].lit!!)
        assertEquals(1, o.glyphs[2].word)
        val highlight = o.highlight!!
        assertEquals("karaoke", highlight.style)
        assertEquals(2, highlight.words.size)
        assertEquals(0.5, highlight.words[1].start, eps)
        near("word box", FracRect(0.5, 0.2, 0.85, 0.8), highlight.words[1].box)
        near("box cell", FracRect(0.0, 0.6, 0.4, 0.9), o.backgroundAtlas!!)

        val pill = overlay(style = "pill").highlight!!.words[0]
        near("pill atlas", FracRect(0.5, 0.0, 0.6, 0.4), pill.pillAtlas!!)
        near("pill box", FracRect(0.08, 0.18, 0.47, 0.82), pill.pillBox!!)
    }

    @Test
    fun `ordinary text parses as it always did`() {
        val o = overlay()
        assertNull(o.highlight)
        assertNull(o.backgroundAtlas)
        assertNull(o.glyphs[0].lit)
        assertEquals(-1, o.glyphs[0].word)
    }

    @Test
    fun `a highlight that does not read whole is no highlight`() {
        val map = mapOf(
            "id" to "t", "kind" to "text", "path" to "/a.png",
            "startSeconds" to 0.0, "endSeconds" to 1.0,
            "glyphs" to listOf(glyph(0, 0, false)),
            "highlight" to mapOf(
                "style" to "colour",
                // The second word has no times: a half-read table would mark
                // every later glyph against the wrong word.
                "words" to listOf(word(0.0, 0.5, 0.1, 0.4), mapOf("left" to 0.5)),
            ),
        )
        assertNull(NativeTimelineOverlay.fromMap(map)!!.highlight)
    }

    @Test
    fun `plain text gives one quad per glyph, the whole cell, as before`() {
        val motion = TextGlyphState(opacity = 0.4, offsetX = 1.0, offsetY = -0.5, scale = 1.3, rotation = 0.2)
        val quads = quadsAt(overlay(), 10.5, motion)
        assertEquals(4, quads.size)
        for (i in 0 until 4) {
            near("cell $i", cellOf(i), quads[i].box)
            near("src $i", baseOf(i), quads[i].src)
            assertEquals(0.4, quads[i].opacity, eps)
            assertEquals(1.3, quads[i].glyphScale, eps)
            assertEquals(0.2, quads[i].glyphRotation, eps)
            // Glyph heights converted to box-height fractions: the glyph is
            // 0.6 of the box tall.
            assertEquals(0.6, quads[i].glyphOffsetX, eps)
            assertEquals(-0.3, quads[i].glyphOffsetY, eps)
        }
    }

    @Test
    fun `colour lights the word being spoken from its lit cells, the rest from their own`() {
        val first = quadsAt(overlay(style = "colour"), 10.2)
        near("0", litOf(0), first[0].src)
        near("1", litOf(1), first[1].src)
        near("2", baseOf(2), first[2].src)
        near("3", baseOf(3), first[3].src)

        val second = quadsAt(overlay(style = "colour"), 10.7)
        near("0 later", baseOf(0), second[0].src)
        near("2 later", litOf(2), second[2].src)
    }

    @Test
    fun `pop swells the word about its own centre, not each letter about its own`() {
        val peak = 10.0 + CaptionHighlightCurves.POP_SECONDS / 2
        val quads = quadsAt(overlay(style = "pop"), peak)
        val swell = CaptionHighlightCurves.POP_SCALE
        assertEquals(swell, quads[0].glyphScale, 1e-6)
        near("lit", litOf(0), quads[0].src)

        // Moved away from the word's centre (0.275, 0.5) by as much again.
        val cell = cellOf(0)
        val wordCentreX = (0.1 + 0.45) / 2
        val shift = ((cell.left + cell.right) / 2 - wordCentreX) * (swell - 1)
        near("moved", FracRect(cell.left + shift, cell.top, cell.right + shift, cell.bottom), quads[0].box)

        // The word not being spoken rests.
        assertEquals(1.0, quads[2].glyphScale, eps)
        near("rest", cellOf(2), quads[2].box)
    }

    @Test
    fun `karaoke cuts a glyph the sweep crosses, lit behind and plain ahead`() {
        // 0.35s into a 0.5s word: the sweep is 70% across the word's box.
        val quads = quadsAt(overlay(style = "karaoke"), 10.35)
        val sweep = 0.1 + 0.35 * 0.7
        // Glyph 0 lies wholly behind the sweep, glyph 1 is crossed, the second
        // word is not yet spoken.
        assertEquals(5, quads.size)
        near("0 lit", litOf(0), quads[0].src)

        val cell = cellOf(1)
        val behind = quads[1]
        val ahead = quads[2]
        near("behind box", FracRect(cell.left, cell.top, sweep, cell.bottom), behind.box)
        near("ahead box", FracRect(sweep, cell.top, cell.right, cell.bottom), ahead.box)
        // The atlas is cut at the same fraction of the cell.
        val u = 0.1 + (sweep - cell.left) / (cell.right - cell.left) * 0.08
        near("behind src", FracRect(0.1, 0.5, u, 1.0), behind.src)
        near("ahead src", FracRect(u, 0.0, 0.18, 0.5), ahead.src)

        near("2 plain", baseOf(2), quads[3].src)
    }

    @Test
    fun `karaoke runs from the right on a right-to-left word`() {
        val quads = quadsAt(overlay(style = "karaoke", rtl = true), 10.35)
        val sweep = 0.45 - 0.35 * 0.7
        val cell = cellOf(0)
        // Glyph 0 is crossed — the lit half is on the right, behind first —
        // and glyph 1, right of the sweep, is lit whole.
        near("behind", FracRect(sweep, cell.top, cell.right, cell.bottom), quads[0].box)
        assertEquals(0.5, quads[0].src.top, eps)
        near("ahead", FracRect(cell.left, cell.top, sweep, cell.bottom), quads[1].box)
        assertEquals(0.0, quads[1].src.top, eps)
        near("1 lit", litOf(1), quads[2].src)
    }

    @Test
    fun `a cut glyph scales about its whole cell, so the halves stay together`() {
        val quads = quadsAt(overlay(style = "karaoke"), 10.35, TextGlyphState(scale = 2.0))
        val cell = cellOf(1)
        val centreX = (cell.left + cell.right) / 2
        val centreY = (cell.top + cell.bottom) / 2
        fun grown(x: Double) = centreX + (x - centreX) * 2.0
        fun grownY(y: Double) = centreY + (y - centreY) * 2.0
        val sweep = 0.1 + 0.35 * 0.7
        near("behind", FracRect(grown(cell.left), grownY(cell.top), grown(sweep), grownY(cell.bottom)), quads[1].box)
        near("ahead", FracRect(grown(sweep), grownY(cell.top), grown(cell.right), grownY(cell.bottom)), quads[2].box)
        assertEquals(1.0, quads[1].glyphScale, eps)
        assertEquals(1.0, quads[2].glyphScale, eps)
    }

    @Test
    fun `reveal hides a word not yet spoken`() {
        val quads = quadsAt(overlay(style = "reveal"), 10.2)
        assertEquals(2, quads.size)
        assertEquals(1.0, quads[0].opacity, eps)
    }

    @Test
    fun `focus dims the other words`() {
        val quads = quadsAt(overlay(style = "focus"), 10.2)
        assertEquals(1.0, quads[0].opacity, eps)
        assertEquals(CaptionHighlightCurves.FOCUS_DIM, quads[2].opacity, eps)
    }

    @Test
    fun `pill puts a box behind the word being spoken, fading in`() {
        val o = overlay(style = "pill")
        val early = TextQuads.pills(o, 10.0 + CaptionHighlightCurves.RAMP_SECONDS / 2)
        assertEquals(1, early.size)
        assertEquals(0.5, early[0].opacity, 1e-6)
        near("src", FracRect(0.5, 0.0, 0.6, 0.4), early[0].src)
        near("box", FracRect(0.08, 0.18, 0.47, 0.82), early[0].box)

        val later = TextQuads.pills(o, 10.7)
        assertEquals(1, later.size)
        near("second word", FracRect(0.7, 0.0, 0.8, 0.4), later[0].src)

        assertTrue(TextQuads.pills(overlay(style = "colour"), 10.2).isEmpty())
        assertTrue(TextQuads.pills(overlay(), 10.2).isEmpty())
    }

    @Test
    fun `the background box is one quad of its own cell`() {
        val quad = TextQuads.background(overlay(background = true))
        assertNotNull(quad)
        near("src", FracRect(0.0, 0.6, 0.4, 0.9), quad!!.src)
        near("box", FracRect(0.05, 0.1, 0.95, 0.9), quad.box)
        assertEquals(1.0, quad.opacity, eps)
        assertNull(TextQuads.background(overlay()))
    }
}
