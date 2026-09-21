package com.techfamz.slimshotai.export

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import android.view.Surface

/**
 * Decodes one clip into a lane's surface, stepped by the export clock.
 *
 * This is why export cannot reuse `TimelinePlaybackEngine`: ExoPlayer plays in
 * realtime by design, and an export that took as long as the video would be
 * worse than the one we are replacing. Here the caller owns the clock — it asks
 * for the frame at a given source position and the decoder runs as fast as the
 * hardware allows to produce it.
 *
 * One instance per lane. Frames land in the lane's `SurfaceTexture`, exactly
 * where ExoPlayer puts them during preview, so the compositor cannot tell the
 * difference between a previewed frame and an exported one.
 */
internal class ExportClipDecoder(
    private val path: String,
    private val outputSurface: Surface,
) {

    private var extractor: MediaExtractor? = null
    private var codec: MediaCodec? = null
    private val bufferInfo = MediaCodec.BufferInfo()

    /** Presentation time of the frame currently in the surface, in µs. */
    var lastRenderedUs: Long = -1L
        private set

    /** True once the extractor and decoder have both run dry. */
    var isFinished: Boolean = false
        private set

    /**
     * The codec reported an error and can do nothing more.
     *
     * **Device-reported as a fatal crash.** A `MediaCodec` that reports an
     * error moves to an error state and every later call throws
     * `IllegalStateException`; there is no recovering it, only replacing it.
     * On the export's own thread that surfaced as a caught failure, but the
     * preview steps this decoder on a `HandlerThread`, where an uncaught
     * exception **kills the process**:
     *
     * ```
     * FATAL EXCEPTION: slimshot-overlay-decode
     *   at MediaCodec.releaseOutputBuffer(Native Method)
     *   at ExportClipDecoder.advanceTo, at RealtimeOverlayDecoder.pump
     * ```
     *
     * The log also shows `keep callback message for reclaim` — the system's
     * resource manager taking a codec away from us under pressure, which can
     * happen at any time and is not ours to prevent. So a dead codec has to be
     * an outcome the caller handles, not an exception nobody catches: the
     * overlay stops and the user is told, the way a transition lane that
     * cannot come up already does.
     */
    var failed: Boolean = false
        private set

    private var inputDone = false

    /** MIME of the video track, for reporting an unsupported file by name. */
    var mimeType: String? = null
        private set

    /**
     * The picture's on-screen shape, with any rotation tag already applied.
     *
     * Phone footage commonly stores landscape pixels plus a 90° rotation tag;
     * fitting an overlay by the raw dimensions would letterbox it sideways.
     */
    var displayAspect: Double = 0.0
        private set

    /**
     * Opens the clip with the extractor already positioned at the sync sample
     * at or before [startUs].
     *
     * The seek happens **before the codec starts, so nothing is flushed.**
     * The old shape — open, then `seekTo` (which flushes) — raced a documented
     * `MediaCodec` pitfall: a flush immediately after `start()` can discard
     * the codec-specific data (SPS/PPS) on some implementations, and a decoder
     * without its CSD silently consumes the whole file producing no output.
     * No error, no failed open — just a clip whose audio played while its
     * video never appeared, and which clip lost the race varied run to run.
     */
    fun open(startUs: Long): Boolean {
        return try {
            val ex = MediaExtractor()
            ex.setDataSource(path)

            var trackIndex = -1
            var format: MediaFormat? = null
            for (i in 0 until ex.trackCount) {
                val candidate = ex.getTrackFormat(i)
                val mime = candidate.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/")) {
                    trackIndex = i
                    format = candidate
                    mimeType = mime
                    break
                }
            }

            if (trackIndex < 0 || format == null) {
                Log.w(TAG, "No video track in $path")
                ex.release()
                return false
            }

            if (!ExportCapabilities.canDecode(mimeType)) {
                Log.w(TAG, "No decoder on this device for $mimeType ($path)")
                ex.release()
                return false
            }

            ex.selectTrack(trackIndex)
            ex.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            val width = if (format.containsKey(MediaFormat.KEY_WIDTH)) {
                format.getInteger(MediaFormat.KEY_WIDTH)
            } else 0
            val height = if (format.containsKey(MediaFormat.KEY_HEIGHT)) {
                format.getInteger(MediaFormat.KEY_HEIGHT)
            } else 0
            val rotation = if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                format.getInteger(MediaFormat.KEY_ROTATION)
            } else 0
            displayAspect = if (width > 0 && height > 0) {
                if (rotation % 180 != 0) {
                    height.toDouble() / width
                } else {
                    width.toDouble() / height
                }
            } else 0.0

            val decoder = MediaCodec.createDecoderByType(mimeType!!)
            decoder.configure(format, outputSurface, null, 0)
            decoder.start()

            extractor = ex
            codec = decoder
            true
        } catch (error: Exception) {
            Log.e(TAG, "Failed to open $path", error)
            release()
            false
        }
    }

    /**
     * Seeks to the sync sample at or before [sourceUs]. **Mid-stream only** —
     * a clip's opening position goes through [open], because the flush here is
     * only safe once the codec has produced output (see [open] for the CSD
     * race a flush-after-start loses).
     *
     * `SEEK_TO_PREVIOUS_SYNC` then decoding forward is the only way to land on
     * an exact frame: seeking to the closest sync sample instead would start the
     * clip on the wrong frame, and a trim that begins mid-GOP is the normal
     * case rather than the exception.
     */
    fun seekTo(sourceUs: Long) {
        val ex = extractor ?: return
        val decoder = codec ?: return
        try {
            ex.seekTo(sourceUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            decoder.flush()
            inputDone = false
            isFinished = false
            lastRenderedUs = -1L
        } catch (error: Exception) {
            Log.w(TAG, "Seek to ${sourceUs}us failed on $path", error)
        }
    }

    /**
     * Decodes until the surface holds the frame for [targetUs].
     *
     * Frames before the target are decoded and **dropped without rendering** —
     * that is the decode-forward part of an exact seek, and rendering them would
     * push the wrong picture into the lane. Returns true if a new frame was
     * rendered, false if the frame already on the lane is the one due.
     */
    fun advanceTo(targetUs: Long): Boolean {
        val decoder = codec ?: return false
        if (isFinished || failed) return false

        // The frame already on the lane may still be the one this output frame
        // wants, and then nothing should be decoded.
        //
        // Without this the loop below always dequeues a fresh output buffer, so
        // it consumes exactly **one source frame per output frame** whatever the
        // timestamps say. A source slower than the export rate — 24fps footage
        // exported at 30 — therefore runs a quarter faster than it should and
        // reaches its last frame a quarter of the way early, and a spent decoder
        // returns false from here forever: the clip freezes on one frame for the
        // rest of its span while everything around it stays correct.
        if (lastRenderedUs >= 0L && lastRenderedUs >= targetUs) return false

        var rendered = false
        var guard = 0

        // **Nothing in this loop may throw past this point.** See [failed]:
        // every call below is illegal once the codec has reported an error or
        // been reclaimed, and this runs on a thread where that is fatal.
        try {
        while (!rendered && guard++ < MAX_STEPS_PER_FRAME) {
            feedInput(decoder)

            val index = decoder.dequeueOutputBuffer(bufferInfo, DEQUEUE_TIMEOUT_US)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (inputDone) {
                        // Nothing left to come; the clip is spent.
                        isFinished = true
                        return false
                    }
                }

                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit

                index < 0 -> Unit

                else -> {
                    val isEnd =
                        bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0

                    // Render only the frame that is due. Anything earlier is
                    // decoded purely to get here and must not reach the lane.
                    val show = bufferInfo.presentationTimeUs >= targetUs || isEnd
                    decoder.releaseOutputBuffer(index, show)

                    if (show) {
                        lastRenderedUs = bufferInfo.presentationTimeUs
                        rendered = true
                    }
                    if (isEnd) {
                        isFinished = true
                        return rendered
                    }
                }
            }
        }
        } catch (error: IllegalStateException) {
            // The codec is gone — reclaimed, or failed mid-frame. Its own
            // buffers are already invalid, so there is nothing to hand back.
            Log.w(TAG, "Decoder failed mid-frame for $path", error)
            failed = true
            return false
        }

        return rendered
    }

    private fun feedInput(decoder: MediaCodec) {
        if (inputDone) return
        val ex = extractor ?: return

        val index = decoder.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
        if (index < 0) return

        val buffer = decoder.getInputBuffer(index) ?: return
        val size = ex.readSampleData(buffer, 0)

        if (size < 0) {
            decoder.queueInputBuffer(
                index,
                0,
                0,
                0,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
            )
            inputDone = true
            return
        }

        decoder.queueInputBuffer(index, 0, size, ex.sampleTime, 0)
        ex.advance()
    }

    fun release() {
        try {
            codec?.stop()
        } catch (_: Exception) {
            // Already in a bad state; releasing is all that is left.
        }
        codec?.release()
        codec = null
        extractor?.release()
        extractor = null
    }

    private companion object {
        const val TAG = "SlimshotExport"
        const val DEQUEUE_TIMEOUT_US = 10_000L

        /**
         * Ceiling on decode steps per output frame.
         *
         * A long GOP can need many decodes to reach one displayed frame after a
         * seek, but an unbounded loop on a malformed file would hang the export
         * with no way out.
         */
        const val MAX_STEPS_PER_FRAME = 512
    }
}
