package com.techfamz.slimshotai.nativepreview

import kotlin.math.PI
import kotlin.math.max
import kotlin.math.sin

/**
 * The export's copy of `caption_highlight_catalog.dart`: what each word
 * highlight does, as a pure function of time.
 *
 * **Pinned to the Dart by `caption_highlight_fixture.json`**
 * (`tool/generate_caption_highlight_fixture.dart`). If a highlight changes, it
 * changes on both sides and the fixture is regenerated, or the file highlights
 * differently from the canvas with nothing explaining why.
 */
internal object CaptionHighlightCurves {

    /** One word's spoken span, in seconds from the caption's start. */
    data class WordSpan(val start: Double, val end: Double)

    data class State(
        val highlighted: Boolean,
        val fill: Double,
        val scale: Double,
        val opacity: Double,
        val pill: Double,
    )

    val RESTING = State(highlighted = false, fill = 0.0, scale = 1.0, opacity = 1.0, pill = 0.0)

    const val RAMP_SECONDS = 0.08
    const val POP_SCALE = 1.2
    const val POP_HOLD = 1.1
    const val POP_SECONDS = 0.25
    const val FOCUS_DIM = 0.5

    private fun ramp(elapsed: Double): Double = (elapsed / RAMP_SECONDS).coerceIn(0.0, 1.0)

    /**
     * Word [index]'s state at [t] seconds into a caption of [spanSeconds].
     * A word is active from its start until the next word starts; the last
     * until the caption ends. Word times are clamped to the span.
     */
    fun stateAt(
        style: String,
        t: Double,
        words: List<WordSpan>,
        index: Int,
        spanSeconds: Double,
    ): State {
        if (style == "none" || index < 0 || index >= words.size) return RESTING
        val span = max(0.0, spanSeconds)
        fun clamp(v: Double) = v.coerceIn(0.0, span)

        val word = words[index]
        val start = clamp(word.start)
        val end = max(start, clamp(word.end))
        val activeEnd = if (index + 1 < words.size) max(start, clamp(words[index + 1].start)) else span
        val active = t >= start && (index == words.size - 1 || t < activeEnd)
        val spoken = t >= start
        val elapsed = t - start

        return when (style) {
            "colour" -> RESTING.copy(highlighted = active)
            "pop" -> {
                if (!active) return RESTING
                val p = (elapsed / POP_SECONDS).coerceIn(0.0, 1.0)
                // One sine over two floors: up from 1 to the peak, down onto
                // the hold, where the word stays while it is being spoken —
                // the Dart catalog's curve, pinned by the fixture.
                val floor = if (p < 0.5) 1.0 else POP_HOLD
                RESTING.copy(highlighted = true, scale = floor + (POP_SCALE - floor) * sin(PI * p))
            }
            "pill" -> RESTING.copy(pill = if (active) ramp(elapsed) else 0.0)
            "karaoke" -> {
                if (!spoken) return RESTING
                val length = end - start
                val fill = if (length <= 0.0) 1.0 else (elapsed / length).coerceIn(0.0, 1.0)
                RESTING.copy(highlighted = fill >= 1.0, fill = fill)
            }
            "reveal" -> RESTING.copy(opacity = if (spoken) ramp(elapsed) else 0.0)
            "focus" -> RESTING.copy(opacity = if (active) 1.0 else FOCUS_DIM)
            else -> RESTING
        }
    }
}
