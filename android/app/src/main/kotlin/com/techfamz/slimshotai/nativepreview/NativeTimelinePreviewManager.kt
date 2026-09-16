package com.techfamz.slimshotai.nativepreview

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.export.AudioExportMixer
import com.techfamz.slimshotai.export.ExportCapabilities
import com.techfamz.slimshotai.export.VideoExportEngine
import com.techfamz.slimshotai.nativepreview.gl.TransitionRenderer
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Bridge between Flutter and the native preview engine.
 *
 * The preview is **not** a PlatformView. It renders into a Flutter-owned
 * texture obtained from [TextureRegistry], which Flutter composites directly.
 *
 * The previous PlatformView approach used `AndroidView`, i.e. virtual display
 * mode: a `TextureView` drew into a virtual display and Flutter then copied
 * that display into its own texture every frame. That cost a full extra frame
 * copy, churned gralloc buffers on every frame, and flooded logcat with
 * `updateAcquireFence: Did not find frame`. Rendering straight into Flutter's
 * texture removes the whole extra hop — it is what `video_player` and
 * `media_kit` do.
 */
@UnstableApi
class NativeTimelinePreviewManager(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var renderer: TransitionRenderer? = null
    private var engine: TimelinePlaybackEngine? = null
    private var pendingTimeline: Map<String, Any?>? = null

    private var canvasWidth = 0
    private var canvasHeight = 0

    private var exportEngine: VideoExportEngine? = null

    /**
     * Renders the timeline to a file.
     *
     * Runs off the main thread — the export loop itself lives on the renderer's
     * GL thread and takes as long as the video needs to decode and re-encode.
     * Playback releases the lane surfaces first: a `Surface` has one producer,
     * and the export decoders write into the same lanes ExoPlayer fills.
     */
    /** Reads the composer's `audioTracks` array — the imported music and voice-overs. */
    private fun parseAudioTracks(
        timeline: Map<String, Any?>,
    ): List<AudioExportMixer.TimelineAudioTrack> {
        val raw = timeline["audioTracks"] as? List<*> ?: return emptyList()
        return raw.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val path = map["filePath"] as? String ?: return@mapNotNull null
            if (path.isBlank()) return@mapNotNull null

            val timelineStart = (map["timelineStart"] as? Number)?.toDouble() ?: 0.0
            val timelineEnd = (map["timelineEnd"] as? Number)?.toDouble()
                ?: return@mapNotNull null
            if (timelineEnd <= timelineStart) return@mapNotNull null

            AudioExportMixer.TimelineAudioTrack(
                filePath = path,
                sourceStart = (map["sourceStart"] as? Number)?.toDouble() ?: 0.0,
                timelineStart = timelineStart,
                timelineEnd = timelineEnd,
                volume = ((map["volume"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 1.0),
            )
        }
    }

    /**
     * Export dimensions for a canvas of [aspect] at [shortSidePx].
     *
     * The **short** side is the quality tier, so a 9:16 project at 1080 exports
     * 1080x1920 and a 16:9 one exports 1920x1080 — which is what "1080p" means
     * to a user in either orientation. Taking it as the height instead would
     * give a portrait project 608x1080.
     *
     * Deliberately not derived from the preview canvas: that is capped at
     * `kMaxPreviewCanvasPx` for fill rate, and an export inheriting the cap
     * would top out at 720p.
     */
    private fun exportSizeFor(aspect: Double, shortSidePx: Int): Pair<Int, Int> {
        val short = shortSidePx.coerceIn(240, 3840)
        if (aspect <= 0.0) return Pair(short, short)

        return if (aspect >= 1.0) {
            // Landscape or square: the height is the short side.
            Pair(Math.round(short * aspect).toInt(), short)
        } else {
            // Portrait: the width is the short side.
            Pair(short, Math.round(short / aspect).toInt())
        }
    }

    private fun startExport(
        timeline: Map<String, Any?>,
        outputPath: String,
        frameRate: Int,
        targetShortSidePx: Int,
        result: MethodChannel.Result,
    ) {
        val activeRenderer = renderer
        val playback = engine
        if (activeRenderer == null) {
            result.error("not_ready", "Preview is not initialised.", null)
            return
        }

        val clips = NativeTimelineClips.fromTimeline(timeline)
        if (clips.isEmpty()) {
            result.error("empty_timeline", "Nothing to export.", null)
            return
        }
        val transitions = NativeTimelineTransitionIntents.fromTimeline(timeline)
        val canvas = timeline["canvas"] as? Map<*, *>
        val canvasAspect = (canvas?.get("aspectRatio") as? Number)?.toDouble() ?: 0.0
        // Falls back to the preview canvas's shape only when the timeline did
        // not carry one, so an export is never sized from the preview's cap.
        val aspect = if (canvasAspect > 0.0) {
            canvasAspect
        } else if (canvasWidth > 0 && canvasHeight > 0) {
            canvasWidth.toDouble() / canvasHeight
        } else {
            9.0 / 16.0
        }
        val (exportWidth, exportHeight) = exportSizeFor(aspect, targetShortSidePx)
        Log.i(
            "SlimshotExport",
            "export size ${exportWidth}x$exportHeight " +
                "(aspect=$aspect short=$targetShortSidePx, preview was ${canvasWidth}x$canvasHeight)",
        )

        // Export composes its own timeline in Dart, so the letterbox colour is
        // taken from *that* payload rather than trusted to match whatever the
        // preview last pushed.
        run {
            val backgroundType = canvas?.get("backgroundType") as? String ?: "black"
            val argb = if (backgroundType == "color") {
                (canvas?.get("backgroundColor") as? Number)?.toInt() ?: 0xFF000000.toInt()
            } else {
                0xFF000000.toInt()
            }
            renderer?.setBackgroundColor(argb)
            // Synchronous: the export's first frame must not go out before the
            // photo is at least pending for upload.
            renderer?.setBackgroundImagePath(
                if (backgroundType == "image") canvas?.get("backgroundImagePath") as? String else null,
                synchronous = true,
            )
        }

        val overlays = NativeTimelineOverlays.fromTimeline(timeline)

        // A video overlay's sound is one more source to the mixer, windowed to
        // the overlay's span — the same shape as an imported music track.
        val overlayAudio = overlays
            .filter { it.isVideo && !it.isMuted && it.volume > 0.0 }
            .map {
                AudioExportMixer.TimelineAudioTrack(
                    filePath = it.path,
                    sourceStart = it.sourceStart,
                    timelineStart = it.startSeconds,
                    timelineEnd = it.endSeconds,
                    volume = it.volume,
                )
            }

        val audioTracks = parseAudioTracks(timeline) + overlayAudio
        // A muted project exports silent rather than exporting the wrong sound.
        val masterVolume = if (timeline["isMuted"] == true) 0.0 else 1.0

        // The composed project duration. Longer than the last clip when audio
        // or an overlay outlasts the video — the engine renders that tail as
        // bare background, the same picture the preview's ticker tail shows.
        val totalDurationSeconds =
            (timeline["durationSeconds"] as? Number)?.toDouble() ?: 0.0

        playback?.pause()
        playback?.detachSurfacesForExport()

        val exporter = VideoExportEngine(
            renderer = activeRenderer,
            onProgress = { progress ->
                sendEvent(mapOf("type" to "exportProgress", "progress" to progress))
            },
            onWarning = { message ->
                sendEvent(mapOf("type" to "exportWarning", "message" to message))
            },
        )
        exportEngine = exporter

        Thread({
            try {
                val exported = exporter.export(
                    VideoExportEngine.Request(
                        clips = clips,
                        transitions = transitions,
                        overlays = overlays,
                        audioTracks = audioTracks,
                        masterVolume = masterVolume,
                        totalDurationSeconds = totalDurationSeconds,
                        canvasWidth = exportWidth,
                        canvasHeight = exportHeight,
                        canvasAspect = canvasAspect,
                        frameRate = frameRate,
                        outputPath = outputPath,
                    ),
                )
                mainHandler.post {
                    playback?.reattachSurfacesAfterExport()
                    exportEngine = null
                    result.success(
                        mapOf(
                            "outputPath" to exported.outputPath,
                            "durationSeconds" to exported.durationSeconds,
                            "frameCount" to exported.frameCount,
                            "degradedTransitions" to exported.degradedTransitions,
                        ),
                    )
                }
            } catch (error: Exception) {
                Log.e("SlimshotExport", "Export failed", error)
                mainHandler.post {
                    playback?.reattachSurfacesAfterExport()
                    exportEngine = null
                    result.error(
                        "export_failed",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }, "slimshot-export").start()
    }

    fun sendEvent(event: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            eventSink?.success(event)
        } else {
            mainHandler.post { eventSink?.success(event) }
        }
    }

    /**
     * A renderer warning, sent as whichever event the screen that can act on it
     * is listening for.
     *
     * `composite` is shared by preview and export, so the effect chain warns
     * from both — but the two have different audiences. During an export the
     * export screen is up and watching `exportWarning`, and the message is about
     * the *file* the user is waiting on, which may legitimately differ from the
     * preview. Otherwise the editor is up, and it is `warning` that the editor
     * understands — the same event the transition-lane fallback already uses to
     * say "this device forced a compromise, here is what you are looking at".
     *
     * Sending both types unconditionally was the alternative and is worse: the
     * export screen would toast a warning about the canvas it is not showing,
     * and the editor would keep one on screen about an export that has finished.
     */
    private fun sendRenderWarning(message: String) {
        val type = if (exportEngine != null) "exportWarning" else "warning"
        sendEvent(mapOf("type" to type, "message" to message))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                try {
                    result.success(mapOf("textureId" to initialize()))
                } catch (error: Exception) {
                    result.error(
                        "initialize_failed",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }

            "setTimeline" -> {
                val timeline = call.arguments as? Map<String, Any?>
                if (timeline == null) {
                    result.error("invalid_timeline", "Timeline payload is missing.", null)
                    return
                }

                val active = engine
                if (active == null) {
                    pendingTimeline = timeline
                } else {
                    try {
                        resizeCanvas(timeline)
                        active.setTimeline(timeline)
                    } catch (error: Exception) {
                        sendEvent(
                            mapOf(
                                "type" to "error",
                                "message" to "Native preview timeline failed: ${
                                    error.message ?: error.javaClass.simpleName
                                }",
                            ),
                        )
                    }
                }
                result.success(null)
            }

            "play" -> {
                engine?.play()
                result.success(null)
            }

            "pause" -> {
                engine?.pause()
                result.success(null)
            }

            "seek" -> {
                val seconds = call.argument<Number>("seconds")?.toDouble()
                if (seconds == null) {
                    result.error("invalid_seek", "Seek command requires seconds.", null)
                    return
                }
                engine?.seek(seconds)
                result.success(null)
            }

            "exportVideo" -> {
                val timeline = call.argument<Map<String, Any?>>("timeline")
                val outputPath = call.argument<String>("outputPath")
                if (timeline == null || outputPath.isNullOrBlank()) {
                    result.error(
                        "invalid_export",
                        "Export needs a timeline and an output path.",
                        null,
                    )
                    return
                }
                startExport(
                    timeline,
                    outputPath,
                    (call.argument<Number>("frameRate") ?: 30).toInt(),
                    (call.argument<Number>("targetShortSidePx") ?: 1080).toInt(),
                    result,
                )
            }

            "cancelExport" -> {
                exportEngine?.cancel()
                result.success(null)
            }

            // Reports what this device's codecs will actually agree to, and
            // starts an encoder to prove it rather than trusting the advertised
            // instance counts. Called with the preview loaded, so the encoder is
            // created while playback already holds its decoders — which is the
            // state export will run in.
            "probeExportCapabilities" -> {
                result.success(
                    ExportCapabilities.probe(
                        (call.argument<Number>("width") ?: 720).toInt(),
                        (call.argument<Number>("height") ?: 1280).toInt(),
                    ),
                )
            }

            "setClipTransform" -> {
                val clipId = call.argument<String>("clipId")
                if (clipId.isNullOrBlank()) {
                    result.error("invalid_transform", "Transform needs a clip id.", null)
                    return
                }
                engine?.setClipTransform(
                    clipId,
                    (call.argument<Number>("scale") ?: 1.0).toDouble(),
                    (call.argument<Number>("offsetX") ?: 0.0).toDouble(),
                    (call.argument<Number>("offsetY") ?: 0.0).toDouble(),
                    (call.argument<Number>("rotation") ?: 0.0).toDouble(),
                )
                result.success(null)
            }

            "setScrubbing" -> {
                engine?.setScrubbing(call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            }

            "setVolume" -> {
                val volume = call.argument<Number>("volume")?.toFloat()
                if (volume == null) {
                    result.error("invalid_volume", "Volume command requires volume.", null)
                    return
                }
                engine?.setVolume(volume)
                result.success(null)
            }

            "dispose" -> {
                releasePreview()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Creates the Flutter texture and brings up the renderer and engine.
     *
     * Returns the texture id Flutter's `Texture` widget renders.
     */
    private fun initialize(): Long {
        textureEntry?.let { return it.id() }

        val entry = textureRegistry.createSurfaceTexture()
        textureEntry = entry

        val activeRenderer = TransitionRenderer(
            onLaneSurfaceReady = { laneIndex, surface ->
                mainHandler.post { engine?.attachLaneSurface(laneIndex, surface) }
            },
            onError = { message ->
                sendEvent(mapOf("type" to "error", "message" to message))
            },
            onWarning = ::sendRenderWarning,
        )
        renderer = activeRenderer

        val activeEngine = TimelinePlaybackEngine(
            context = context,
            renderer = activeRenderer,
            onEvent = ::handleEngineEvent,
        )
        engine = activeEngine

        activeRenderer.start()
        // Until the first video size arrives, give the texture a sane size so
        // the very first frames are not scaled from a 1x1 buffer.
        entry.surfaceTexture().setDefaultBufferSize(
            DEFAULT_TEXTURE_WIDTH,
            DEFAULT_TEXTURE_HEIGHT,
        )
        activeRenderer.attachOutputSurface(
            entry.surfaceTexture(),
            DEFAULT_TEXTURE_WIDTH,
            DEFAULT_TEXTURE_HEIGHT,
        )

        pendingTimeline?.let {
            resizeCanvas(it)
            activeEngine.setTimeline(it)
            pendingTimeline = null
        }

        return entry.id()
    }

    /**
     * Sizes the output texture to the **project canvas**.
     *
     * Not to the video: clips in one project can have different shapes, and
     * the renderer fits each into the canvas. Sizing the surface to whichever
     * clip happened to report its dimensions first makes every one of those
     * fits wrong — a portrait project with a landscape clip ends up rendering
     * into a landscape viewport and the picture is squeezed.
     */
    private fun resizeCanvas(timeline: Map<String, Any?>) {
        val canvas = timeline["canvas"] as? Map<*, *> ?: return
        val width = (canvas["width"] as? Number)?.toInt() ?: return
        val height = (canvas["height"] as? Number)?.toInt() ?: return
        if (width <= 0 || height <= 0) return
        if (width == canvasWidth && height == canvasHeight) return

        canvasWidth = width
        canvasHeight = height

        val entry = textureEntry ?: return
        entry.surfaceTexture().setDefaultBufferSize(width, height)
        // An EGL window surface caches its dimensions, so it has to be rebuilt
        // for the new buffer size to take effect — a size notification alone
        // would keep rendering at the old size.
        renderer?.attachOutputSurface(entry.surfaceTexture(), width, height)
    }

    private fun handleEngineEvent(event: Map<String, Any?>) {
        // Video size is forwarded to Dart for information only; it must not
        // drive the surface size (see resizeCanvas).
        sendEvent(event)
    }

    private fun releasePreview() {
        pendingTimeline = null
        engine?.release()
        engine = null
        renderer?.release()
        renderer = null
        textureEntry?.release()
        textureEntry = null
        canvasWidth = 0
        canvasHeight = 0
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    companion object {
        const val methodChannelName = "slimshot_ai/native_timeline_preview"
        const val eventChannelName = "slimshot_ai/native_timeline_preview/events"

        private const val DEFAULT_TEXTURE_WIDTH = 1280
        private const val DEFAULT_TEXTURE_HEIGHT = 720
    }
}
