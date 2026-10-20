package com.techfamz.slimshotai.audio

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.export.ExportMuxer
import com.techfamz.slimshotai.export.PcmAudioSource
import java.io.File
import java.nio.ByteBuffer

/**
 * Takes the sound out of a video into an `.m4a` of its own, and reduces a
 * sound to the peaks the Extract sheet draws.
 *
 * **Copied, not converted, wherever it can be** ([ExtractPlan.canRemux]):
 * almost every phone video carries AAC, and its samples go into the new file
 * unchanged — near-instant at any length, the quality untouched. Anything else
 * is decoded and encoded to AAC through the export's own reader.
 *
 * The track points at this file rather than the video: playing a video only
 * for its sound would hold a video decoder open the whole time.
 */
@UnstableApi
internal object AudioExtractor {

    data class Result(val path: String, val durationMs: Long, val remuxed: Boolean)

    class ExtractFailed(message: String) : Exception(message)

    /** The new file, or null when the video has no sound. */
    fun extract(videoPath: String, outputPath: String): Result? {
        val probe = MediaExtractor()
        val audio: Pair<Int, MediaFormat>?
        try {
            probe.setDataSource(videoPath)
            audio = firstAudioTrack(probe)
        } catch (error: Exception) {
            probe.release()
            throw ExtractFailed("This video could not be opened.")
        }
        if (audio == null) {
            probe.release()
            return null
        }

        val part = File("$outputPath.part")
        part.delete()
        val mime = audio.second.getString(MediaFormat.KEY_MIME).orEmpty()
        try {
            val durationMs = if (ExtractPlan.canRemux(mime)) {
                remux(probe, audio.first, audio.second, part)
            } else {
                transcode(videoPath, part)
            }
            // A sound track with nothing in it is no sound.
            if (durationMs == null) {
                part.delete()
                return null
            }
            val target = File(outputPath)
            target.delete()
            if (!part.renameTo(target)) throw ExtractFailed("The sound could not be saved.")
            return Result(target.path, durationMs, ExtractPlan.canRemux(mime))
        } catch (error: Exception) {
            part.delete()
            Log.w(TAG, "extract failed for $videoPath ($mime)", error)
            if (error is ExtractFailed) throw error
            throw ExtractFailed("The sound could not be taken out of this video.")
        } finally {
            try {
                probe.release()
            } catch (_: Exception) {
            }
        }
    }

    /** [count] peaks of [path]'s sound, each 0..1. */
    fun peaks(path: String, count: Int): DoubleArray {
        val probe = MediaExtractor()
        val format = try {
            probe.setDataSource(path)
            firstAudioTrack(probe)?.second
        } catch (error: Exception) {
            null
        } finally {
            probe.release()
        } ?: return DoubleArray(count)

        val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val durationUs =
            if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
        val totalFrames = durationUs * rate / 1_000_000L
        if (totalFrames <= 0) return DoubleArray(count)

        val source = PcmAudioSource(path, 1.0, rate)
        if (!source.open()) return DoubleArray(count)
        try {
            val acc = WaveformPeaks.Accumulator(totalFrames, count)
            val block = FloatArray(BLOCK_FRAMES * 2)
            while (true) {
                val read = source.read(block, 0, BLOCK_FRAMES)
                if (read <= 0) break
                acc.add(block, read, 2)
                if (read < BLOCK_FRAMES) break
            }
            return acc.result()
        } finally {
            source.release()
        }
    }

    private fun firstAudioTrack(extractor: MediaExtractor): Pair<Int, MediaFormat>? {
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            if (format.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                return i to format
            }
        }
        return null
    }

    /**
     * Copies the AAC samples unchanged, starting the file at 0. Returns its
     * length, or null when the track holds no samples.
     */
    private fun remux(extractor: MediaExtractor, track: Int, format: MediaFormat, out: File): Long? {
        extractor.selectTrack(track)
        val muxer = ExportMuxer(out.path, 1)
        try {
            val index = muxer.addTrack(format)
            val capacity = if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE).coerceAtLeast(MIN_SAMPLE_BYTES)
            } else {
                MAX_SAMPLE_BYTES
            }
            val buffer = ByteBuffer.allocateDirect(capacity)
            val info = MediaCodec.BufferInfo()
            var first = -1L
            var last = 0L
            while (true) {
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val time = extractor.sampleTime
                if (first < 0) first = time
                last = time - first
                val flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                } else {
                    0
                }
                info.set(0, size, last, flags)
                buffer.position(0)
                buffer.limit(size)
                muxer.writeSample(index, buffer, info)
                extractor.advance()
            }
            if (first < 0) return null
            val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            // The last sample's start plus one AAC frame.
            return (last + AAC_FRAME_SAMPLES * 1_000_000L / rate) / 1000L
        } finally {
            muxer.close()
        }
    }

    /** Decodes and encodes to AAC. Returns the file's length, or null when silent-empty. */
    private fun transcode(videoPath: String, out: File): Long? {
        val source = PcmAudioSource(videoPath, 1.0, TRANSCODE_RATE)
        if (!source.open()) {
            throw ExtractFailed("The sound in this video could not be read.")
        }
        val encoder = AacFileEncoder(out.path, TRANSCODE_RATE, 2)
        try {
            val block = FloatArray(BLOCK_FRAMES * 2)
            val shorts = ShortArray(BLOCK_FRAMES * 2)
            while (true) {
                val read = source.read(block, 0, BLOCK_FRAMES)
                if (read <= 0) break
                PcmFrames.floatToShort(block, read * 2, shorts)
                encoder.write(shorts, read * 2)
                if (read < BLOCK_FRAMES) break
            }
            val frames = encoder.finish()
            if (frames == 0L) return null
            return PcmFrames.usForFrames(frames, TRANSCODE_RATE) / 1000L
        } catch (error: Exception) {
            encoder.abandon()
            throw error
        } finally {
            source.release()
        }
    }

    private const val TAG = "SlimshotAudio"
    private const val BLOCK_FRAMES = 4096
    private const val TRANSCODE_RATE = 44_100
    private const val AAC_FRAME_SAMPLES = 1024
    private const val MIN_SAMPLE_BYTES = 8 * 1024
    private const val MAX_SAMPLE_BYTES = 256 * 1024
}
