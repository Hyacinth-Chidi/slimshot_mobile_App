package com.techfamz.slimshotai.nativepreview.gl.effects

import com.techfamz.slimshotai.nativepreview.EffectPassCosts
import com.techfamz.slimshotai.nativepreview.NativeTimelineEffect

/** What a drawing of an effect tile's atlas answers. */
internal sealed class EffectPreviewAnswer {
    /** The atlas, as one JPEG. */
    class Atlas(val jpeg: ByteArray) : EffectPreviewAnswer()

    /** This effect cannot be drawn here: Dart remembers it for the session. */
    object Failed : EffectPreviewAnswer()

    /** Not now — released, exporting, the GL thread gone. Dart asks again later. */
    object Busy : EffectPreviewAnswer()
}

/**
 * An effect tile's atlas: [frameCount] cells of [cellWidth] x [cellHeight],
 * [columns] to a row, frame 0 the plain picture and frame `k` the bar at
 * `(k - 1) / fps` seconds. The Dart `effect_preview_layout.dart` lays the
 * same grid out top-down; GL draws bottom-up, so [cellViewport] flips the row
 * and one flip of the read-back atlas puts every frame where Dart looks.
 */
internal data class EffectPreviewSpec(
    val cellWidth: Int,
    val cellHeight: Int,
    val columns: Int,
    val frameCount: Int,
    val fps: Int,
) {
    val rows: Int get() = (frameCount + columns - 1) / columns
    val atlasWidth: Int get() = cellWidth * columns
    val atlasHeight: Int get() = cellHeight * rows

    /** The bar's time at [index], or null for frame 0 — the plain picture. */
    fun frameSeconds(index: Int): Double? =
        if (index == 0) null else (index - 1).toDouble() / fps

    /** `[x, y, width, height]` of cell [index] in GL's bottom-up framebuffer. */
    fun cellViewport(index: Int): IntArray {
        val column = index % columns
        val row = index / columns
        return intArrayOf(column * cellWidth, (rows - 1 - row) * cellHeight, cellWidth, cellHeight)
    }

    /** The cells drawn per GL turn, in order — never more than [MAX_CELLS_PER_SLICE]. */
    fun slices(): List<IntRange> =
        (0 until frameCount step MAX_CELLS_PER_SLICE).map { first ->
            first until minOf(first + MAX_CELLS_PER_SLICE, frameCount)
        }

    companion object {
        /**
         * Cells a GL turn may draw before the live canvas gets the thread back:
         * a few milliseconds of tile work, never a whole effect's frames.
         */
        const val MAX_CELLS_PER_SLICE = 4

        private const val MAX_TEXTURE_PX = 4096

        /**
         * The spec Dart asked for, or null when it cannot be honoured: cells
         * must sit on 16-pixel JPEG blocks (no block straddles two frames) and
         * be at most 512 px, frames 2..64, columns 1..frames, 1..60 fps, and
         * the atlas within a texture's 4096.
         */
        fun fromArgs(
            cellWidth: Number?,
            cellHeight: Number?,
            columns: Number?,
            frames: Number?,
            fps: Number?,
        ): EffectPreviewSpec? {
            val spec = EffectPreviewSpec(
                cellWidth = cellWidth?.toInt() ?: return null,
                cellHeight = cellHeight?.toInt() ?: return null,
                columns = columns?.toInt() ?: return null,
                frameCount = frames?.toInt() ?: return null,
                fps = fps?.toInt() ?: return null,
            )
            fun cell(px: Int) = px in 16..512 && px % 16 == 0
            return spec.takeIf {
                cell(it.cellWidth) && cell(it.cellHeight) &&
                    it.frameCount in 2..64 && it.columns in 1..it.frameCount &&
                    it.fps in 1..60 &&
                    it.atlasWidth <= MAX_TEXTURE_PX && it.atlasHeight <= MAX_TEXTURE_PX
            }
        }
    }
}

/** One tile's drawing: the sample bar and the atlas to draw it into. */
internal data class EffectPreviewRequest(
    val bar: NativeTimelineEffect,
    val spec: EffectPreviewSpec,
) {
    companion object {
        /**
         * The request, or null when it cannot be drawn: a malformed bar, no
         * spec, or an effect this engine has no passes for — which answers
         * failed, so the tile keeps its icon instead of asking again.
         */
        fun parse(effect: Any?, spec: EffectPreviewSpec?): EffectPreviewRequest? {
            val map = effect as? Map<*, *> ?: return null
            val bar = NativeTimelineEffect.fromMap(map) ?: return null
            if (spec == null || EffectPassCosts.costOf(bar.effectId) == 0) return null
            return EffectPreviewRequest(bar, spec)
        }
    }
}
