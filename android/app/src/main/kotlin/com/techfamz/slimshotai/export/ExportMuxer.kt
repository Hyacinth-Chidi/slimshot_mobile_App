package com.techfamz.slimshotai.export

import android.media.MediaCodec
import android.media.MediaFormat
import android.util.Log
import androidx.media3.common.util.MediaFormatUtil
import androidx.media3.common.util.UnstableApi
import androidx.media3.muxer.BufferInfo as MuxerBufferInfo
import androidx.media3.muxer.Mp4Muxer
import androidx.media3.muxer.Muxer
import java.io.FileOutputStream
import java.nio.ByteBuffer

/**
 * Writes the exported tracks into an MP4.
 *
 * Uses Media3's own muxer rather than the platform `MediaMuxer`. Transformer
 * cannot be our export engine — its composition model cannot express a
 * two-texture shader blend, so it cannot draw our transitions — but its muxer
 * is a separate, standalone library and there is no reason to hand-roll around
 * the platform one when Google's handles the device quirks, B-frames and edit
 * lists for us.
 *
 * The wrapper exists for one rule the muxer enforces at runtime: **no sample
 * may be written until every track has been added.** The video and audio
 * encoders each publish their real output format only after producing their
 * first frame, and they do not do it at the same moment. Left unguarded that
 * either throws or silently drops the samples produced before the second track
 * appeared — a file that exports missing its first second of audio.
 *
 * [expectedTracks] tells it how many to wait for.
 */
@UnstableApi
internal class ExportMuxer(outputPath: String, private val expectedTracks: Int) {

    private val stream = FileOutputStream(outputPath)
    private val muxer: Muxer = Mp4Muxer.Builder(stream).build()

    /** Samples produced before every track was added, held rather than dropped. */
    private val pending = mutableListOf<PendingSample>()

    private var addedTracks = 0
    private var started = false
    private var closed = false

    private class PendingSample(
        val trackIndex: Int,
        val buffer: ByteBuffer,
        val info: MuxerBufferInfo,
    )

    /**
     * The encoders hand back the platform's `BufferInfo`; Media3's muxer takes
     * its own. Converted here so the rest of the export code keeps talking to
     * `MediaCodec` in `MediaCodec`'s own terms.
     */
    private fun MediaCodec.BufferInfo.toMuxerInfo(): MuxerBufferInfo {
        return MuxerBufferInfo(presentationTimeUs, size, flags)
    }

    @Synchronized
    fun addTrack(format: MediaFormat): Int {
        check(!started) { "Cannot add a track after writing has begun." }
        val index = muxer.addTrack(MediaFormatUtil.createFormatFromMediaFormat(format))
        addedTracks++
        if (addedTracks >= expectedTracks) {
            started = true
            flushPending()
        }
        return index
    }

    /**
     * Writes one encoded sample, or holds it until the muxer is ready.
     *
     * Held rather than dropped: the frames an encoder produces while the other
     * encoder is still starting up are real content, and discarding them is
     * what makes an export begin a beat late.
     */
    @Synchronized
    fun writeSample(
        trackIndex: Int,
        buffer: ByteBuffer,
        info: MediaCodec.BufferInfo,
    ) {
        if (closed || trackIndex < 0) return

        if (!started) {
            // The encoder reuses its buffers, so the bytes have to be copied
            // before they can be held.
            val copy = ByteBuffer.allocateDirect(info.size).apply {
                put(buffer.duplicate())
                flip()
            }
            pending.add(PendingSample(trackIndex, copy, info.toMuxerInfo()))
            return
        }

        muxer.writeSampleData(trackIndex, buffer, info.toMuxerInfo())
    }

    private fun flushPending() {
        var written = 0
        var rejected = 0
        for (sample in pending) {
            try {
                muxer.writeSampleData(sample.trackIndex, sample.buffer, sample.info)
                written++
            } catch (error: Exception) {
                rejected++
                if (rejected == 1) {
                    Log.w(TAG, "Muxer rejected a held sample", error)
                }
            }
        }
        Log.i(TAG, "muxer started: flushed $written held sample(s), $rejected rejected")
        pending.clear()
    }

    @Synchronized
    fun close() {
        if (closed) return
        closed = true
        try {
            muxer.close()
        } catch (error: Exception) {
            Log.w(TAG, "Muxer close failed", error)
        }
        try {
            stream.close()
        } catch (_: Exception) {
            // The muxer owns the file; a close failure here changes nothing.
        }
    }

    private companion object {
        const val TAG = "SlimshotExport"
    }
}
