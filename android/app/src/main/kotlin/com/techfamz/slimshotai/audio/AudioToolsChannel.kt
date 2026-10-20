package com.techfamz.slimshotai.audio

import android.os.Handler
import android.os.Looper
import androidx.media3.common.util.UnstableApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * `slimshot_ai/audio_tools`: Extract's two native calls, run off the main
 * thread one at a time and answered on it.
 *
 * - `extract({videoPath, outputPath})` → `{hasSound: false}` or
 *   `{hasSound: true, path, durationMs, remuxed}`; error `extract_failed`.
 * - `peaks({path, count})` → `count` doubles in 0..1.
 */
@UnstableApi
class AudioToolsChannel : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "slimshot-audio-tools")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "extract" -> {
                val videoPath = call.argument<String>("videoPath")
                val outputPath = call.argument<String>("outputPath")
                if (videoPath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                    result.error("bad_args", "videoPath and outputPath are required", null)
                    return
                }
                worker.execute {
                    try {
                        val extracted = AudioExtractor.extract(videoPath, outputPath)
                        val answer: Map<String, Any> = if (extracted == null) {
                            mapOf("hasSound" to false)
                        } else {
                            mapOf(
                                "hasSound" to true,
                                "path" to extracted.path,
                                "durationMs" to extracted.durationMs,
                                "remuxed" to extracted.remuxed,
                            )
                        }
                        mainHandler.post { result.success(answer) }
                    } catch (error: Exception) {
                        val message = error.message ?: "The sound could not be taken out of this video."
                        mainHandler.post { result.error("extract_failed", message, null) }
                    }
                }
            }

            "peaks" -> {
                val path = call.argument<String>("path")
                val count = call.argument<Int>("count") ?: DEFAULT_PEAKS
                if (path.isNullOrEmpty()) {
                    result.error("bad_args", "path is required", null)
                    return
                }
                worker.execute {
                    val peaks = try {
                        AudioExtractor.peaks(path, count.coerceIn(1, MAX_PEAKS)).toList()
                    } catch (error: Exception) {
                        List(count.coerceIn(1, MAX_PEAKS)) { 0.0 }
                    }
                    mainHandler.post { result.success(peaks) }
                }
            }

            else -> result.notImplemented()
        }
    }

    fun release() {
        worker.shutdownNow()
    }

    companion object {
        const val channelName = "slimshot_ai/audio_tools"
        private const val DEFAULT_PEAKS = 200
        private const val MAX_PEAKS = 2000
    }
}
