package com.techfamz.slimshotai.export

import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.nativepreview.LaneFit
import com.techfamz.slimshotai.nativepreview.NativeTimelineClip
import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay
import com.techfamz.slimshotai.nativepreview.NativeTimelineTransitionIntent
import com.techfamz.slimshotai.nativepreview.gl.OverlayDrawBuilder
import com.techfamz.slimshotai.nativepreview.gl.TransitionDraw
import com.techfamz.slimshotai.nativepreview.gl.TransitionRenderer
import com.techfamz.slimshotai.nativepreview.gl.effects.ClipEffectController
import com.techfamz.slimshotai.thumbnails.StillImageDecoder
import java.io.File

/**
 * Renders the timeline to a file, faster than realtime.
 *
 * The clock is ours: for each output frame the engine works out which clips are
 * live at that instant, positions their decoders on the matching source frame,
 * and asks the renderer to composite. Nothing waits for wall time, so the export
 * runs as fast as decode and encode allow.
 *
 * **The picture comes from the same code the preview uses.**
 * `TransitionRenderer.composite` draws both, so transitions, letterboxing, crop,
 * per-clip grades and the project look cannot differ between what the user
 * previewed and what lands in the file.
 *
 * The whole loop runs on the renderer's GL thread, where the EGL context lives.
 */
