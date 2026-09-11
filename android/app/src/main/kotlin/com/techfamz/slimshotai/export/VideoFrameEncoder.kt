package com.techfamz.slimshotai.export

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.util.Log
import android.view.Surface
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer

/**
 * Hardware H.264 encoder fed by a GL surface.
 *
 * Export renders through the preview's own shader into [inputSurface], so an
 * exported frame is the previewed frame — there is no second implementation of
 * transitions, fitting, cropping or grading to drift out of step.
 *
 * Encoding is on hardware, which is the whole point of leaving FFmpeg alone
 * here: `libx264` would be markedly slower on exactly the low-end devices this
 * app targets.
 *
 * The caller drives it: render a frame, call [drainTo], repeat; then
 * [signalEndOfStream] and drain until [isFinished].
 */
@UnstableApi
internal class VideoFrameEncoder(
    width: Int,
    height: Int,
    frameRate: Int,
    bitRate: Int,
) {

    private val codec: MediaCodec
    private val bufferInfo = MediaCodec.BufferInfo()

    /** The GL window surface is created over this. */
    val inputSurface: Surface

    /** Muxer track index, assigned when the encoder reports its real format. */
    var trackIndex: Int = -1
        private set

    var isFinished: Boolean = false
        private set

    init {
        val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL_SECONDS)
        }

        codec = MediaCodec.createEncoderByType(MIME_TYPE)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        inputSurface = codec.createInputSurface()
        codec.start()
    }

    /**
     * Moves whatever the encoder has finished into the muxer.
     *
     * Called after every rendered frame. The encoder runs behind the renderer,
     * so most calls take nothing out; that is expected, not a stall.
     */
    fun drainTo(muxer: ExportMuxer, endOfStream: Boolean) {
        while (true) {
            val index = codec.dequeueOutputBuffer(
                bufferInfo,
                if (endOfStream) DRAIN_TIMEOUT_US else 0L,
            )

            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    // Nothing ready. While finishing we have to keep waiting:
                    // the end-of-stream flag has not come back yet.
                    if (!endOfStream) return
                }

                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    check(trackIndex < 0) { "Encoder format changed twice." }
                    trackIndex = muxer.addTrack(codec.outputFormat)
                }

                index < 0 -> Log.w(TAG, "Unexpected encoder status $index")

                else -> {
                    val encoded: ByteBuffer = codec.getOutputBuffer(index)
                        ?: throw IllegalStateException("Encoder returned no buffer for $index")

                    // Codec config bytes belong in the track format, which the
                    // muxer already took; writing them again corrupts the file.
                    val isConfig =
                        bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (!isConfig && bufferInfo.size > 0) {
                        encoded.position(bufferInfo.offset)
                        encoded.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSample(trackIndex, encoded, bufferInfo)
                    }

                    codec.releaseOutputBuffer(index, false)

                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        isFinished = true
                        return
                    }
                }
            }
        }
    }

    fun signalEndOfStream() {
        codec.signalEndOfInputStream()
    }

    fun release() {
        try {
            codec.stop()
        } catch (error: Exception) {
            Log.w(TAG, "Encoder stop failed", error)
        }
        codec.release()
        inputSurface.release()
    }

    companion object {
        private const val TAG = "SlimshotExport"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val I_FRAME_INTERVAL_SECONDS = 1
        private const val DRAIN_TIMEOUT_US = 10_000L

        /**
         * Bitrate for a given frame size, at roughly 0.12 bits per pixel per
         * frame — enough for clean short-form video without producing files
         * that are painful to upload from a phone.
         */
        fun bitRateFor(width: Int, height: Int, frameRate: Int): Int {
            val estimate = (width.toLong() * height * frameRate * 0.12).toInt()
            return estimate.coerceIn(2_000_000, 16_000_000)
        }
    }
}
