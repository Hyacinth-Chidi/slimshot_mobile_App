package com.techfamz.slimshotai.audio

import android.os.Handler
import android.os.Looper
import androidx.media3.common.util.UnstableApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * `slimshot_ai/voice_recorder`: one take at a time.
 *
 * - `open({outputPath})` → `{sampleRate}`; error `recorder_unavailable`.
 * - `setCapturing({capturing})` → `{capturedMs}` — answered at once on the
 *   main thread, because when it lands is when the take starts or stops.
 * - `close({keep})` → `{path, durationMs}` for a kept take, else `{}`.
 */
@UnstableApi
class VoiceRecorderChannel : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "slimshot-voice-channel")
    }

    @Volatile
    private var recorder: VoiceRecorder? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> {
                val outputPath = call.argument<String>("outputPath")
                if (outputPath.isNullOrEmpty()) {
                    result.error("bad_args", "outputPath is required", null)
                    return
                }
                worker.execute {
                    recorder?.let { runCatching { it.close(keep = false) } }
                    recorder = null
                    try {
                        val opened = VoiceRecorder.open(outputPath)
                        recorder = opened
                        mainHandler.post { result.success(mapOf("sampleRate" to opened.sampleRate)) }
                    } catch (error: Exception) {
                        val message = error.message ?: "The microphone is in use or unavailable."
                        mainHandler.post { result.error("recorder_unavailable", message, null) }
                    }
                }
            }

            "setCapturing" -> {
                val current = recorder
                current?.setCapturing(
                    on = call.argument<Boolean>("capturing") ?: false,
                    alignMs = call.argument<Number>("alignMs")?.toLong(),
                )
                result.success(mapOf("capturedMs" to (current?.capturedMs ?: 0L)))
            }

            "close" -> {
                val keep = call.argument<Boolean>("keep") ?: false
                val current = recorder
                recorder = null
                if (current == null) {
                    result.success(emptyMap<String, Any>())
                    return
                }
                current.setCapturing(on = false, alignMs = null)
                worker.execute {
                    try {
                        val take = current.close(keep)
                        val answer: Map<String, Any> = if (take == null) {
                            emptyMap()
                        } else {
                            mapOf("path" to take.first, "durationMs" to take.second)
                        }
                        mainHandler.post { result.success(answer) }
                    } catch (error: Exception) {
                        val message = error.message ?: "The recording could not be saved."
                        mainHandler.post { result.error("recorder_unavailable", message, null) }
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    fun release() {
        recorder?.let { runCatching { it.close(keep = false) } }
        recorder = null
        worker.shutdownNow()
    }

    companion object {
        const val channelName = "slimshot_ai/voice_recorder"
    }
}