@UnstableApi
internal class VideoExportEngine(
    private val renderer: TransitionRenderer,
    private val onProgress: (Double) -> Unit,
    private val onWarning: (String) -> Unit,
) {

    data class Request(
        val clips: List<NativeTimelineClip>,
        val transitions: List<NativeTimelineTransitionIntent>,
        val overlays: List<NativeTimelineOverlay>,
        val audioTracks: List<AudioExportMixer.TimelineAudioTrack>,
        val masterVolume: Double,
        /**
         * The composed project duration. Exceeds the last clip's end when
         * audio or an overlay outlasts the video; the export then keeps
         * rendering background-only frames until this instant, so a long
         * music track is not cut off where the picture stops.
         */
        val totalDurationSeconds: Double,
        val canvasWidth: Int,
        val canvasHeight: Int,
        val canvasAspect: Double,
        val frameRate: Int,
        val outputPath: String,
    )

    data class Result(
        val outputPath: String,
        val durationSeconds: Double,
        val frameCount: Int,
        val degradedTransitions: Int,
    )

    /** One lane's decoder plus which clip it currently holds. */
    private class LaneState {
        var decoder: ExportClipDecoder? = null
        var clipId: String? = null
        var failed = false

        /**
         * True while this lane is showing a photo rather than decoder output.
         *
         * Survives [release], which only drops the decoder: the renderer keeps
         * showing an image until it is told otherwise, so the next video clip on
         * this lane has to clear it or the still would be drawn over the video.
         */
        var showingImage = false

        /** False when the clip on this lane could not be made drawable. */
        var contentReady = false

        /** Consecutive failed decoder opens, for the bounded retry. */
        var openAttempts = 0

        /**
         * Which clip [openAttempts] is counting for. The retry path clears
         * `clipId` to trigger a reopen, so the counter cannot key off it — it
         * would reset on every retry and the bound would never be reached.
         */
        var attemptsClipId: String? = null

        /**
         * Recovery ladder for a decoder that consumed its input without ever
         * producing a frame: 0 = untried, 1 = reopened once, 2 = nearest-frame
         * rescue attempted (done). Keyed by [recoveryClipId] for the same
         * reason as [attemptsClipId].
         */
        var recoveryStage = 0
        var recoveryClipId: String? = null

        fun release() {
            decoder?.release()
            decoder = null
            clipId = null
        }
    }

    /** Counters for one export, reported rather than left in the picture. */
    private class VideoDiagnostics {
        var lateFrames = 0
        var blankFrames = 0
        var undecodableStills = 0
        var failedOverlays = 0
        var skippedOverlayDecoders = 0
    }

    @Volatile
    private var cancelled = false

    fun cancel() {
        cancelled = true
    }

    /**
     * Renders the timeline to a file.
     *
     * Runs on the caller's background thread. **Audio deliberately does not
     * touch the GL thread**: decoding and encoding it has nothing to do with
     * rendering, and doing that work on the renderer's thread put codec I/O on
     * the one thread that owns the EGL context. Only the video loop is
     * submitted there, because only it needs the context.
     */
    fun export(request: Request): Result {
        require(request.clips.isNotEmpty()) { "Nothing to export." }

        val videoEndSeconds = request.clips.maxOf { it.timelineEnd }
        require(videoEndSeconds > 0.0) { "Timeline has no duration." }
        // Audio or an overlay may run past the last clip; the file covers the
        // longer of the two, with the tail rendered as bare background — the
        // same picture the preview's ticker tail plays over.
        val duration = maxOf(videoEndSeconds, request.totalDurationSeconds)
        Log.i(
            TAG,
            "export duration: clips end ${"%.2f".format(videoEndSeconds)}s, " +
                "timeline says ${"%.2f".format(request.totalDurationSeconds)}s " +
                "-> rendering ${"%.2f".format(duration)}s",
        )

        // Reject unplayable media before anything is created, so the failure
        // names the file rather than producing a black stretch.
        for (clip in request.clips) {
            if (clip.isImage) continue
            if (!File(clip.playbackVideoPath).exists()) {
                throw IllegalStateException("Missing file: ${clip.playbackVideoPath}")
            }
        }

        // Audio is mixed and encoded first. The muxer holds samples until every
        // track has been added, and holding video would mean buffering hundreds
        // of megabytes where audio is a couple; running the audio codecs to
        // completion first also releases them before the video codecs are
        // created, keeping the peak number of live instances down.
        val mixer = AudioExportMixer(
            clips = request.clips,
            audioTracks = request.audioTracks,
            overlays = request.overlays,
            masterVolume = request.masterVolume,
            transitions = request.transitions,
            durationSeconds = duration,
        )
        val hasAudio = try {
            mixer.prepare()
        } catch (error: Exception) {
            Log.w(TAG, "Audio could not be prepared; exporting video only", error)
            onWarning("Exported without sound: ${error.javaClass.simpleName} ${error.message}")
            mixer.release()
            false
        }
        // A project with nothing audible — photos only, or every source muted —
        // legitimately exports silent. That is not a warning; toasting it made
        // every photo export look faulty. The reason still goes to the log for
        // the case where sound was expected and missing.
        if (!hasAudio) {
            Log.i(TAG, "No audio sources (${mixer.firstFailureReason}); exporting video only")
        }

        // Opening the decoders is real work and takes a noticeable moment on a
        // low-end device. Reporting it moves the bar off zero immediately,
        // instead of leaving the first seconds looking like a hang.
        onProgress(SETUP_PROGRESS)

        var muxer: ExportMuxer? = null
        try {
            muxer = ExportMuxer(
                request.outputPath,
                expectedTracks = if (hasAudio) 2 else 1,
            )

            // Progress is split between the two passes so the bar always moves.
            // Audio runs first and to completion, so reporting only video
            // progress left the export looking frozen for the whole audio pass.
            val videoProgressFloor = if (hasAudio) AUDIO_PROGRESS_SHARE else 0.0

            if (hasAudio) {
                mixer.encodeTo(
                    muxer,
                    isCancelled = { cancelled },
                    onProgress = { fraction ->
                        onProgress(fraction * AUDIO_PROGRESS_SHARE)
                    },
                )
                if (cancelled) throw InterruptedException("Export cancelled.")

                // Silence is never an acceptable silent outcome. If the pass
                // ran and produced nothing, say so with the counters rather
                // than handing over a mute file as a clean success.
                if (mixer.producedNothing) {
                    onWarning("Exported without sound — ${mixer.diagnostics}")
                }
            } else {
                Log.i(TAG, "No audio sources; exporting video only")
            }

            val video = renderer.callOnGlThread {
                runVideo(request, muxer!!, duration, videoProgressFloor)
            }
            onProgress(1.0)

            if (video.degradedTransitions > 0) {
                onWarning(
                    "${video.degradedTransitions} transition(s) exported as a cut: " +
                        "this device would not run a second video decoder.",
                )
            }

            return Result(
                outputPath = request.outputPath,
                durationSeconds = duration,
                frameCount = video.frameCount,
                degradedTransitions = video.degradedTransitions,
            )
        } finally {
            mixer.release()
            muxer?.close()
            if (cancelled) {
                File(request.outputPath).delete()
            }
        }
    }

    private class VideoResult(val frameCount: Int, val degradedTransitions: Int)

    /** The video pass. Runs on the GL thread, where the EGL context lives. */
    private fun runVideo(
        request: Request,
        muxer: ExportMuxer,
        duration: Double,
        progressFloor: Double,
    ): VideoResult {
        val (encodeWidth, encodeHeight) =
            ExportCapabilities.alignedEncoderSize(request.canvasWidth, request.canvasHeight)

        // The encoder may refuse the size asked for — this app spans a decade
        // of Android hardware and the range one device supports is not the
        // range another does. Alignment rounding of a pixel or two is routine;
        // a real reduction means the user is getting a smaller file than they
        // chose, and has to be told rather than discovered later.
        val requestedPixels = request.canvasWidth.toLong() * request.canvasHeight
        val encodedPixels = encodeWidth.toLong() * encodeHeight
        if (encodedPixels < requestedPixels * SIZE_DOWNGRADE_THRESHOLD) {
            Log.w(
                TAG,
                "Encoder capped ${request.canvasWidth}x${request.canvasHeight} " +
                    "to ${encodeWidth}x$encodeHeight",
            )
            onWarning(
                "Exported at ${encodeWidth}x$encodeHeight — this device's encoder " +
                    "would not accept ${request.canvasWidth}x${request.canvasHeight}.",
            )
        }

        val lanes = arrayOf(LaneState(), LaneState())
        val diagnostics = VideoDiagnostics()
        // The per-frame overlay decisions live in [OverlayDrawBuilder] so the
        // preview can share them; the counters it used to bump directly stay
        // here, fed through its events.
        val overlayPass = OverlayDrawBuilder(
            renderer = renderer,
            overlays = request.overlays,
            events = object : OverlayDrawBuilder.Events {
                override fun onOverlayFailed() {
                    diagnostics.failedOverlays++
                }

                override fun onDecoderSkipped() {
                    diagnostics.skippedOverlayDecoders++
                }

                override fun onLateFrame() {
                    diagnostics.lateFrames++
                }
            },
            frameWaitMs = FRAME_WAIT_MS,
        )
        var encoder: VideoFrameEncoder? = null
        var degraded = 0
        var frameIndex = 0

        // What the lanes look like on the way in. A lane that starts without a
        // frame used to be one that could never get one: `onFrameAvailable` was
        // delivered on this thread's looper, which this loop occupies for the
        // whole export.
        Log.i(
            TAG,
            "video pass: ${encodeWidth}x$encodeHeight @${request.frameRate}fps, " +
                "lane0.hasFrame=${renderer.laneHasFrame(0)} " +
                "lane1.hasFrame=${renderer.laneHasFrame(1)}",
        )

        // The shape of the frame actually being rendered and encoded. Fits are
        // computed against this, never against the requested canvas, so a
        // device that forces a different encode size still letterboxes every
        // clip correctly inside the frame it really produces.
        val renderAspect = encodeWidth.toDouble() / encodeHeight

        // Outside the try so the finally can clear it. The renderer's EGL
        // context **survives** an export — it is the preview's — so these
        // programs have to be deleted and the pass list emptied explicitly, or
        // the last exported frame's effect stays on the canvas when playback
        // comes back.
        val clipEffects = ClipEffectController(renderer)

        try {
            encoder = VideoFrameEncoder(
                encodeWidth,
                encodeHeight,
                request.frameRate,
                VideoFrameEncoder.bitRateFor(encodeWidth, encodeHeight, request.frameRate),
            )
            renderer.beginExport(encoder.inputSurface, encodeWidth, encodeHeight)

            val frameDurationSeconds = 1.0 / request.frameRate
            val totalFrames = Math.ceil(duration * request.frameRate).toInt()

            // Last instant with video on it. Past this only audio and overlays
            // are still running, and the frame is bare background.
            val videoEndSeconds = request.clips.maxOf { it.timelineEnd }
            var lanesReleasedForTail = false

            while (frameIndex < totalFrames && !cancelled) {
                val t = frameIndex * frameDurationSeconds

                // Codec slots free up before anything tries to claim one.
                overlayPass.releaseExpired(t)

                val window = request.transitions.firstOrNull { it.contains(t) }
                val outgoing = window?.let { request.clips.getOrNull(it.leftClipIndex) }
                val incoming = window?.let { request.clips.getOrNull(it.rightClipIndex) }

                // Which clip's effect is drawn on this frame.
                //
                // **In a transition the outgoing clip wins for the whole
                // window.** The two overlapping clips may carry different
                // effects, but a pass runs on the *finished composited frame* —
                // one frame, two answers — and the outgoing clip is already the
                // window's master everywhere else: its clock drives the blend
                // and mastership hands over at the window's end. Effecting each
                // lane into its own target before the blend would be more
                // correct and doubles the offscreen targets and the pass count
                // on exactly the hardware two live decoders already strain. It
                // is a decision, not an oversight, and the preview engine makes
                // the same one so the two still agree.
                //
                // Past the video end there is no clip at all, and no effect: the
                // tail is bare background plus live overlays, and overlays are
                // deliberately painted outside the effect chain.
                // The conditions mirror the draw branches below exactly, so the
                // effect always follows the clip actually on the frame — a
                // half-resolved window (one of the two clips missing) draws
                // through the plain path, and so must its effect.
                val effectClip = when {
                    t >= videoEndSeconds - EDGE_EPSILON -> null
                    window != null && outgoing != null && incoming != null -> outgoing
                    else -> clipAt(request.clips, t) ?: request.clips.firstOrNull()
                }
                // **The effect clock is `t`, the export's own timeline
                // position** — never the frame index and never wall clock
                // time. This loop runs as fast as the codecs allow, so a
                // self-timed effect would play at the export's speed rather
                // than the project's and the file would not match the canvas.
                // `t` is the same quantity the preview engine's ticker passes,
                // so both reach the identical progress at the identical instant
                // of a clip whatever rate either is running at.
                // One progress, used for both the shader's clock and the
                // strength it is drawn at, so an envelope or a keyframe row can
                // never be a frame out of step with the picture it shapes. A
                // flat parameter resolves to its base value at every progress —
                // exactly the scalar this replaced.
                val effectProgress = effectClip?.effectProgressAt(t) ?: 0.0
                clipEffects.apply(
                    effectClip?.effectId,
                    effectClip?.effectIntensityAt(effectProgress) ?: 0.0,
                    effectProgress,
                )

                if (t >= videoEndSeconds - EDGE_EPSILON) {
                    // The audio/overlay tail: no lane is drawn, so the frame is
                    // the background colour plus whatever overlays are live.
                    // The clip decoders are finished for good — releasing them
                    // up front frees their codec slots for an overlay decoder
                    // that runs into the tail.
                    if (!lanesReleasedForTail) {
                        lanesReleasedForTail = true
                        lanes.forEach { it.release() }
                        renderer.clearTransition()
                        renderer.setActiveLane(NO_ACTIVE_LANE)
                    }
                } else if (window != null && outgoing != null && incoming != null) {
                    val outReady = prepareLane(lanes, outgoing, t, request, renderAspect, diagnostics)
                    val inReady = prepareLane(lanes, incoming, t, request, renderAspect, diagnostics)

                    if (outReady && inReady) {
                        renderer.setActiveLane(outgoing.laneIndex)
                        renderer.setTransition(
                            TransitionDraw(
                                type = window.type,
                                progress = window.progressAt(t),
                                outgoingLane = outgoing.laneIndex,
                                incomingLane = incoming.laneIndex,
                            ),
                        )
                    } else {
                        // A device that will not give us the second decoder
                        // gets a hard cut, the same fallback the preview makes,
                        // so the two still agree. Reported, never silent.
                        degraded++
                        val live = if (inReady) incoming else outgoing
                        renderer.clearTransition()
                        renderer.setActiveLane(live.laneIndex)
                    }
                } else {
                    val clip = clipAt(request.clips, t) ?: request.clips.first()
                    if (!prepareLane(lanes, clip, t, request, renderAspect, diagnostics)) {
                        diagnostics.blankFrames++
                    }
                    renderer.clearTransition()
                    renderer.setActiveLane(clip.laneIndex)
                }

                renderer.drawExportFrame(
                    (t * 1_000_000_000L).toLong(),
                    overlayPass.drawsFor(t),
                )
                encoder.drainTo(muxer, endOfStream = false)

                frameIndex++
                if (frameIndex % PROGRESS_EVERY_FRAMES == 0) {
                    val fraction = (frameIndex.toDouble() / totalFrames).coerceIn(0.0, 1.0)
                    onProgress(progressFloor + fraction * (1.0 - progressFloor))
                }
            }

            encoder.signalEndOfStream()
            while (!encoder.isFinished) {
                encoder.drainTo(muxer, endOfStream = true)
            }

            reportDiagnostics(diagnostics, frameIndex)
            return VideoResult(frameIndex, degraded)
        } finally {
            lanes.forEach { it.release() }
            // Decoders before endExport, which frees the GL-side overlay lanes.
            overlayPass.release()
            // Before endExport, while the GL thread is still ours to post onto:
            // this deletes the effect programs and empties the renderer's pass
            // list, so playback resumes on its single-pass path instead of
            // inheriting whatever the last exported frame carried.
            clipEffects.apply(null, 0.0)
            renderer.endExport()
            encoder?.release()
        }
    }

    /**
     * Puts [clip] on its lane and positions it at timeline instant [t].
     *
     * Returns false when the lane has nothing drawable — this device would not
     * give us a decoder, or a photo could not be decoded — so the caller
     * degrades to a cut rather than exporting a black frame in silence.
     */
    private fun prepareLane(
        lanes: Array<LaneState>,
        clip: NativeTimelineClip,
        t: Double,
        request: Request,
        renderAspect: Double,
        diagnostics: VideoDiagnostics,
    ): Boolean {
        val lane = lanes.getOrNull(clip.laneIndex) ?: return false

        if (lane.clipId != clip.id) {
            // Failure is scoped to a clip, never to the lane. Left sticky, one
            // clip that exhausted its retries silently killed every later clip
            // on the same lane: a three-clip export froze on clip one's last
            // frame while clips two AND three never appeared. The attempt
            // counter itself is scoped by [LaneState.attemptsClipId], because
            // the retry path clears `clipId` on purpose.
            lane.failed = false
            lane.release()
            lane.clipId = clip.id
            lane.contentReady = false

            if (clip.isImage) {
                loadStill(lane, clip, request, diagnostics)
            } else {
                openDecoder(lane, clip)
            }

            Log.i(
                TAG,
                "lane[${clip.laneIndex}] -> ${clip.id} image=${clip.isImage} " +
                    "ready=${lane.contentReady} hasFrame=${renderer.laneHasFrame(clip.laneIndex)}",
            )
        }
        // After the switch handling, so a clip that failed keeps failing
        // cheaply — but a *new* clip on the lane got its fresh chance above.
        if (lane.failed) return false

        // Per-frame lane state, identical to what the preview engine sets each
        // tick — the fit formula is shared rather than copied.
        // Fitted against the aspect of the frame actually being encoded, not
        // the one that was requested. If the encoder forced a different shape,
        // fitting against the request would letterbox every clip wrongly inside
        // the real viewport — clips shrank exactly this way when a per-axis
        // clamp turned a portrait request into a square.
        //
        // The clip's own progress, so a keyframed transform moves across the
        // clip in the file exactly as it does on the canvas. `t` is the
        // timeline position, never a frame index — this loop runs as fast as
        // the codecs allow, so anything self-timed would render differently.
        val clipProgress = clip.clipProgressAt(t)

        // Export used to inherit whatever canvas rect the *preview* engine had
        // last left on the renderer — right by accident, since a `setTimeline`
        // always preceded an export. It now sets the clip's own rect per
        // frame, which is both correct and no longer accidental.
        val r = clip.contentRect
        renderer.setLaneContentRect(clip.laneIndex, r[0], r[1], r[2], r[3])
        renderer.setLaneFlip(clip.laneIndex, clip.flipMask())
        renderer.setLaneMask(clip.laneIndex, clip.maskUniforms())
        renderer.setLaneChromaKey(clip.laneIndex, clip.chromaUniforms())
        renderer.setLaneOpacity(clip.laneIndex, clip.opacityAt(clipProgress).toFloat())

        if (clip.isImage) {
            // A photo's contain fit is derived by the renderer from the
            // decoded bitmap at draw time, against the viewport actually being
            // encoded — the same atomic path the preview uses. Only the clip
            // transform is pushed from here.
            renderer.setLaneImageTransform(
                clip.laneIndex,
                clip.canvasScaleAt(clipProgress).toFloat(),
                clip.canvasOffsetXAt(clipProgress).toFloat(),
                clip.canvasOffsetYAt(clipProgress).toFloat(),
                Math.toRadians(clip.canvasRotationAt(clipProgress)).toFloat(),
            )
        } else {
            // Fitted by what the lane shows through its rect, not by the
            // whole frame — the same rule the preview engine applies.
            val (fitX, fitY) = LaneFit.of(clip.contentAspect, renderAspect)
            renderer.setLaneFit(
                clip.laneIndex,
                fitX * clip.canvasScaleAt(clipProgress).toFloat(),
                fitY * clip.canvasScaleAt(clipProgress).toFloat(),
                clip.canvasOffsetXAt(clipProgress).toFloat(),
                clip.canvasOffsetYAt(clipProgress).toFloat(),
                Math.toRadians(clip.canvasRotationAt(clipProgress)).toFloat(),
            )
        }
        renderer.setLaneColorMatrix(clip.laneIndex, clip.colorMatrix)

        val decoder = lane.decoder
        if (decoder != null) {
            val targetUs = (clip.sourceAt(t) * 1_000_000L).toLong()
            val since = renderer.laneFrameSequence(clip.laneIndex)
            var renderedNew = decoder.advanceTo(targetUs)
            if (!renderedNew && decoder.isFinished && decoder.lastRenderedUs < 0L) {
                // The decoder consumed its input without producing a single
                // frame. Known causes: a codec that lost its CSD anyway, or a
                // trim pointing past the video track's last sample (a
                // container routinely outlives its video track). One full
                // reopen — through the no-flush open — then the nearest
                // earlier frame; a nearby picture from *this* clip beats the
                // previous clip's stale one. Each step runs at most once per
                // clip, so a clip that truly has nothing cannot loop the
                // export into re-reading its file every output frame.
                if (lane.recoveryClipId != clip.id) {
                    lane.recoveryClipId = clip.id
                    lane.recoveryStage = 0
                }
                // Both branches toast through `exportWarning` as well as log:
                // these paths only fire when something is already wrong, and
                // the device names the failing mechanism without a logcat.
                when (lane.recoveryStage) {
                    0 -> {
                        Log.w(
                            TAG,
                            "clip ${clip.id}: decoder produced nothing; " +
                                "reopening once",
                        )
                        onWarning(
                            "Decoder for " +
                                "${File(clip.playbackVideoPath).name} " +
                                "produced no frames — reopened.",
                        )
                        lane.recoveryStage = 1
                        lane.release()
                        // Reopens next frame through openDecoder.
                    }

                    1 -> {
                        Log.w(
                            TAG,
                            "clip ${clip.id}: still no frame at ${targetUs}us; " +
                                "showing nearest earlier frame",
                        )
                        onWarning(
                            "${File(clip.playbackVideoPath).name}: still no " +
                                "frame after reopen — showing nearest frame.",
                        )
                        lane.recoveryStage = 2
                        decoder.seekTo(targetUs)
                        renderedNew = decoder.advanceTo(0L)
                    }
                }
            }
            if (renderedNew) {
                // `releaseOutputBuffer(index, true)` only **queues** the frame;
                // it reaches the lane's SurfaceTexture on the producer's own
                // thread. Compositing without waiting would draw the frame
                // before it, and the flag the renderer gates its texture update
                // on arrives on the GL thread's looper — which this loop is
                // occupying, so on a lane that had never had a frame it could
                // not arrive at all.
                if (!renderer.awaitLaneFrame(clip.laneIndex, since, FRAME_WAIT_MS)) {
                    diagnostics.lateFrames++
                }
            }
        }

        return lane.contentReady
    }

    /**
     * Decodes a photo clip and hands it to the renderer as a 2D texture.
     *
     * Export **has** to decode its own stills. Playback is paused and the lane
     * surfaces are detached by the time this runs, so nothing is feeding the
     * lane: relying on the bitmap the preview engine's `ImageOutput` happened to
     * leave there exported that one photo for the whole file.
     */
    private fun loadStill(
        lane: LaneState,
        clip: NativeTimelineClip,
        request: Request,
        diagnostics: VideoDiagnostics,
    ) {
        // Decoded to the canvas, not to the file's own size: the frame is
        // fitted into that canvas anyway, and a 12MP photo would be a large
        // allocation and a large texture upload for nothing.
        val bitmap = StillImageDecoder.decode(
            clip.playbackVideoPath,
            request.canvasWidth,
            request.canvasHeight,
        )
        if (bitmap == null) {
            Log.w(TAG, "Could not decode still ${clip.playbackVideoPath}")
            diagnostics.undecodableStills++
            return
        }
        // The renderer measures the bitmap at upload and derives its contain
        // fit at draw time — the decoded pixels (EXIF rotation and
        // downsampling already applied) are the authority on shape.
        renderer.setLaneImage(clip.laneIndex, bitmap)
        lane.showingImage = true
        lane.contentReady = true
    }

    /** Opens a video clip's decoder onto the lane's surface. */
    private fun openDecoder(lane: LaneState, clip: NativeTimelineClip) {
        // Coming off a photo the lane must go back to decoder output, or the
        // still stays bound and is drawn over every frame of the video.
        if (lane.showingImage) {
            renderer.clearLaneImage(clip.laneIndex)
            lane.showingImage = false
        }

        val surface = renderer.laneSurface(clip.laneIndex)
        if (surface == null) {
            lane.failed = true
            return
        }
        val decoder = ExportClipDecoder(clip.playbackVideoPath, surface)
        if (!decoder.open((clip.sourceStart * 1_000_000L).toLong())) {
            // NOT a permanent failure. Codec instances are a shared, scarce
            // resource — an open that lands while an overlay's decoder still
            // holds its slot fails, and the slot frees a frame later; the
            // surface the previous clip's codec just vacated can also refuse
            // to reconnect for a moment, because MediaCodec.release()
            // disconnects it asynchronously. Clearing the clip id makes the
            // next frame try again; a bounded attempt count keeps a genuinely
            // undecodable file from retrying forever.
            if (lane.attemptsClipId != clip.id) {
                lane.attemptsClipId = clip.id
                lane.openAttempts = 0
            }
            lane.openAttempts++
            if (lane.openAttempts >= MAX_DECODER_OPEN_ATTEMPTS) {
                Log.w(
                    TAG,
                    "Lane ${clip.laneIndex} decoder for ${clip.id} failed " +
                        "${lane.openAttempts} times; giving up",
                )
                lane.failed = true
                // Degrade loudly: the lane still holds the *previous* clip's
                // last frame, and compositing that for this clip's whole span
                // is a lie that reads as a freeze. Background is honest.
                renderer.invalidateLane(clip.laneIndex)
                renderer.clearLaneImage(clip.laneIndex)
                onWarning(
                    "A clip could not be decoded and shows as background " +
                        "(${File(clip.playbackVideoPath).name}).",
                )
            } else {
                lane.clipId = null
                // Export runs faster than realtime, so bare retries would all
                // land inside the same few milliseconds — before an async
                // surface disconnect or a freed codec slot has had time to
                // settle. Spreading them over real time is what lets the
                // bounded count actually cover the recovery window.
                Thread.sleep(OPEN_RETRY_BACKOFF_MS)
                // A connection the old codec left on the surface can outlive
                // any wait on some devices; a fresh surface carries none.
                // Tried twice before the attempts run out.
                if (lane.openAttempts % SURFACE_RECREATE_AFTER_ATTEMPTS == 0) {
                    renderer.recreateLaneSurfaceForExport(clip.laneIndex)
                }
            }
            return
        }
        lane.openAttempts = 0
        lane.attemptsClipId = null
        lane.decoder = decoder
        lane.contentReady = true
    }

    /**
     * Says out loud what the file will look like when it is not what was
     * previewed.
     *
     * A frame that could not be produced is a frame the user did not see in the
     * preview, so it never passes as a clean success.
     */
    private fun reportDiagnostics(diagnostics: VideoDiagnostics, frameCount: Int) {
        Log.i(
            TAG,
            "video pass done: frames=$frameCount late=${diagnostics.lateFrames} " +
                "blank=${diagnostics.blankFrames} stills=${diagnostics.undecodableStills}",
        )

        if (diagnostics.undecodableStills > 0) {
            onWarning(
                "${diagnostics.undecodableStills} photo(s) could not be read and " +
                    "are missing from the video.",
            )
        }
        if (diagnostics.blankFrames > 0) {
            onWarning(
                "${diagnostics.blankFrames} frame(s) had nothing to draw and " +
                    "exported black.",
            )
        }
        // A handful of late frames is decode jitter and shows as a repeated
        // frame. A large share means the picture is lagging its own clock,
        // which is worth saying rather than shipping quietly.
        if (frameCount > 0 && diagnostics.lateFrames > frameCount / 10) {
            onWarning(
                "${diagnostics.lateFrames} of $frameCount frames arrived late; " +
                    "the video may look choppier than the preview.",
            )
        }
        if (diagnostics.failedOverlays > 0) {
            onWarning(
                "${diagnostics.failedOverlays} overlay(s) could not be drawn " +
                    "and were left out.",
            )
        }
        if (diagnostics.skippedOverlayDecoders > 0) {
            onWarning(
                "${diagnostics.skippedOverlayDecoders} video overlay(s) skipped: " +
                    "this device cannot run that many decoders at once.",
            )
        }
    }

    /** The last clip that has started owns the instant, matching the preview. */
    private fun clipAt(clips: List<NativeTimelineClip>, t: Double): NativeTimelineClip? {
        return clips.lastOrNull { t >= it.timelineStart - EDGE_EPSILON }
    }

    private companion object {
        const val TAG = "SlimshotExport"
        const val EDGE_EPSILON = 0.001
        const val PROGRESS_EVERY_FRAMES = 15

        /**
         * No lane drawn: the composite is background and overlays only.
         * `TransitionRenderer` resolves an out-of-range active lane to null
         * and skips the lane pass. Used for the audio/overlay tail.
         */
        const val NO_ACTIVE_LANE = -1

        /**
         * How long one output frame waits for its decoded picture to land.
         *
         * Generous next to a decode, which is milliseconds, and bounded so a
         * decoder that has stopped delivering costs a repeated frame rather than
         * hanging the export with no way out.
         */
        const val FRAME_WAIT_MS = 250L

        /**
         * Share of the progress bar given to the audio pass.
         *
         * A rough split rather than a measured one — audio is far cheaper than
         * video, and the point is that the bar moves from the first moment
         * rather than that the two halves are proportionally exact.
         */
        const val AUDIO_PROGRESS_SHARE = 0.15

        /** Reported once the decoders are open, so the bar starts moving. */
        const val SETUP_PROGRESS = 0.02

        /**
         * How much smaller than requested counts as a downgrade worth telling
         * the user about, rather than ordinary alignment rounding.
         */
        const val SIZE_DOWNGRADE_THRESHOLD = 0.95

        /**
         * How many frames a lane keeps retrying a failed decoder open.
         *
         * A slot-contention failure clears within a frame or two of the
         * competing decoder being released; a whole second of retries means
         * the file genuinely cannot be decoded here.
         */
        const val MAX_DECODER_OPEN_ATTEMPTS = 30

        /**
         * Wall-clock pause between failed decoder opens. 30 attempts spread
         * 20ms apart cover ~600ms of real recovery time — enough for an async
         * surface disconnect or a competing codec's release to complete.
         */
        const val OPEN_RETRY_BACKOFF_MS = 20L

        /**
         * After this many consecutive failed opens the lane's surface itself
         * is rebuilt. A stale producer connection on the old surface fails
         * every `configure` no matter how long the retries wait.
         */
        const val SURFACE_RECREATE_AFTER_ATTEMPTS = 10
    }
}
