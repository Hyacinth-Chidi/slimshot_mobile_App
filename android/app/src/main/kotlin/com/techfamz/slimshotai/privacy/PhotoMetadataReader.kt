package com.techfamz.slimshotai.privacy

import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Reads the personal details a photo carries — where, on what, when, by
 * whom — for the Privacy Strip screen, through the platform's own EXIF
 * reader. The screen shows what a photo really holds rather than a fixed
 * list, and the report reads the cleaned file again to confirm it is gone.
 *
 * `ExifInterface` reads JPEG, PNG and WebP everywhere and HEIF from Android 9;
 * a file it cannot open answers an empty map — "nothing found" — never an
 * error, because the strip still runs on it.
 */
class PhotoMetadataReader : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "slimshot-photo-metadata")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "read") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("bad_args", "path is required", null)
            return
        }
        worker.execute {
            val found = read(path)
            mainHandler.post { result.success(found) }
        }
    }

    @Suppress("DEPRECATION") // getLatLong(FloatArray) is the API-24 route.
    private fun read(path: String): Map<String, Any> {
        return try {
            val exif = ExifInterface(path)
            val found = HashMap<String, Any>()
            val latLong = FloatArray(2)
            if (exif.getLatLong(latLong)) {
                found["latitude"] = latLong[0].toDouble()
                found["longitude"] = latLong[1].toDouble()
            }
            exif.getAttribute(ExifInterface.TAG_MAKE)?.let { found["make"] = it }
            exif.getAttribute(ExifInterface.TAG_MODEL)?.let { found["model"] = it }
            (exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                ?: exif.getAttribute(ExifInterface.TAG_DATETIME))
                ?.let { found["dateTaken"] = it }
            exif.getAttribute(ExifInterface.TAG_ARTIST)?.let { found["artist"] = it }
            found
        } catch (error: Exception) {
            Log.w(TAG, "No metadata read from $path: ${error.message}")
            emptyMap()
        }
    }

    fun release() {
        worker.shutdownNow()
    }

    companion object {
        const val channelName = "slimshot_ai/photo_metadata"
        private const val TAG = "SlimshotPrivacy"
    }
}
