package com.techfamz.slimshotai.nativepreview.gl

import com.techfamz.slimshotai.nativepreview.CaptionHighlightCurves
import com.techfamz.slimshotai.nativepreview.FracRect
import com.techfamz.slimshotai.nativepreview.NativeTextHighlight
import com.techfamz.slimshotai.nativepreview.NativeTimelineGlyph
import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay
import com.techfamz.slimshotai.nativepreview.TextGlyphState

/**
 * The quads a text overlay draws at one instant: its background box, a pill
 * behind each word that has one showing, and its glyphs.
 *
 * **Pure arithmetic, no GL**, so the export's half of the caption highlight is
 * tested on the JVM against the same cases the canvas painter is
 * (`text_overlay_painter.dart`). The painter is the reference: every rule
 * below restates one of its rules in box fractions.
 */
internal object TextQuads {

    /**
     * One quad. [src] is a cell of the atlas; [box] is where it lands, in
     * text-box fractions. The four glyph fields are `OverlayRenderer.Draw`'s
     * own, and rest at identity for a quad that is not a glyph.
     */
    data class Quad(
        val src: FracRect,
        val box: FracRect,
        /** Multiplied into the overlay's own opacity. */
        val opacity: Double,
        val glyphScale: Double = 1.0,
        val glyphRotation: Double = 0.0,
        /** Box-height fractions, as `Draw` wants them. */
        val glyphOffsetX: Double = 0.0,
        val glyphOffsetY: Double = 0.0,
    )

    /**
     * The background box as one quad, or null for a text without one.
     *
     * One rect behind every glyph that **does not move with the letters**: a
     * box sliced per character would come apart the moment a glyph moved.
     */
    fun background(overlay: NativeTimelineOverlay): Quad? {
        val cell = overlay.backgroundAtlas ?: return null
        return Quad(
            src = cell,
            box = FracRect(
                overlay.backgroundLeft,
                overlay.backgroundTop,
                overlay.backgroundRight,
                overlay.backgroundBottom,
            ),
            opacity = 1.0,
        )
    }

    /**
     * A pill behind each word whose pill is showing, faded by how far it has
     * come in. Like the background, a pill does not travel with a letter's
     * own animation.
     */
    fun pills(overlay: NativeTimelineOverlay, t: Double): List<Quad> {
        val highlight = overlay.highlight ?: return emptyList()
        val local = t - overlay.startSeconds
        val span = overlay.endSeconds - overlay.startSeconds
        val quads = ArrayList<Quad>(1)
        highlight.words.forEachIndexed { index, word ->
            val src = word.pillAtlas ?: return@forEachIndexed
            val box = word.pillBox ?: return@forEachIndexed
            val pill = highlight.stateAt(index, local, span).pill
            if (pill > 0.0) quads.add(Quad(src = src, box = box, opacity = pill))
        }
        return quads
    }

    /**
     * The glyphs at [t] (timeline seconds), each moved by its own animation
     * ([motion], by glyph index) and marked by its word's highlight.
     *
     * **The quad is the whole padded cell, positioned so that the cell's
     * `src` sub-rect lands exactly on the glyph's box rect** — the cell's
     * padding carries the stroke and shadow bleed, which must spill past the
     * glyph's placement without being drawn twice where neighbours overlap.
     */
    fun glyphs(
        overlay: NativeTimelineOverlay,
        t: Double,
        motion: (Int) -> TextGlyphState,
    ): List<Quad> {
        val quads = ArrayList<Quad>(overlay.glyphs.size)
        forEachPlaced(overlay, t, motion) { glyph, p ->
            val base = FracRect(glyph.atlasLeft, glyph.atlasTop, glyph.atlasRight, glyph.atlasBottom)
            val lit = glyph.lit
            val marked = p.marked
            val cell = p.cell

            if (marked.fill > 0.0 && marked.fill < 1.0 && lit != null) {
                // **Karaoke cuts the glyph at the sweep**: lit behind the line,
                // plain ahead of it — two quads over the one cell, each
                // sampling the matching slice of its own cell.
                val word = p.marking!!.words[glyph.word]
                val wordBox = word.box
                val rtl = word.rtl
                val sweep = (
                    if (rtl) wordBox.right - wordBox.width * marked.fill
                    else wordBox.left + wordBox.width * marked.fill
                    ).coerceIn(cell.left, cell.right)
                val leftPart = FracRect(cell.left, cell.top, sweep, cell.bottom)
                val rightPart = FracRect(sweep, cell.top, cell.right, cell.bottom)
                val (behind, ahead) = if (rtl) rightPart to leftPart else leftPart to rightPart

                for ((part, atlas) in listOf(behind to lit, ahead to base)) {
                    if (part.width <= 0.0) continue
                    // The halves scale about the **whole cell's** centre,
                    // pre-applied here: `Draw` would scale each about its own
                    // and pull the two apart. A rotation cannot be pre-applied
                    // to an axis-aligned rect, so each half turns about its own
                    // centre — a seam that opens only while a rotating
                    // per-glyph animation and a karaoke sweep cross the same
                    // letter at once.
                    quads.add(
                        Quad(
                            src = slice(atlas, cell, part),
                            box = scaledAbout(part, cell.centerX, cell.centerY, p.scale),
                            opacity = p.opacity,
                            glyphScale = 1.0,
                            glyphRotation = p.rotation,
                            glyphOffsetX = p.offsetX,
                            glyphOffsetY = p.offsetY,
                        ),
                    )
                }
            } else {
                quads.add(
                    Quad(
                        src = if (marked.highlighted && lit != null) lit else base,
                        box = cell,
                        opacity = p.opacity,
                        glyphScale = p.scale,
                        glyphRotation = p.rotation,
                        glyphOffsetX = p.offsetX,
                        glyphOffsetY = p.offsetY,
                    ),
                )
            }
        }
        return quads
    }

