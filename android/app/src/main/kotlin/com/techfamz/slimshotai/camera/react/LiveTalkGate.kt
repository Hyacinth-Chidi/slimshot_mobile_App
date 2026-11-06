package com.techfamz.slimshotai.camera.react

/**
 * Out loud, the video plays from the phone's speaker and the microphone hears
 * it. This gate lowers the video while you talk and holds the microphone back
 * while you don't, so the speaker's copy does not double the video's clean
 * sound in the file.
 *
 * **Talking is what the microphone hears above the video's own sound at that
 * moment.** The mixer knows that sound — it reads the video's audio beside the
 * microphone — so each 10 ms block brings both levels. The speaker's copy
 * arrives at the microphone some fixed amount quieter (the bleed, learned as
 * the low end of microphone-minus-video over the last few seconds, where
 * pauses in talking show it bare); the room's own level is learned while the
 * video is silent. A block is talking when the microphone stands
 * [MARGIN_DB] above both. Loud music in the video raises the expected level
 * with it, so it is not mistaken for a voice.
 *
 * **Where the gate cannot tell, it opens everything**: before it has half a
 * second to go on, while the video is audible but its bleed not yet learned,
 * and when the "bleed" comes out implausibly loud — which is what continuous
 * talking from the first moment looks like. A voice is never held back on a
 * guess; the cost is the speaker's copy left in for a while.
 *
 * Talking runs bridge short pauses, drop clicks, and are padded before and
 * after; [gainsAt] is asked [LOOKAHEAD_MS] behind the newest block, so the
 * video dips with the first word rather than after it. Pure, JVM-tested.
 */
internal class LiveTalkGate(
    private val lowerVideo: Boolean,
    private val duck: Double,
    private val gate: Double,
    private val rampMs: Int,
) {
    data class Gains(val video: Double, val mic: Double)

    private class Block(val fileMs: Long, val micDb: Double, val videoDb: Double)

    private val window = ArrayDeque<Block>()

    /** Closed talking runs that lasted long enough, [start, end) in file ms. */
    private val spans = ArrayList<LongArray>()

    /** Stretches where the gate could not tell, [from, to). */
    private val uncertain = ArrayList<LongArray>()

    private var firstMs: Long? = null
    private var lastMs: Long? = null
    private var runStart: Long? = null
    private var runEnd = 0L

    fun addBlock(fileMs: Long, micDb: Double, videoDb: Double) {
        val first = firstMs ?: fileMs.also { firstMs = it }
        lastMs = fileMs
        window.addLast(Block(fileMs, micDb, videoDb))
        while (window.first().fileMs <= fileMs - WINDOW_MS) window.removeFirst()

        val audible = window.filter { it.videoDb > AUDIBLE_DB }
        val bleed = if (audible.size >= MIN_ESTIMATE_BLOCKS) {
            percentile(audible.map { it.micDb - it.videoDb }, 0.10)
        } else {
            null
        }
        val silent = window.filter { it.videoDb <= AUDIBLE_DB }
        val room = if (silent.size >= MIN_ESTIMATE_BLOCKS) percentile(silent.map { it.micDb }, 0.10) else SILENT_DB
        val videoAudible = videoDb > AUDIBLE_DB

        val unsure = fileMs - first < WARMUP_MS ||
            (bleed != null && bleed > MAX_BLEED_DB) ||
            (videoAudible && bleed == null)
        if (unsure) markUncertain(fileMs)

        val expected = maxOf(room, if (bleed != null) videoDb + bleed else Double.NEGATIVE_INFINITY)
        val voiced = !unsure && micDb >= expected + MARGIN_DB && micDb > SILENT_DB

        val open = runStart
        if (voiced) {
            if (open != null && fileMs - runEnd < BRIDGE_MS) {
                runEnd = fileMs + BLOCK_MS
            } else {
                closeRun()
                runStart = fileMs
                runEnd = fileMs + BLOCK_MS
            }
        } else if (open != null && fileMs - runEnd >= BRIDGE_MS) {
            closeRun()
        }
    }

    /** The video's and the microphone's gains at [fileMs]. */
    fun gainsAt(fileMs: Long): Gains {
        if (!lowerVideo) return Gains(1.0, 1.0)
        val first = firstMs ?: return Gains(1.0, 1.0)
        if (fileMs < first || isUncertain(fileMs)) return Gains(1.0, 1.0)
        prune(fileMs)
        val share = shareAt(fileMs)
        return Gains(1.0 - (1.0 - duck) * share, gate + (1.0 - gate) * share)
    }

    private fun closeRun() {
        val start = runStart ?: return
        if (runEnd - start >= MIN_TALK_MS) spans += longArrayOf(start, runEnd)
        runStart = null
    }

    private fun shareAt(t: Long): Double {
        var share = 0.0
        fun consider(start: Long, end: Long) {
            val from = start - LEAD_MS
            val to = end + TAIL_MS
            val s = when {
                t in from..to -> 1.0
                t < from && t >= from - rampMs -> (t - (from - rampMs)).toDouble() / rampMs
                t > to && t <= to + rampMs -> 1.0 - (t - to).toDouble() / rampMs
                else -> 0.0
            }
            if (s > share) share = s
        }
        for (span in spans) consider(span[0], span[1])
        val open = runStart
        if (open != null && runEnd - open >= MIN_TALK_MS) consider(open, runEnd)
        return share.coerceIn(0.0, 1.0)
    }

    private fun markUncertain(fileMs: Long) {
        val last = uncertain.lastOrNull()
        if (last != null && last[1] >= fileMs) {
            last[1] = fileMs + BLOCK_MS
        } else {
            uncertain += longArrayOf(fileMs, fileMs + BLOCK_MS)
        }
    }

    private fun isUncertain(t: Long): Boolean = uncertain.any { t >= it[0] && t < it[1] }

    /** Forgets what lies well behind [t]: the mixer only ever asks forward. */
    private fun prune(t: Long) {
        val horizon = t - FORGET_MS
        spans.removeAll { it[1] + TAIL_MS + rampMs < horizon }
        uncertain.removeAll { it[1] < horizon }
    }

    private fun percentile(values: List<Double>, share: Double): Double {
        val sorted = values.sorted()
        return sorted[((sorted.size - 1) * share).toInt()]
    }

    companion object {
        const val BLOCK_MS = 10L
        const val LOOKAHEAD_MS = 250L
        const val LEAD_MS = 80L
        const val TAIL_MS = 200L
        const val BRIDGE_MS = 400L
        const val MIN_TALK_MS = 120L
        const val WINDOW_MS = 6_000L
        const val WARMUP_MS = 500L
        const val MARGIN_DB = 8.0
        const val SILENT_DB = -50.0

        /** The video counts as audible above this. */
        const val AUDIBLE_DB = -45.0

        /** A speaker's copy louder than this, relative to the video, is not a copy: the gate cannot tell. */
        const val MAX_BLEED_DB = -6.0

        /** Blocks an estimate needs before it is trusted: half a second. */
        const val MIN_ESTIMATE_BLOCKS = 50
        const val FORGET_MS = 2_000L
    }
}
