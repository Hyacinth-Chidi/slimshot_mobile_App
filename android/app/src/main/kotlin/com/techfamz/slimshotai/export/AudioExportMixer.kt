package com.techfamz.slimshotai.export

import android.media.MediaCodec
import android.media.MediaFormat
import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.nativepreview.NativeTimelineClip
import com.techfamz.slimshotai.nativepreview.NativeTimelineTransitionIntent
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Mixes the timeline's audio and encodes it as AAC.
 *
 * The gain rules are the preview's, not a second set: a clip plays at
 * `masterVolume * clip.volume`, and across a transition the two clips are
 * cross-faded **equal-power** — `cos` out, `sin` in — which is what keeps the
 * combined loudness steady through the blend instead of dipping in the middle.
 * Those are the same expressions `TimelinePlaybackEngine.applyAudio` uses.
 *
 * Audio is mixed over the whole timeline in blocks rather than per clip, so
 * overlapping sources simply sum — which is what a transition and a background
 * music track both need.
 */
@UnstableApi
internal class AudioExportMixer(
    private val clips: List<NativeTimelineClip>,
    private val audioTracks: List<TimelineAudioTrack>,
    private val masterVolume: Double,
    private val transitions: List<NativeTimelineTransitionIntent>,
    private val durationSeconds: Double,
) {

    /** An imported audio track laid on the timeline. */
    data class TimelineAudioTrack(
        val filePath: String,
        val sourceStart: Double,
        val timelineStart: Double,
        val timelineEnd: Double,
        val volume: Double,
    )

    private class Source(
        val reader: PcmAudioSource,
        val timelineStart: Double,
        val timelineEnd: Double,
        val gainAt: (Double) -> Double,
    ) {
        var started = false
    }

    private var codec: MediaCodec? = null
    private val bufferInfo = MediaCodec.BufferInfo()

    var trackIndex: Int = -1
        private set

    // Counters, so a silent export says which stage produced nothing rather
    // than leaving the whole chain as a suspect.
    private var framesRead = 0L
    private var samplesWritten = 0
    private var bytesWritten = 0L
    private var sourceCount = 0

    /** Why each clip or track contributed nothing, for the silent-export report. */
    private val skipped = mutableListOf<String>()

    /**
     * One line describing what the audio pass actually did.
     *
     * Reported to the user when the result is silent, because "the export has
     * no sound" is indistinguishable from outside whether the sources never
     * opened, the decoders produced nothing, or the encoder emitted nothing.
     */
    val diagnostics: String
        get() {
            val base = "sources=$sourceCount read=$framesRead " +
                "samples=$samplesWritten bytes=$bytesWritten track=$trackIndex"
            if (skipped.isEmpty()) return base
            return "$base — skipped: ${skipped.joinToString("; ")}"
        }

    /** True when the pass ran but nothing audible came out of it. */
    val producedNothing: Boolean
        get() = sourceCount > 0 && samplesWritten == 0

    /**
     * The first concrete reason nothing opened, short enough to fit in a toast.
     *
     * A counter dump is useless to a user and gets truncated before the part
     * that matters; the reason itself is what identifies the fault.
     */
    val firstFailureReason: String
        get() = skipped.firstOrNull() ?: "no clips carried audio"

    private var prepared: List<Source>? = null

    /**
     * Opens the sources and reports whether there is anything to encode.
     *
     * Has to happen before the muxer is built: the muxer must be told how many
     * tracks to wait for, and promising it an audio track that never arrives
     * would leave it waiting forever and produce no file at all. Only actually
     * opening the sources can answer that — a video file may well have no audio
     * track, and a silent clip is perfectly normal.
     */
    fun prepare(): Boolean {
        val sources = buildSources()
        prepared = sources
        sourceCount = sources.size
        Log.i(
            TAG,
            "audio prepare: ${sources.size} source(s) from ${clips.size} clip(s) " +
                "and ${audioTracks.size} track(s), masterVolume=$masterVolume",
        )
        return sources.isNotEmpty()
    }

    /** Closes anything [prepare] opened, for the paths that never encode. */
    fun release() {
        prepared?.forEach { it.reader.release() }
        prepared = null
    }

    /**
     * Renders and encodes the whole audio track.
     *
     * Done in one pass before the video rather than interleaved: audio is a
     * fraction of the work, and keeping it separate means the video loop is not
     * carrying a second set of decoders alongside its own.
     */
    fun encodeTo(
        muxer: ExportMuxer,
        isCancelled: () -> Boolean,
        onProgress: (Double) -> Unit = {},
    ) {
        val sources = prepared ?: buildSources().also { prepared = it }
        if (sources.isEmpty()) {
            onProgress(1.0)
            return
        }

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        codec = encoder
        try {
            val format = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC,
                SAMPLE_RATE,
                CHANNELS,
            ).apply {
                setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
                setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    android.media.MediaCodecInfo.CodecProfileLevel.AACObjectLC,
                )
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, BLOCK_FRAMES * CHANNELS * 4)
            }
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()

            val totalFrames = (durationSeconds * SAMPLE_RATE).toLong()
            val mix = FloatArray(BLOCK_FRAMES * CHANNELS)
            val scratch = FloatArray(BLOCK_FRAMES * CHANNELS)
            val pcm = ByteBuffer
                .allocateDirect(BLOCK_FRAMES * CHANNELS * 2)
                .order(ByteOrder.nativeOrder())

            var frame = 0L
            var blocksSinceReport = 0
            while (frame < totalFrames && !isCancelled()) {
                val block = minOf(BLOCK_FRAMES.toLong(), totalFrames - frame).toInt()
                java.util.Arrays.fill(mix, 0f)

                for (source in sources) {
                    mixSource(source, frame, block, mix, scratch)
                }

                pcm.clear()
                for (i in 0 until block * CHANNELS) {
                    // Clip rather than wrap: summed sources can exceed full
                    // scale, and wrapping turns a loud moment into a crack.
                    val sample = (mix[i] * PCM_16_SCALE)
                        .coerceIn(-PCM_16_SCALE, PCM_16_SCALE - 1)
                    pcm.putShort(sample.toInt().toShort())
                }
                pcm.flip()

                queue(encoder, pcm, frame, muxer)
                frame += block

                // The audio pass runs to completion before a single video frame
                // is drawn, so without this the progress bar sits at zero for
                // its whole duration and the export reads as frozen.
                if (++blocksSinceReport >= PROGRESS_EVERY_BLOCKS) {
                    blocksSinceReport = 0
                    onProgress((frame.toDouble() / totalFrames).coerceIn(0.0, 1.0))
                }
            }
            onProgress(1.0)

            if (signalEnd(encoder, frame)) {
                drain(encoder, muxer, endOfStream = true)
            }

            Log.i(
                TAG,
                "audio encoded: track=$trackIndex frames=$frame " +
                    "read=$framesRead samples=$samplesWritten bytes=$bytesWritten",
            )
        } finally {
            sources.forEach { it.reader.release() }
            prepared = null
            try {
                encoder.stop()
            } catch (error: Exception) {
                Log.w(TAG, "Audio encoder stop failed", error)
            }
            encoder.release()
            codec = null
        }
    }

    private fun mixSource(
        source: Source,
        startFrame: Long,
        block: Int,
        mix: FloatArray,
        scratch: FloatArray,
    ) {
        val blockStart = startFrame.toDouble() / SAMPLE_RATE
        val blockEnd = (startFrame + block).toDouble() / SAMPLE_RATE
        if (blockEnd <= source.timelineStart || blockStart >= source.timelineEnd) return

        if (!source.started) {
            source.started = true
        }

        val produced = source.reader.read(scratch, 0, block)
        if (produced <= 0) return
        framesRead += produced

        for (i in 0 until produced) {
            val t = (startFrame + i).toDouble() / SAMPLE_RATE
            if (t < source.timelineStart || t >= source.timelineEnd) continue
            val gain = source.gainAt(t).toFloat()
            if (gain == 0f) continue
            mix[i * 2] += scratch[i * 2] * gain
            mix[i * 2 + 1] += scratch[i * 2 + 1] * gain
        }
    }

    private fun queue(
        encoder: MediaCodec,
        pcm: ByteBuffer,
        startFrame: Long,
        muxer: ExportMuxer,
    ) {
        while (pcm.hasRemaining()) {
            val index = encoder.dequeueInputBuffer(TIMEOUT_US)
            if (index < 0) {
                drain(encoder, muxer, endOfStream = false)
                continue
            }
            val input = encoder.getInputBuffer(index) ?: return
            input.clear()
            val size = minOf(input.remaining(), pcm.remaining())
            val slice = pcm.slice()
            slice.limit(size)
            input.put(slice)
            pcm.position(pcm.position() + size)

            encoder.queueInputBuffer(
                index,
                0,
                size,
                startFrame * 1_000_000L / SAMPLE_RATE,
                0,
            )
            drain(encoder, muxer, endOfStream = false)
        }
    }

    /**
     * Signals end of stream, retrying until an input buffer is free.
     *
     * Giving up on the first failed dequeue would leave the encoder never told
     * the stream had ended — and the final drain waits for exactly that flag,
     * so the export would hang instead of finishing.
     */
    private fun signalEnd(encoder: MediaCodec, frame: Long): Boolean {
        repeat(END_OF_STREAM_ATTEMPTS) {
            val index = encoder.dequeueInputBuffer(TIMEOUT_US)
            if (index >= 0) {
                encoder.queueInputBuffer(
                    index,
                    0,
                    0,
                    frame * 1_000_000L / SAMPLE_RATE,
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                )
                return true
            }
        }
        Log.w(TAG, "Audio encoder never freed an input buffer for end of stream")
        return false
    }

    private fun drain(encoder: MediaCodec, muxer: ExportMuxer, endOfStream: Boolean) {
        while (true) {
            val index = encoder.dequeueOutputBuffer(
                bufferInfo,
                if (endOfStream) TIMEOUT_US else 0L,
            )
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!endOfStream) return

                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (trackIndex < 0) trackIndex = muxer.addTrack(encoder.outputFormat)
                }

                index < 0 -> Unit

                else -> {
                    val encoded = encoder.getOutputBuffer(index)
                    val isConfig =
                        bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (encoded != null && !isConfig && bufferInfo.size > 0) {
                        encoded.position(bufferInfo.offset)
                        encoded.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSample(trackIndex, encoded, bufferInfo)
                        samplesWritten++
                        bytesWritten += bufferInfo.size
                    }
                    encoder.releaseOutputBuffer(index, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    /** Opens a reader per audible clip and per imported track. */
    private fun buildSources(): List<Source> {
        val sources = mutableListOf<Source>()
        skipped.clear()

        for (clip in clips) {
            if (clip.isImage) {
                skipped += "${clip.id}:image"
                continue
            }
            if (masterVolume <= 0.0) {
                skipped += "muted"
                continue
            }
            // **A clip keyframed up from silence is not a silent clip.** The
            // old check read a plain number; on a fade-in from 0 the base value
            // *is* 0, so reading `baseValue` here would skip the whole clip and
            // export it with no sound at all. Only a flat, genuinely silent
            // parameter is worth skipping — the saving is one decoder.
            if (!clip.volume.isAnimated && clip.volume.baseValue <= 0.0) {
                skipped += "${clip.id}:vol0"
                continue
            }
            if (!File(clip.playbackVideoPath).exists()) {
                skipped += "${clip.id}:missing"
                continue
            }

            val reader = PcmAudioSource(clip.playbackVideoPath, clip.speed, SAMPLE_RATE)
            if (!reader.open()) {
                skipped += (reader.failureReason ?: "${clip.id}:openFailed")
                continue
            }
            reader.seekTo((clip.sourceStart * 1_000_000L).toLong())

            sources.add(
                Source(
                    reader = reader,
                    timelineStart = clip.timelineStart,
                    timelineEnd = clip.timelineEnd,
                    // Resolved per block at the clip's own progress, so a
                    // keyframed fade lands in the file where it does on the
                    // canvas. The equal-power transition crossfade rides on top
                    // rather than replacing it.
                    gainAt = { t ->
                        masterVolume *
                            clip.volumeAt(clip.clipProgressAt(t)) *
                            crossfadeGain(clip, t)
                    },
                ),
            )
        }

        for (track in audioTracks) {
            if (track.volume <= 0.0) continue
            if (!File(track.filePath).exists()) continue

            val reader = PcmAudioSource(track.filePath, 1.0, SAMPLE_RATE)
            if (!reader.open()) continue
            reader.seekTo((track.sourceStart * 1_000_000L).toLong())

            sources.add(
                Source(
                    reader = reader,
                    timelineStart = track.timelineStart,
                    timelineEnd = track.timelineEnd,
                    gainAt = { track.volume },
                ),
            )
        }

        return sources
    }

    /**
     * Equal-power crossfade factor for [clip] at [t].
     *
     * `cos`/`sin` rather than a linear ramp: two linearly faded sources sum to
     * roughly 70% power at the midpoint, which is audible as a dip every time a
     * transition passes.
     */
    private fun crossfadeGain(clip: NativeTimelineClip, t: Double): Double {
        val window = transitions.firstOrNull { it.contains(t) } ?: return 1.0
        val progress = window.progressAt(t).toDouble()

        val outgoing = clips.getOrNull(window.leftClipIndex)
        val incoming = clips.getOrNull(window.rightClipIndex)

        return when (clip.id) {
            outgoing?.id -> cos(progress * PI / 2.0)
            incoming?.id -> sin(progress * PI / 2.0)
            else -> 1.0
        }
    }

    private companion object {
        const val TAG = "SlimshotExport"
        const val SAMPLE_RATE = 44100
        const val CHANNELS = 2
        const val BIT_RATE = 128_000
        const val BLOCK_FRAMES = 1024
        const val TIMEOUT_US = 10_000L
        const val PCM_16_SCALE = 32768f
        const val END_OF_STREAM_ATTEMPTS = 50

        /** ~0.23s of audio per report: often enough to read as continuous. */
        const val PROGRESS_EVERY_BLOCKS = 10
    }
}
