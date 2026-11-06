package com.techfamz.slimshotai.camera.react

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The live reaction's sound, stereo 16-bit PCM in, AAC into [ReactMuxer].
 * Every sample's time comes from the frames written so far, never a clock,
 * so the sound's timing in the file is exact: frame `n` is at `n / rate`.
 */
@UnstableApi
internal class ReactAacEncoder(private val muxer: ReactMuxer, private val sampleRate: Int) {

    private val codec: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
    private val info = MediaCodec.BufferInfo()
    private var track = -1
    private var framesWritten = 0L
    private var pcm: ByteBuffer = ByteBuffer.allocateDirect(0)

    init {
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, CHANNELS).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, MAX_INPUT_BYTES)
        }
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
        } catch (error: Exception) {
            codec.release()
            throw error
        }
    }

    /** Encodes [frames] interleaved stereo frames of [samples]. */
    fun write(samples: ShortArray, frames: Int) {
        val bytes = frames * CHANNELS * 2
        if (pcm.capacity() < bytes) pcm = ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder())
        pcm.clear()
        pcm.asShortBuffer().put(samples, 0, frames * CHANNELS)
        pcm.limit(bytes)
        while (pcm.hasRemaining()) {
            val index = codec.dequeueInputBuffer(WAIT_US)
            if (index < 0) {
                drain(false)
                continue
            }
            val input = codec.getInputBuffer(index) ?: continue
            input.clear()
            val frameBytes = CHANNELS * 2
            val size = (minOf(input.remaining(), pcm.remaining()) / frameBytes) * frameBytes
            val slice = pcm.slice()
            slice.limit(size)
            input.put(slice)
            pcm.position(pcm.position() + size)
            codec.queueInputBuffer(index, 0, size, framesWritten * 1_000_000L / sampleRate, 0)
            framesWritten += size / frameBytes
            drain(false)
        }
    }

    /** Ends the stream and waits for the encoder to give everything up. */
    fun finish() {
        var attempts = 0
        while (attempts++ < END_ATTEMPTS) {
            val index = codec.dequeueInputBuffer(WAIT_US)
            if (index >= 0) {
                codec.queueInputBuffer(
                    index,
                    0,
                    0,
                    framesWritten * 1_000_000L / sampleRate,
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                )
                break
            }
            drain(false)
        }
        drain(true)
    }

    private fun drain(endOfStream: Boolean) {
        var waits = 0
        while (true) {
            val index = codec.dequeueOutputBuffer(info, if (endOfStream) WAIT_US else 0L)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream || ++waits > END_ATTEMPTS) return
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (track < 0) track = muxer.addTrack(codec.outputFormat)
                }
                index < 0 -> Unit
                else -> {
                    val buffer = codec.getOutputBuffer(index)
                    val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (buffer != null && !config && info.size > 0) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        muxer.writeSample(track, buffer, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    fun release() {
        try {
            codec.stop()
        } catch (_: Exception) {
            // Already stopped or dead: release regardless.
        }
        codec.release()
    }

    companion object {
        const val CHANNELS = 2
        private const val BIT_RATE = 192_000
        private const val MAX_INPUT_BYTES = 16_384
        private const val WAIT_US = 10_000L
        private const val END_ATTEMPTS = 200
    }
}
