package com.techfamz.slimshotai.thumbnails

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Extracts filmstrip frames straight from the source media.
 *
 * Deliberately keyframe-accurate ([MediaMetadataRetriever.OPTION_CLOSEST_SYNC]) rather than
 * frame-exact. Exact seeking has to decode from the previous keyframe up to the requested
 * time, which is roughly an order of magnitude slower and is wasted work at filmstrip size —
 * every video editor uses sync frames for the strip and exact frames only for the preview.
 *
 * Requests are served newest-first: while the user scrubs, the tiles they are looking at now
 * matter more than tiles they scrolled past a moment ago.
 */
class VideoThumbnailProvider : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * One retriever per file. [MediaMetadataRetriever] is not thread-safe and is expensive to
     * open, so access is serialised onto a single worker and the instances are reused.
     */
    private val retrievers = ConcurrentHashMap<String, MediaMetadataRetriever>()

    /** Cached still-vs-video verdict per path, so it is decided only once. */
    private val imageFlags = ConcurrentHashMap<String, Boolean>()

    private val queue = LinkedBlockingDeque<Runnable>()
    private val running = AtomicBoolean(true)
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "slimshot-thumbnails").apply { priority = Thread.MIN_PRIORITY }
    }

    init {
        worker.execute {
            while (running.get()) {
                try {
                    // Newest request first: the visible window is what matters.
                    queue.takeLast().run()
                } catch (_: InterruptedException) {
                    return@execute
                } catch (error: Exception) {
                    Log.e(TAG, "Thumbnail job failed", error)
                }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getFrames" -> {
                val path = call.argument<String>("path")
                val timesMs = call.argument<List<Number>>("timesMs")
                if (path.isNullOrBlank() || timesMs == null) {
                    result.error("invalid_args", "path and timesMs are required.", null)
                    return
                }
                val width = call.argument<Number>("width")?.toInt() ?: DEFAULT_WIDTH
                val height = call.argument<Number>("height")?.toInt() ?: DEFAULT_HEIGHT

                queue.putLast {
                    val frames = timesMs.map { extractFrame(path, it.toLong(), width, height) }
                    mainHandler.post { result.success(frames) }
                }
            }

            "probe" -> {
                val paths = call.argument<List<String>>("paths")
                if (paths == null) {
                    result.error("invalid_args", "paths is required.", null)
                    return
                }
                queue.putLast {
                    val probes = paths.map { probe(it) }
                    mainHandler.post { result.success(probes) }
                }
            }

            "releaseSource" -> {
                val path = call.argument<String>("path")
                if (path != null) {
                    queue.putLast { closeRetriever(path) }
                }
                result.success(null)
            }

            "releaseAll" -> {
                queue.putLast { closeAllRetrievers() }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Reads what the editor needs to place a file on the timeline: how long it
     * runs, how big its frame is, and whether it carries audio.
     *
     * Rotation is applied here rather than left to callers — a portrait phone
     * video reports landscape dimensions plus a 90° rotation, and a timeline
     * that trusted the raw values would lay it out sideways.
     *
     * Returns `durationMs = 0` for a still image, which is how the Dart side
     * distinguishes a photo from a video.
     */
    private fun probe(path: String): Map<String, Any?>? {
        if (isStillImage(path)) {
            // Orientation-corrected, for the same reason the video branch below
            // swaps on a rotation tag: a portrait photo stores landscape pixels
            // plus an EXIF turn, and a timeline that trusted the raw bounds
            // would fit it into the canvas as though it were landscape.
            val bounds = StillImageDecoder.bounds(path)
            return mapOf(
                "path" to path,
                "isImage" to true,
                "durationMs" to 0L,
                "width" to (bounds?.first ?: 0),
                "height" to (bounds?.second ?: 0),
                "hasAudio" to false,
            )
        }

        val retriever = retrieverFor(path) ?: return null
        return try {
            fun meta(key: Int) = retriever.extractMetadata(key)

            val rotation = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            var width = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            var height = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) {
                val swap = width
                width = height
                height = swap
            }

            val durationMs = meta(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val hasVideo = meta(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val hasAudio = meta(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            val isImage = !hasVideo || durationMs <= 0L

            // A still needs its size from the frame itself; the video metadata
            // keys are absent for image files.
            if (isImage && (width <= 0 || height <= 0)) {
                retriever.getFrameAtTime(0L)?.let { bitmap ->
                    width = bitmap.width
                    height = bitmap.height
                    bitmap.recycle()
                }
            }

            mapOf(
                "path" to path,
                "isImage" to isImage,
                "durationMs" to if (isImage) 0L else durationMs,
                "width" to width,
                "height" to height,
                "hasAudio" to (hasAudio && !isImage),
            )
        } catch (error: Exception) {
            Log.e(TAG, "Cannot probe $path", error)
            null
        }
    }

    /**
     * Whether a path holds a still image.
     *
     * Decided once per file with a bounds-only decode, which allocates nothing.
     * [MediaMetadataRetriever] cannot read a JPEG or PNG, so a photo has to
     * take the [BitmapFactory] path instead or its filmstrip stays empty.
     */
    private fun isStillImage(path: String): Boolean {
        imageFlags[path]?.let { return it }
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, options)
        val isImage = options.outWidth > 0 && options.outHeight > 0
        imageFlags[path] = isImage
        return isImage
    }

    private fun extractFrame(
        path: String,
        timeMs: Long,
        width: Int,
        height: Int,
    ): ByteArray? {
        return try {
            if (isStillImage(path)) {
                val still = StillImageDecoder.decode(path, width, height) ?: return null
                val stream = ByteArrayOutputStream()
                still.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)
                still.recycle()
                return stream.toByteArray()
            }

            val retriever = retrieverFor(path) ?: return null
            val timeUs = timeMs * 1000L

            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    width,
                    height,
                )
            } else {
                retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?.let { scaleDown(it, width, height) }
            } ?: return null

            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)
            bitmap.recycle()
            stream.toByteArray()
        } catch (error: Exception) {
            Log.w(TAG, "No frame at ${timeMs}ms in $path: ${error.message}")
            null
        }
    }

    /** Pre-O_MR1 fallback: retrieve full size, then scale and drop the original. */
    private fun scaleDown(source: Bitmap, width: Int, height: Int): Bitmap {
        val scale = minOf(
            width.toFloat() / source.width,
            height.toFloat() / source.height,
        ).coerceAtMost(1f)
        if (scale >= 1f) return source

        val scaled = Bitmap.createScaledBitmap(
            source,
            (source.width * scale).toInt().coerceAtLeast(1),
            (source.height * scale).toInt().coerceAtLeast(1),
            true,
        )
        if (scaled !== source) source.recycle()
        return scaled
    }

    private fun retrieverFor(path: String): MediaMetadataRetriever? {
        retrievers[path]?.let { return it }
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(path)
            retrievers[path] = retriever
            retriever
        } catch (error: Exception) {
            Log.e(TAG, "Cannot open $path for thumbnails", error)
            null
        }
    }

    private fun closeRetriever(path: String) {
        retrievers.remove(path)?.let {
            try {
                it.release()
            } catch (_: Exception) {
                // Already torn down; nothing to do.
            }
        }
    }

    private fun closeAllRetrievers() {
        retrievers.keys.toList().forEach { closeRetriever(it) }
    }

    fun dispose() {
        running.set(false)
        queue.putLast { closeAllRetrievers() }
        worker.shutdownNow()
    }

    companion object {
        private const val TAG = "VideoThumbnailProvider"
        private const val JPEG_QUALITY = 72
        private const val DEFAULT_WIDTH = 160
        private const val DEFAULT_HEIGHT = 160

        const val channelName = "slimshot_ai/video_thumbnails"
    }
}
