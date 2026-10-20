package com.techfamz.slimshotai.audio

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.export.ExportMuxer
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 16-bit PCM in, an AAC `.m4a` out — for a video's sound that cannot be
 * copied as it is, and for a recorded voiceover.
 *
 * The export's own encoder in `AudioExportMixer` is deliberately left alone:
 * it is device-verified, and this is a second, small user of the same codec
 * setup rather than a refactor of the app's most important operation.
 *
 * Every sample's timestamp is worked out from the frames written so far, never
 * from a clock, so the file's timing is exact however fast it is written.
 */
@UnstableApi
internal class AacFileEncoder(
    private val outputPath: String,
    private val sampleRate: Int,
    private val channels: Int,
    bitRate: Int = 128_000,
) {
    private val muxer = ExportMuxer(outputPath, 1)
    private val encoder: MediaCodec
    private val info = MediaCodec.BufferInfo()
    private var trackIndex = -1
    private var framesWritten = 0L
    private var done = false
    private var pcm: ByteBuffer = ByteBuffer.allocateDirect(0)

    init {
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        try {
            val format = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC,
                sampleRate,
                channels,
            ).apply {
                setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
                setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC,
                )
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, MAX_INPUT_BYTES)
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
        } catch (error: Exception) {
            codec.release()
            muxer.close()
            File(outputPath).delete()
            throw error
        }
        encoder = codec
    }

    /** Frames written so far. */
    val frames: Long get() = framesWritten

    /** Encodes [count] interleaved 16-bit samples from [samples]. */
    fun write(samples: ShortArray, count: Int) {
        check(!done) { "Encoder already finished" }
        if (count <= 0) return
        val bytes = count * 2
        if (pcm.capacity() < bytes) {
            pcm = ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder())
        }
        pcm.clear()
        for (i in 0 until count) pcm.putShort(samples[i])
        pcm.flip()

        val frameBytes = channels * 2
        while (pcm.remaining() >= frameBytes) {
            val index = encoder.dequeueInputBuffer(TIMEOUT_US)
            if (index < 0) {
                drain(endOfStream = false)
                continue
            }
            val input = encoder.getInputBuffer(index) ?: return
            input.clear()
            // Whole frames only, so the next buffer's timestamp is exact.
            val size = (minOf(input.remaining(), pcm.remaining()) / frameBytes) * frameBytes
            val slice = pcm.slice()
            slice.limit(size)
            input.put(slice)
            pcm.position(pcm.position() + size)
            encoder.queueInputBuffer(
                index,
                0,
                size,
                PcmFrames.usForFrames(framesWritten, sampleRate),
                0,
            )
            framesWritten += size / frameBytes
            drain(endOfStream = false)
        }
    }

    /** Ends the stream and closes the file. Returns the frames written. */
    fun finish(): Long {
        if (done) return framesWritten
        done = true
        try {
            if (signalEnd()) drain(endOfStream = true)
        } finally {
            releaseCodec()
            muxer.close()
        }
        return framesWritten
    }

    /** Stops without keeping anything: the file is deleted. */
    fun abandon() {
        if (!done) {
            done = true
            releaseCodec()
            muxer.close()
        }
        File(outputPath).delete()
    }

    private fun releaseCodec() {
        try {
            encoder.stop()
        } catch (error: Exception) {
            Log.w(TAG, "AAC encoder stop failed", error)
        }
        encoder.release()
    }

    /** Retries until an input buffer is free, or the final drain waits for ever. */
    private fun signalEnd(): Boolean {
        repeat(END_OF_STREAM_ATTEMPTS) {
            val index = encoder.dequeueInputBuffer(TIMEOUT_US)
            if (index >= 0) {
                encoder.queueInputBuffer(
                    index,
                    0,
                    0,
                    PcmFrames.usForFrames(framesWritten, sampleRate),
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                )
                return true
            }
            drain(endOfStream = false)
        }
        Log.w(TAG, "AAC encoder never freed an input buffer for end of stream")
        return false
    }

    private fun drain(endOfStream: Boolean) {
        while (true) {
            val index = encoder.dequeueOutputBuffer(info, if (endOfStream) TIMEOUT_US else 0L)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!endOfStream) return
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (trackIndex < 0) trackIndex = muxer.addTrack(encoder.outputFormat)
                }
                index < 0 -> Unit
                else -> {
                    val encoded = encoder.getOutputBuffer(index)
                    val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (encoded != null && !isConfig && info.size > 0) {
                        encoded.position(info.offset)
                        encoded.limit(info.offset + info.size)
                        muxer.writeSample(trackIndex, encoded, info)
                    }
                    encoder.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    private companion object {
        const val TAG = "SlimshotAudio"
        const val TIMEOUT_US = 10_000L
        const val END_OF_STREAM_ATTEMPTS = 50
        const val MAX_INPUT_BYTES = 16_384
    }
}