    /**
     * Each glyph's shadow, placed exactly as its letter is — drawn before
     * every letter ([glyphs]), so a shadow lies under all of them as it does
     * on the canvas. Baked into the letter's own cell, line 2's shadows were
     * drawn over line 1's letters. One quad per letter: the lit and plain
     * halves of a swept letter share one silhouette.
     */
    fun shadows(
        overlay: NativeTimelineOverlay,
        t: Double,
        motion: (Int) -> TextGlyphState,
    ): List<Quad> {
        val quads = ArrayList<Quad>(overlay.glyphs.size)
        forEachPlaced(overlay, t, motion) { glyph, p ->
            val shadow = glyph.shadow ?: return@forEachPlaced
            quads.add(
                Quad(
                    src = shadow,
                    box = p.cell,
                    opacity = p.opacity,
                    glyphScale = p.scale,
                    glyphRotation = p.rotation,
                    glyphOffsetX = p.offsetX,
                    glyphOffsetY = p.offsetY,
                ),
            )
        }
        return quads
    }

    /** Where a glyph is drawn at an instant — its letter and its shadow alike. */
    private class Placement(
        val cell: FracRect,
        val opacity: Double,
        val scale: Double,
        val rotation: Double,
        val offsetX: Double,
        val offsetY: Double,
        val marked: CaptionHighlightCurves.State,
        val marking: NativeTextHighlight?,
    )

    /**
     * Every glyph that is drawn at [t], with its placement — the one
     * definition [glyphs] and [shadows] both read, so a shadow can never sit
     * anywhere but under its own letter.
     */
    private inline fun forEachPlaced(
        overlay: NativeTimelineOverlay,
        t: Double,
        motion: (Int) -> TextGlyphState,
        draw: (NativeTimelineGlyph, Placement) -> Unit,
    ) {
        val highlight = overlay.highlight
        val local = t - overlay.startSeconds
        val span = overlay.endSeconds - overlay.startSeconds

        overlay.glyphs.forEachIndexed { index, glyph ->
            val srcW = glyph.srcRight - glyph.srcLeft
            val srcH = glyph.srcBottom - glyph.srcTop
            // A degenerate sub-rect has no scale to solve for; skipping the
            // glyph loses one letter, dividing by it would place every quad
            // at infinity and lose the whole text.
            if (srcW <= 0.0 || srcH <= 0.0) return@forEachIndexed

            val cellWidth = (glyph.boxRight - glyph.boxLeft) / srcW
            val cellHeight = (glyph.boxBottom - glyph.boxTop) / srcH
            val cellLeft = glyph.boxLeft - glyph.srcLeft * cellWidth
            val cellTop = glyph.boxTop - glyph.srcTop * cellHeight
            var cell = FracRect(cellLeft, cellTop, cellLeft + cellWidth, cellTop + cellHeight)

            val anim = motion(index)
            val word = glyph.word
            val marking = highlight?.takeIf { word in it.words.indices }
            val marked = marking?.stateAt(word, local, span) ?: CaptionHighlightCurves.RESTING

            val opacity = anim.opacity * marked.opacity
            val scale = anim.scale * marked.scale
            // A glyph animated to nothing is dropped rather than drawn at
            // zero: a zero-area quad is wasted state changes, and a negative
            // scale would turn the letter inside out.
            if (opacity <= 0.0 || scale <= 0.0) return@forEachIndexed

            // **A popped word swells about its own centre**, not each letter
            // about its own: every glyph is scaled in place and moved away
            // from the word's centre by as much, so the word grows as one.
            if (marked.scale != 1.0) {
                val wordBox = marking!!.words[word].box
                val grow = marked.scale - 1.0
                val dx = (cell.centerX - wordBox.centerX) * grow
                val dy = (cell.centerY - wordBox.centerY) * grow
                cell = FracRect(cell.left + dx, cell.top + dy, cell.right + dx, cell.bottom + dy)
            }

            // The catalog measures displacement in **glyph heights**, on both
            // axes, so a diagonal slide stays diagonal and the travel scales
            // with the type size. `Draw` wants box-height fractions: the
            // glyph's own height as a fraction of the box, applied to x and y
            // alike.
            val glyphHeightInBox = glyph.boxBottom - glyph.boxTop
            draw(
                glyph,
                Placement(
                    cell = cell,
                    opacity = opacity,
                    scale = scale,
                    rotation = anim.rotation,
                    offsetX = anim.offsetX * glyphHeightInBox,
                    offsetY = anim.offsetY * glyphHeightInBox,
                    marked = marked,
                    marking = marking,
                ),
            )
        }
    }

    /** The slice of atlas cell [atlas] that lands on [part] of [cell]. */
    private fun slice(atlas: FracRect, cell: FracRect, part: FracRect): FracRect {
        fun u(x: Double) = atlas.left + (x - cell.left) / cell.width * atlas.width
        return FracRect(u(part.left), atlas.top, u(part.right), atlas.bottom)
    }

    private fun scaledAbout(rect: FracRect, cx: Double, cy: Double, scale: Double): FracRect {
        if (scale == 1.0) return rect
        return FracRect(
            cx + (rect.left - cx) * scale,
            cy + (rect.top - cy) * scale,
            cx + (rect.right - cx) * scale,
            cy + (rect.bottom - cy) * scale,
        )
    }
}
