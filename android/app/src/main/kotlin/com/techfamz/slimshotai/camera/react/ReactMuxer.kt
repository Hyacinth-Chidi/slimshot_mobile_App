package com.techfamz.slimshotai.camera.react

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
 * Media3's `Mp4Muxer` over a stream — a gallery entry's file descriptor, so
 * the reaction is written straight into the album with no copy afterwards.
 * The export's `ExportMuxer` takes only a path and is left alone; this keeps
 * its one rule: **nothing is written until every track has been added**, and
 * samples that arrive before are held, not dropped. Video and sound come from
 * two threads, so every entry point is synchronized.
 */
@UnstableApi
internal class ReactMuxer(private val stream: FileOutputStream, private val expectedTracks: Int) {

    private val muxer: Muxer = Mp4Muxer.Builder(stream).build()
    private val pending = mutableListOf<Triple<Int, ByteBuffer, MuxerBufferInfo>>()
    private var added = 0
    private var started = false
    private var closed = false

    @Synchronized
    fun addTrack(format: MediaFormat): Int {
        check(!started) { "Cannot add a track after writing has begun." }
        val index = muxer.addTrack(MediaFormatUtil.createFormatFromMediaFormat(format))
        added++
        if (added >= expectedTracks) {
            started = true
            for ((track, buffer, info) in pending) {
                try {
                    muxer.writeSampleData(track, buffer, info)
                } catch (error: Exception) {
                    Log.w(TAG, "held sample refused", error)
                }
            }
            pending.clear()
        }
        return index
    }

    @Synchronized
    fun writeSample(track: Int, buffer: ByteBuffer, info: MediaCodec.BufferInfo) {
        if (closed || track < 0) return
        val muxerInfo = MuxerBufferInfo(info.presentationTimeUs, info.size, info.flags)
        if (!started) {
            val copy = ByteBuffer.allocateDirect(info.size).apply {
                put(buffer.duplicate())
                flip()
            }
            pending += Triple(track, copy, muxerInfo)
            return
        }
        muxer.writeSampleData(track, buffer, muxerInfo)
    }

    /** Finishes the file; false where it could not be finished. */
    @Synchronized
    fun close(): Boolean {
        if (closed) return started
        closed = true
        var ok = started
        try {
            muxer.close()
        } catch (error: Exception) {
            Log.w(TAG, "muxer close failed", error)
            ok = false
        }
        try {
            stream.close()
        } catch (_: Exception) {
            // The muxer owns the file; a close failure here changes nothing.
        }
        return ok
    }

    private companion object {
        const val TAG = "SlimshotCamera"
    }
}
