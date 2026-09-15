package com.techfamz.slimshotai.export

import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.nativepreview.LaneFit
import com.techfamz.slimshotai.nativepreview.NativeTimelineClip
import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay
import com.techfamz.slimshotai.nativepreview.NativeTimelineTransitionIntent
import com.techfamz.slimshotai.nativepreview.TextAnimationCategory
import com.techfamz.slimshotai.nativepreview.TextAnimationCurves
import com.techfamz.slimshotai.nativepreview.TextGlyphState
import com.techfamz.slimshotai.nativepreview.gl.OverlayRenderer
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
        val overlayPass = OverlayPass(request.overlays, diagnostics)
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
        if (clip.isImage) {
            // A photo's contain fit is derived by the renderer from the
            // decoded bitmap at draw time, against the viewport actually being
            // encoded — the same atomic path the preview uses. Only the clip
            // transform is pushed from here.
            renderer.setLaneImageTransform(
                clip.laneIndex,
                clip.canvasScale.toFloat(),
                clip.canvasOffsetX.toFloat(),
                clip.canvasOffsetY.toFloat(),
            )
        } else {
            val (fitX, fitY) = LaneFit.of(clip.sourceAspect, renderAspect)
            renderer.setLaneFit(
                clip.laneIndex,
                fitX * clip.canvasScale.toFloat(),
                fitY * clip.canvasScale.toFloat(),
                clip.canvasOffsetX.toFloat(),
                clip.canvasOffsetY.toFloat(),
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
         * Most video-overlay decoders live at once, on top of the two clip
         * lanes. Three simultaneous decoders is already the practical ceiling
         * on entry-level hardware; an overlay beyond the cap is skipped with a
         * warning rather than risking every codec on the device failing.
         */
        const val MAX_OVERLAY_DECODERS = 2

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

    /**
     * Resolves the overlays that are live at each output instant into draw
     * calls, owning the still uploads and per-overlay video decoders.
     *
     * The overlays arrive lane-sorted from the composer, and [drawsFor] keeps
     * that order, so stacking in the file matches stacking in the preview.
     */
    private inner class OverlayPass(
        private val overlays: List<NativeTimelineOverlay>,
        private val diagnostics: VideoDiagnostics,
    ) {

        private inner class VideoState {
            var decoder: ExportClipDecoder? = null
            var failed = false
        }

        private val videoStates = mutableMapOf<String, VideoState>()

        /**
         * Frees the decoder of every video overlay whose window has passed.
         *
         * Called at the **top** of each output frame, before the clip lanes
         * open anything. Codec instances are shared and scarce: releasing
         * expired overlays only when the overlays were drawn — after the lanes
         * had already tried to open — meant that at a clip boundary the next
         * clip's decoder competed with an overlay decoder that was about to be
         * freed anyway, and on devices near their codec limit the open lost.
         */
        fun releaseExpired(t: Double) {
            for (overlay in overlays) {
                if (overlay.isVideo && t >= overlay.endSeconds &&
                    videoStates.containsKey(overlay.id)
                ) {
                    videoStates.remove(overlay.id)?.decoder?.release()
                    renderer.overlays.releaseVideoLane(overlay.id)
                }
            }
        }

        fun drawsFor(t: Double): List<OverlayRenderer.Draw> {
            if (overlays.isEmpty()) return emptyList()

            val draws = mutableListOf<OverlayRenderer.Draw>()
            for (overlay in overlays) {
                if (!overlay.contains(t)) continue

                // Text with live glyph curves is the one overlay whose box-level
                // state is **not** what gets drawn, so it must not be what the
                // early-out consults either. `timing` is resolved here rather
                // than inside `textDraws` precisely so that the gate below and
                // the draw itself read the same value; see `textState`.
                val timing = if (overlay.isText) {
                    TextAnimationTiming.of(overlay, overlay.glyphs.size)
                } else {
                    null
                }
                val state = textState(overlay, t, timing)

                // The gate now tests the state that will actually be used.
                // For an image overlay, a video overlay, and text with no live
                // glyph curve that is `stateAt(t)` exactly as before; for text
                // whose glyphs animate it is the resting state, whose opacity
                // and scale are the overlay's authored values and so can only be
                // zero if the user authored them zero. A glyph animated to
                // nothing still drops itself inside `textDraws`, one glyph at a
                // time — which is the only place with the information to do it.
                if (state.opacity <= 0.0 || state.scale <= 0.0) continue

                val resolved = if (overlay.isVideo) {
                    listOfNotNull(videoDraw(overlay, t, state))
                } else if (overlay.isText) {
                    textDraws(overlay, t, state, timing!!)
                } else {
                    listOfNotNull(imageDraw(overlay, state))
                }
                draws.addAll(resolved)
            }
            return draws
        }

        /**
         * The box-level state an overlay will actually be drawn with.
         *
         * **Exactly one pass may animate the text.** `stateAt` is the image
         * overlay's whole-box animation and it switches on the *same*
         * `animationIn`/`animationOut` strings the per-glyph catalog reads, so
         * once a glyph resolves a curve, letting the box-level state through as
         * well would fade the text twice (opacity squared) and slide it twice.
         * When the glyph pass owns the animation the box rests; when it owns
         * nothing — no animation, or ids that resolve to no slot — the box-level
         * state is used untouched, which is what keeps an unanimated text
         * overlay producing exactly the draws it does today.
         *
         * This is also why it is a gate as well as a value. A loop animation
         * with no in-animation is the case that makes the difference load
         * bearing: `stateAt` would leave a text overlay's box at whatever the
         * legacy arms compute — potentially zero opacity at an endpoint — while
         * every glyph curve is perfectly alive, and gating on it would drop
         * whole frames of text out of the file.
         */
        private fun textState(
            overlay: NativeTimelineOverlay,
            t: Double,
            timing: TextAnimationTiming?,
        ): NativeTimelineOverlay.FrameState {
            if (timing != null && timing.isActive) return overlay.restingState()
            return overlay.stateAt(t)
        }

        private fun imageDraw(
            overlay: NativeTimelineOverlay,
            state: NativeTimelineOverlay.FrameState,
        ): OverlayRenderer.Draw? {
            val cached = renderer.overlays.cachedImageTexture(overlay.path)
            val (textureId, aspect) = cached ?: run {
                val bitmap = StillImageDecoder.decode(
                    overlay.path,
                    OVERLAY_IMAGE_MAX_PX,
                    OVERLAY_IMAGE_MAX_PX,
                )
                if (bitmap == null) {
                    diagnostics.failedOverlays++
                    return null
                }
                val uploaded = renderer.overlays.imageTexture(overlay.path, bitmap)
                // texImage2D copies the pixels; holding the bitmap as well
                // would double every overlay's memory for nothing.
                bitmap.recycle()
                uploaded
            }

            return draw(overlay, state, textureId, isExternal = false, aspect, null)
        }

        /**
         * One draw per glyph, all reading the overlay's atlas.
         *
         * The texture is uploaded once and every glyph samples its own cell, so
         * a 40-character text costs one upload and 40 quads — nothing for a GPU,
         * and what lets a later stage animate each character independently.
         *
         * **The quad is the whole padded cell, positioned so that the cell's
         * `src` sub-rect lands exactly on the glyph's box rect.** The cell is
         * bigger than the placement because its padding carries stroke and
         * shadow bleed; drawing only the placement would clip a shadow at the
         * letter's edge, while *placing* by the padded cell would composite the
         * bleed twice wherever neighbouring cells overlap. Drawing the cell
         * whole, anchored through `src`, gives the shadow its spill and each
         * texel exactly one contribution.
         */
        private fun textDraws(
            overlay: NativeTimelineOverlay,
            t: Double,
            /** Already resolved by [textState]'s rule — never `stateAt` raw. */
            state: NativeTimelineOverlay.FrameState,
            timing: TextAnimationTiming,
        ): List<OverlayRenderer.Draw> {
            val cached = renderer.overlays.cachedImageTexture(overlay.path)
            val (textureId, _) = cached ?: run {
                val bitmap = StillImageDecoder.decode(
                    overlay.path,
                    TEXT_ATLAS_MAX_PX,
                    TEXT_ATLAS_MAX_PX,
                )
                if (bitmap == null) {
                    diagnostics.failedOverlays++
                    return emptyList()
                }
                val uploaded = renderer.overlays.imageTexture(overlay.path, bitmap)
                bitmap.recycle()
                uploaded
            }

            val glyphCount = overlay.glyphs.size

            val base = draw(
                overlay,
                state,
                textureId,
                isExternal = false,
                contentAspect = 1.0,
                texMatrix = null,
            )

            return overlay.glyphs.mapIndexedNotNull { index, glyph ->
                val srcW = glyph.srcRight - glyph.srcLeft
                val srcH = glyph.srcBottom - glyph.srcTop
                // A degenerate sub-rect has no scale to solve for; skipping the
                // glyph loses one letter, dividing by it would place every quad
                // at infinity and lose the whole text.
                if (srcW <= 0.0 || srcH <= 0.0) return@mapIndexedNotNull null

                // The cell's `src` sub-rect must cover the box rect, so the full
                // cell is that much larger, and its origin sits back by the
                // bleed that precedes `src`.
                val cellWidth = (glyph.boxRight - glyph.boxLeft) / srcW
                val cellHeight = (glyph.boxBottom - glyph.boxTop) / srcH
                val cellLeft = glyph.boxLeft - glyph.srcLeft * cellWidth
                val cellTop = glyph.boxTop - glyph.srcTop * cellHeight

                val glyphState = timing.stateAt(t, index, glyphCount)
                // A glyph animated to nothing is dropped rather than drawn at
                // zero: a zero-area quad is wasted state changes, and a negative
                // scale would turn the letter inside out.
                if (glyphState.opacity <= 0.0 || glyphState.scale <= 0.0) {
                    return@mapIndexedNotNull null
                }

                // The catalog measures displacement in **glyph heights**, on
                // both axes — that is what keeps a diagonal slide diagonal and
                // makes the travel scale with the type size rather than with the
                // box. `Draw` wants box-height fractions, so the conversion is
                // the glyph's own height as a fraction of the box, applied to x
                // and y alike. Using the glyph's *width* for x would make a
                // narrow letter like "i" slide a fraction of the distance a "W"
                // does, and the word would come apart mid-animation.
                val glyphHeightInBox = glyph.boxBottom - glyph.boxTop

                base.copy(
                    opacity = base.opacity * glyphState.opacity,
                    srcRect = floatArrayOf(
                        glyph.atlasLeft.toFloat(),
                        glyph.atlasTop.toFloat(),
                        glyph.atlasRight.toFloat(),
                        glyph.atlasBottom.toFloat(),
                    ),
                    boxRect = floatArrayOf(
                        cellLeft.toFloat(),
                        cellTop.toFloat(),
                        (cellLeft + cellWidth).toFloat(),
                        (cellTop + cellHeight).toFloat(),
                    ),
                    glyphScale = glyphState.scale,
                    glyphRotation = glyphState.rotation,
                    glyphOffsetX = glyphState.offsetX * glyphHeightInBox,
                    glyphOffsetY = glyphState.offsetY * glyphHeightInBox,
                )
                // `fillProgress` is deliberately dropped: the renderer has no
                // colour-fill pass yet, and inventing one here would make
                // `colour_fill` export as something the preview does not play.
            }
        }

        private fun videoDraw(
            overlay: NativeTimelineOverlay,
            t: Double,
            state: NativeTimelineOverlay.FrameState,
        ): OverlayRenderer.Draw? {
            val videoState = videoStates.getOrPut(overlay.id) { VideoState() }
            if (videoState.failed) return null

            var decoder = videoState.decoder
            if (decoder == null) {
                if (videoStates.count { it.value.decoder != null } >= MAX_OVERLAY_DECODERS) {
                    videoState.failed = true
                    diagnostics.skippedOverlayDecoders++
                    return null
                }
                val lane = renderer.overlays.videoLane(overlay.id)
                val surface = lane.surface
                if (surface == null) {
                    videoState.failed = true
                    diagnostics.failedOverlays++
                    return null
                }
                decoder = ExportClipDecoder(overlay.path, surface)
                if (!decoder.open((overlay.sourceStart * 1_000_000L).toLong())) {
                    videoState.failed = true
                    diagnostics.failedOverlays++
                    renderer.overlays.releaseVideoLane(overlay.id)
                    return null
                }
                videoState.decoder = decoder
            }

            val lane = renderer.overlays.videoLane(overlay.id)
            val since = lane.frameSequence()
            if (decoder.advanceTo((overlay.sourceAt(t) * 1_000_000L).toLong())) {
                if (!lane.awaitFrameAfter(since, FRAME_WAIT_MS)) {
                    diagnostics.lateFrames++
                }
            }
            renderer.overlays.updateVideoLane(overlay.id)

            // Before its first frame lands there is nothing to sample; skipping
            // the draw shows the frame under it rather than undefined texels.
            if (lane.frameSequence() == 0L) return null

            return draw(
                overlay,
                state,
                lane.textureId,
                isExternal = true,
                decoder.displayAspect,
                lane.texMatrix,
            )
        }

        private fun draw(
            overlay: NativeTimelineOverlay,
            state: NativeTimelineOverlay.FrameState,
            textureId: Int,
            isExternal: Boolean,
            contentAspect: Double,
            texMatrix: FloatArray?,
        ): OverlayRenderer.Draw {
            return OverlayRenderer.Draw(
                textureId = textureId,
                isExternal = isExternal,
                contentAspect = if (contentAspect > 0.0) contentAspect else 1.0,
                centerX = overlay.centerX + state.offsetX,
                centerY = overlay.centerY + state.offsetY,
                boxWidth = overlay.boxWidth,
                boxHeight = overlay.boxHeight,
                scale = state.scale,
                rotation = overlay.rotation,
                opacity = state.opacity,
                texMatrix = texMatrix,
            )
        }

        fun release() {
            for ((id, state) in videoStates) {
                state.decoder?.release()
                renderer.overlays.releaseVideoLane(id)
            }
            videoStates.clear()
        }
    }
}

/**
 * One text overlay's animation windows, resolved once per overlay per frame.
 *
 * Splitting this out of the per-glyph loop is not only a saving: the in/out
 * durations are a property of the *overlay* (they depend on the glyph count, not
 * on which glyph), and computing them per glyph would invite a future edit that
 * made one letter's window differ from its neighbour's.
 */
private class TextAnimationTiming(
    private val inId: String?,
    private val outId: String?,
    private val loopId: String?,
    private val startSeconds: Double,
    private val endSeconds: Double,
    private val inSeconds: Double,
    private val outSeconds: Double,
    private val loopPeriod: Double,
) {

    /**
     * Whether any per-glyph curve will actually run.
     *
     * False means the glyph pass contributes nothing, and the caller keeps the
     * box-level animation — the path an unanimated text overlay takes today.
     */
    val isActive: Boolean
        get() = (inId != null && inSeconds > 0.0) ||
            (outId != null && outSeconds > 0.0) ||
            (loopId != null && loopPeriod > 0.0)

    /**
     * The glyph's state at [t], composed from whichever windows are live.
     *
     * The three windows compose by multiplication rather than by precedence.
     * In and out can both be live on a very short overlay — `resolveDurations`
     * compresses them to fit but does not separate them — and a loop runs
     * underneath both, so an entrance into a continuous wave does not stutter at
     * the handover. Each window that is *not* live contributes its resting
     * state, which is identity for all five channels.
     */
    fun stateAt(t: Double, index: Int, glyphCount: Int): TextGlyphState {
        var opacity = 1.0
        var offsetX = 0.0
        var offsetY = 0.0
        var scale = 1.0
        var rotation = 0.0

        fun apply(state: TextGlyphState) {
            opacity *= state.opacity
            offsetX += state.offsetX
            offsetY += state.offsetY
            scale *= state.scale
            rotation += state.rotation
        }

        val elapsed = t - startSeconds
        val remaining = endSeconds - t

        if (inId != null && inSeconds > 0.0 && elapsed < inSeconds) {
            apply(TextAnimationCurves.stateAt(inId, elapsed / inSeconds, index, glyphCount))
        }
        if (outId != null && outSeconds > 0.0 && remaining < outSeconds) {
            // `p` runs 0 at the window's start to 1 at the overlay's end, which
            // is the sense every out-curve is written in: it rests at `p == 0`.
            apply(
                TextAnimationCurves.stateAt(
                    outId,
                    (1.0 - remaining / outSeconds).coerceIn(0.0, 1.0),
                    index,
                    glyphCount,
                ),
            )
        }
        if (loopId != null && loopPeriod > 0.0) {
            // The loop's phase is its own, measured from the overlay's start and
            // wrapped by one cycle — not by the overlay's span. Every loop curve
            // is a whole number of cycles in `p`, so `p == 0` and `p == 1` are
            // the same instant of the motion and the wrap is invisible; deriving
            // the phase from the span instead would put the seam at an arbitrary
            // point of the wave and make it jump once per loop.
            var phase = (elapsed / loopPeriod) % 1.0
            // `%` keeps the sign of the dividend, and `elapsed` can be a hair
            // negative on the overlay's very first frame from float rounding.
            if (phase < 0.0) phase += 1.0
            apply(TextAnimationCurves.stateAt(loopId, phase, index, glyphCount))
        }

        return TextGlyphState(
            opacity = opacity.coerceIn(0.0, 1.0),
            offsetX = offsetX,
            offsetY = offsetY,
            scale = scale.coerceAtLeast(0.0),
            rotation = rotation,
        )
    }

    companion object {
        fun of(overlay: NativeTimelineOverlay, glyphCount: Int): TextAnimationTiming {
            // Ids resolve **by slot**, never by name alone. A legacy `'fade'`
            // means `fade_in` in the in-slot and `fade_out` in the out-slot, and
            // a bare in-only id sitting in the out-slot resolves to nothing at
            // all — the old widget layer played no out-animation for one, so
            // inventing one here would add an exit to saved drafts that never
            // had one.
            val inId = overlay.animationIn
                ?.let { TextAnimationCurves.resolveAnimationId(it, TextAnimationCategory.IN) }
            val outId = overlay.animationOut
                ?.let { TextAnimationCurves.resolveAnimationId(it, TextAnimationCategory.OUT) }
            val loopId = overlay.animationLoop
                ?.let { TextAnimationCurves.resolveAnimationId(it, TextAnimationCategory.LOOP) }

            val span = overlay.endSeconds - overlay.startSeconds

            // **One speed drives both the in and the out window**, and
            // `resolveDurations` — the port of the Dart's compression rule — is
            // the only thing that resolves them, so a short overlay's windows
            // squeeze identically on both sides of the boundary.
            //
            // `NativeTimelineOverlay` carries `speedIn` and `speedOut`
            // separately because that is the shape of the JSON, but **they are
            // expected to be equal**: the animation tab is a single Speed
            // slider. Honouring a divergence would mean a second copy of the
            // compression rule living here, kept in sync with the Dart across a
            // boundary nothing type-checks — the exact drift this whole file is
            // built to prevent — for a control the UI does not offer. If the two
            // ever genuinely need to differ, widen `resolveDurations` to take
            // both on *both* sides of the port and regenerate the fixture; do
            // not re-add a local re-derivation here.
            val durations = TextAnimationCurves.resolveDurations(
                spanSeconds = span,
                inAnimationId = overlay.animationIn,
                outAnimationId = overlay.animationOut,
                glyphCount = glyphCount,
                speed = overlay.speedIn,
            )

            val inSeconds = durations.inSeconds
            val outSeconds = durations.outSeconds

            val loopPeriod = if (loopId == null) {
                0.0
            } else {
                TextAnimationCurves.naturalDuration(loopId, glyphCount) / overlay.speedLoop
            }

            return TextAnimationTiming(
                inId = inId,
                outId = outId,
                loopId = loopId,
                startSeconds = overlay.startSeconds,
                endSeconds = overlay.endSeconds,
                inSeconds = inSeconds,
                outSeconds = outSeconds,
                loopPeriod = loopPeriod,
            )
        }
    }
}

/** Largest side an overlay image is decoded at; well above any overlay box. */
private const val OVERLAY_IMAGE_MAX_PX = 1024

/**
 * Largest side a text atlas is decoded at.
 *
 * Separate from [OVERLAY_IMAGE_MAX_PX] (1024) deliberately: that cap is generous
 * for a photo drawn into a small overlay box, but an atlas is rasterised at
 * export density — up to 4096 — and decoding it at 1024 would downscale it,
 * making exported text *blurrier* than the flat raster it replaced. The atlas is
 * already capped at the texture limit on the Dart side, so this cap only has to
 * not undercut it.
 */
private const val TEXT_ATLAS_MAX_PX = 4096
