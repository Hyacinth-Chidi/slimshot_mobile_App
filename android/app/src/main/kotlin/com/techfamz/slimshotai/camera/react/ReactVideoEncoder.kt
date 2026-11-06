package com.techfamz.slimshotai.camera.react

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.util.Log
import android.view.Surface
import androidx.media3.common.util.UnstableApi

/**
 * The live reaction's H.264 encoder, fed by the recorder's GL drawing through
 * [inputSurface]. The export's `VideoFrameEncoder` drains only into the
 * export's muxer and is left alone; this is the same small loop, draining
 * into [ReactMuxer].
 */
@UnstableApi
internal class ReactVideoEncoder(width: Int, height: Int, frameRate: Int) {

    private val codec: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    private val info = MediaCodec.BufferInfo()
    val inputSurface: Surface
    private var track = -1

    var finished = false
        private set

    init {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRateFor(width, height, frameRate))
            setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = codec.createInputSurface()
            codec.start()
        } catch (error: Exception) {
            codec.release()
            throw error
        }
    }

    /** Moves what the encoder has finished into [muxer]; with [endOfStream], waits for the end. */
    fun drainTo(muxer: ReactMuxer, endOfStream: Boolean) {
        var waits = 0
        while (true) {
            val index = codec.dequeueOutputBuffer(info, if (endOfStream) WAIT_US else 0L)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream || ++waits > MAX_END_WAITS) return
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
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        finished = true
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
            Log.w("SlimshotCamera", "REACT encoder stop failed", error)
        }
        codec.release()
        inputSurface.release()
    }

    companion object {
        private const val WAIT_US = 10_000L
        private const val MAX_END_WAITS = 200

        /** About 0.12 bits a pixel a frame: clean short-form video, uploadable from a phone. */
        fun bitRateFor(width: Int, height: Int, frameRate: Int): Int =
            (width.toLong() * height * frameRate * 0.12).toInt().coerceIn(2_000_000, 16_000_000)
    }
}
