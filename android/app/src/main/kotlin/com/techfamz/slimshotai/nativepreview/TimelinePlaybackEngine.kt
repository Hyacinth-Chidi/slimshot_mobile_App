package com.techfamz.slimshotai.nativepreview

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.image.ImageOutput
import com.techfamz.slimshotai.nativepreview.gl.TransitionDraw
import com.techfamz.slimshotai.nativepreview.gl.TransitionRenderer
import com.techfamz.slimshotai.nativepreview.gl.effects.ClipEffectController
import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * Drives timeline playback across two decoder lanes.
 *
 * A transition is an **overlap in timeline time**, not an animation that runs
 * after a clip ends. During the overlap both clips are genuinely decoding:
 * the outgoing clip plays out its tail on one lane while the incoming clip
 * plays its head on the other, and the GL shader composites the two live
 * textures. Nothing is frozen, captured, or paused for the transition's sake.
 *
 * ```
 *   clip A  ────────────────────────┐
 *                          ┌────────┴──── overlap ────┐
 *   clip B                 └──────────────────────────────────────
 *                          │<-- transition duration -->│
 * ```
 *
 * ### Clock
 *
 * One clock drives everything. The **outgoing** lane stays master for the whole
 * window because its position is already stable, while the incoming lane is
 * slaved to it — every source position, the shader progress, and both audio
 * gains are derived from the same `timelinePositionSeconds()`. Mastership hands
 * over at the window's end, where the outgoing clip is finished anyway.
 *
 * ### Lanes
 *
 * Clips alternate lanes only across a transition, so a run of plain cuts stays
 * on one lane and keeps ExoPlayer's gapless playlist behaviour. Within a lane,
 * temporally adjacent clips form a *block* that plays as one playlist; a gap
 * between blocks (where the other lane is on screen) is crossed by swapping the
 * lane's media items during the preroll, never in the critical path.
 */
@UnstableApi
internal class TimelinePlaybackEngine(
    private val context: Context,
    private val renderer: TransitionRenderer,
    private val onEvent: (Map<String, Any?>) -> Unit,
) {

    /** A run of temporally adjacent clips that can play as one playlist. */
    private class LaneBlock(val clips: List<NativeTimelineClip>) {
        val timelineStart: Double get() = clips.first().timelineStart
        val timelineEnd: Double get() = clips.last().timelineEnd

        fun contains(seconds: Double): Boolean =
            seconds >= timelineStart - EDGE_EPSILON && seconds < timelineEnd

        fun indexOfClipAt(seconds: Double): Int {
            for ((index, clip) in clips.withIndex()) {
                if (seconds < clip.timelineEnd || index == clips.lastIndex) return index
            }
            return 0
        }
    }

    private class Lane(val index: Int) {
        var player: ExoPlayer? = null
        var blocks: List<LaneBlock> = emptyList()
        var loadedBlockIndex = -1
        var surfaceAttached = false
        var pendingSurfaceAttach = false

        /**
         * Last values actually pushed to the player. The tick runs at 60Hz;
         * re-setting an unchanged volume or speed every frame makes ExoPlayer
         * tear down and rebuild its `AudioTrack`, which is audible.
         */
        var appliedVolume = Float.NaN
        var appliedSpeed = Double.NaN

        /** Guards the drift correction against becoming a seek loop. */
        var lastDriftSeekMs = 0L

        fun applyVolume(target: Float) {
            val clamped = target.coerceIn(0f, 1f)
            if (!appliedVolume.isNaN() && abs(appliedVolume - clamped) < VOLUME_EPSILON) return
            appliedVolume = clamped
            player?.volume = clamped
        }

        fun applySpeed(target: Double) {
            if (!appliedSpeed.isNaN() && abs(appliedSpeed - target) < SPEED_EPSILON) return
            appliedSpeed = target
            player?.playbackParameters = PlaybackParameters(target.toFloat())
        }

        fun blockIndexAt(seconds: Double): Int =
            blocks.indexOfFirst { it.contains(seconds) }

        fun currentClip(): NativeTimelineClip? {
            val block = blocks.getOrNull(loadedBlockIndex) ?: return null
            val player = player ?: return null
            return block.clips.getOrNull(player.currentMediaItemIndex)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val lanes = arrayOf(Lane(0), Lane(1))

    private var clips: List<NativeTimelineClip> = emptyList()
    private var transitions: List<NativeTimelineTransitionIntent> = emptyList()

    /**
     * The renderer's effect passes, kept matched to the clip on screen.
     *
     * Change-guarded inside: the ticker runs at ~60Hz and building a pass list
     * links a GL program, so an unguarded call would link and leak one per
     * frame. See [applyClipEffect] for which clip is resolved and why.
     */
    private val clipEffects = ClipEffectController(renderer)

    /**
     * Shape of the output frame, chosen in Dart from the tallest imported clip.
     * Zero means unresolved, in which case clips fill the frame as before.
     */
    private var canvasAspect = 0.0

    private var masterLane = 0
    private var volume = 1.0f
    private var isPlaying = false
    private var isReady = false
    private var hasSentCompleted = false
    private var pendingSeekSeconds: Double? = null
    private var lastPositionEventMs = 0L
    private var lastPlaybackLogMs = 0L
    private var activeWindowKey: String? = null
    private var prerolledWindowKey: String? = null
    private var released = false
    private var isScrubbing = false

    /**
     * Live pinch/drag transforms, keyed by clip id, overriding the timeline's
     * committed values while a gesture is in flight.
     *
     * A pinch updates sixty times a second, and pushing a whole recomposed
     * timeline per gesture frame would re-prepare the players — the same
     * mistake trimming made before it was gated. The gesture writes here
     * through one small channel call instead; the release commits to Dart
     * state, whose `setTimeline` then carries the same values and clears this.
     */
    private val transformOverrides = HashMap<String, DoubleArray>()

    fun setClipTransform(clipId: String, scale: Double, offsetX: Double, offsetY: Double) {
        transformOverrides[clipId] = doubleArrayOf(scale, offsetX, offsetY)
        applyLaneFits(timelinePositionSeconds())
    }

    /**
     * Last distinct position the player reported, and when it reported it.
     *
     * `ExoPlayer.getCurrentPosition()` is not obliged to advance every frame,
     * and for an image period it can sit on one value for the best part of a
     * second and then jump — most visibly on a photo that sits before a video,
     * where the upcoming video's renderers are being brought up. The picture is
     * fine (a photo is a still), but the editor's playhead is driven by these
     * events, so it stepped along the timeline once a second while the first
     * photo and the video either side of it ran smoothly.
     */
    private var clockSampleSeconds = Double.NaN
    private var clockSampleAtMs = 0L
    private var lastEmittedPositionSeconds = Double.NaN

    /** Surfaces arrive from the GL thread; a lane may exist before its surface. */
    private val laneSurfaces = arrayOfNulls<android.view.Surface>(2)

    val timelineDurationSeconds: Double
        get() = clips.maxOfOrNull { it.timelineEnd } ?: 0.0

    private val ticker = object : Runnable {
        override fun run() {
            if (!released) {
                tick()
                mainHandler.postDelayed(this, TICK_INTERVAL_MS)
            }
        }
    }

    init {
        mainHandler.post(ticker)
    }

    // ------------------------------------------------------------------ setup

    fun attachLaneSurface(laneIndex: Int, surface: android.view.Surface) {
        laneSurfaces[laneIndex] = surface
        val lane = lanes.getOrNull(laneIndex) ?: return
        if (lane.pendingSurfaceAttach) {
            lane.player?.setVideoSurface(surface)
            lane.surfaceAttached = true
            lane.pendingSurfaceAttach = false
        }
    }

    fun setTimeline(timeline: Map<String, Any?>) {
        // Where the user actually is, captured before the lanes are rebuilt.
        //
        // The editor pushes a timeline on every edit, and rebuilding the lanes
        // resets each player to its default position. Restarting from 0 left
        // the engine at the head of the timeline while the editor's playhead
        // stayed where the user had put it, so the next play or scrub appeared
        // to jump — most visibly as a middle clip that never got its turn.
        val positionBeforeRebuild = if (clips.isEmpty()) null else timelinePositionSeconds()

        val parsed = parseClips(timeline)
        if (parsed.isEmpty()) {
            emit("error", "message" to "Native preview timeline has no playable clips.")
            return
        }

        val unpreparedReverse = parsed.firstOrNull { it.needsReverseProxy }
        if (unpreparedReverse != null) {
            stopAll()
            emit(
                "needsReverseProxy",
                "clipId" to unpreparedReverse.id,
                "message" to "Clip ${unpreparedReverse.id} needs a prepared reverse proxy.",
            )
            return
        }

        for (clip in parsed) {
            if (!File(clip.playbackVideoPath).exists()) {
                emit("error", "message" to "Source video does not exist: ${clip.playbackVideoPath}")
                return
            }
        }

        val parsedTransitions = NativeTimelineTransitionIntents.fromTimeline(timeline)
        val canvas = timeline["canvas"] as? Map<*, *>

        // Property-only edits go the soft way: adopt the new values without
        // touching the players. Rebuilding the lanes replaces the media items
        // and re-prepares each player, which drops the decoder's current frame
        // — visible as the canvas flashing to the background — so committing a
        // pinch, changing a filter or nudging a volume must never pay that
        // price. Only edits that change *what plays* (trim, split, reorder,
        // add, remove, a transition) rebuild.
        if (isSamePlaybackStructure(parsed, parsedTransitions)) {
            clips = parsed
            transitions = parsedTransitions
            canvasAspect = (canvas?.get("aspectRatio") as? Number)?.toDouble() ?: 0.0
            applyCanvasLook(canvas)

            // The lanes' blocks hold clip *objects*, and every per-tick reader
            // — fits, grades, volumes, speeds — goes through
            // `lane.currentClip()`, which reads the blocks. Adopting the new
            // list without remapping the blocks left those readers on the old
            // objects, so a committed pinch snapped straight back to the old
            // scale the moment the gesture's override was cleared below.
            val byId = parsed.associateBy { it.id }
            for (lane in lanes) {
                lane.blocks = lane.blocks.map { block ->
                    LaneBlock(block.clips.map { old -> byId[old.id] ?: old })
                }
            }

            // The committed timeline now carries whatever the gesture wrote.
            transformOverrides.clear()
            // The next tick re-derives fits, grades, speeds and volumes from
            // the adopted clips; each setter is change-guarded, so unchanged
            // values cost nothing and changed ones apply without a reload.
            if (VERBOSE) Log.i(TAG, "setTimeline: soft update (properties only)")
            return
        }

        clips = parsed
        transitions = parsedTransitions
        canvasAspect = (canvas?.get("aspectRatio") as? Number)?.toDouble() ?: 0.0
        applyCanvasLook(canvas)
        hasSentCompleted = false
        isReady = false
        activeWindowKey = null
        prerolledWindowKey = null
        // The committed timeline now carries whatever a finished gesture wrote.
        transformOverrides.clear()

        // Link every shader this timeline can ask for, before playback needs it.
        renderer.warmUpShaders(
            transitions.map { it.type }.toSet(),
            includeImageVariants = clips.any { it.isImage },
        )
        renderer.clearTransition()

        buildLanes()

        masterLane = clips.first().laneIndex
        renderer.setActiveLane(masterLane)

        emit(
            "preparing",
            "isReady" to false,
            "transitionCount" to transitions.size,
            "laneCount" to lanes.count { it.blocks.isNotEmpty() },
        )

        loadBlockFor(lanes[masterLane], 0)
        // An explicit pending seek wins; otherwise hold the position the user
        // was already at, clamped in case the edit shortened the timeline.
        seek(
            pendingSeekSeconds
                ?: positionBeforeRebuild?.coerceIn(0.0, timelineDurationSeconds)
                ?: 0.0,
        )
        // After the seek, so the seek's lane bookkeeping does not undo it.
        prewarmTransitionLane()

        logTimeline()
    }

    /**
     * Dumps what the engine actually built.
     *
     * Playback problems here are nearly always a disagreement between the
     * timeline the editor thinks it sent and the lanes the engine derived from
     * it, and that disagreement is invisible from the outside. Filter logcat on
     * [TAG] to see it.
     */
    private fun logTimeline() {
        if (!VERBOSE) return

        Log.i(TAG, "timeline: ${clips.size} clips, ${transitions.size} transitions, " +
            "duration=${"%.3f".format(timelineDurationSeconds)}s, canvasAspect=$canvasAspect")
        clips.forEachIndexed { index, clip ->
            Log.i(
                TAG,
                "  clip[$index] lane=${clip.laneIndex} image=${clip.isImage} " +
                    "timeline=${"%.3f".format(clip.timelineStart)}..${"%.3f".format(clip.timelineEnd)} " +
                    "source=${"%.3f".format(clip.sourceStart)}..${"%.3f".format(clip.sourceEnd)} " +
                    "speed=${clip.speed} file=${File(clip.playbackVideoPath).name}",
            )
        }
        transitions.forEachIndexed { index, transition ->
            Log.i(
                TAG,
                "  transition[$index] ${transition.type} " +
                    "${"%.3f".format(transition.timelineStartSeconds)}.." +
                    "${"%.3f".format(transition.timelineEndSeconds)} " +
                    "clips ${transition.leftClipIndex}->${transition.rightClipIndex}",
            )
        }
        lanes.forEach { lane ->
            Log.i(
                TAG,
                "  lane[${lane.index}] blocks=${lane.blocks.size} " +
                    lane.blocks.joinToString { block ->
                        "[${block.clips.joinToString(",") { it.id }}]"
                    },
            )
        }
    }

    /** Periodic snapshot of the clock, so drift and stuck clips are visible. */
    private fun logPlaybackIfDue(position: Double) {
        if (!VERBOSE || !isPlaying) return
        val nowMs = SystemClock.elapsedRealtime()
        if (nowMs - lastPlaybackLogMs < PLAYBACK_LOG_INTERVAL_MS) return
        // Wall-clock delta, so a stalled ticker can be told apart from a
        // position that the player simply is not updating. Without it the two
        // look identical in the log.
        val sinceLastMs = if (lastPlaybackLogMs == 0L) 0 else nowMs - lastPlaybackLogMs
        lastPlaybackLogMs = nowMs

        val lane = lanes.getOrNull(masterLane)
        val player = lane?.player
        Log.i(
            TAG,
            "pos=${"%.3f".format(position)}/${"%.3f".format(timelineDurationSeconds)} " +
                "(+${sinceLastMs}ms wall) " +
                "master=$masterLane item=${player?.currentMediaItemIndex} " +
                "clip=${lane?.currentClip()?.id} " +
                "playerPos=${player?.currentPosition} state=${player?.playbackState} " +
                "playing=${player?.isPlaying} window=$activeWindowKey",
        )
    }

    /**
     * Splits each lane's clips into blocks of temporally adjacent clips.
     *
     * A lane only ever holds one block's media items at a time, so a gap in the
     * lane (where the other lane owns the screen) never forces ExoPlayer to
     * auto-advance into a clip whose turn has not come.
     */
    private fun buildLanes() {
        for (lane in lanes) {
            val laneClips = clips.filter { it.laneIndex == lane.index }
            val blocks = mutableListOf<LaneBlock>()
            var current = mutableListOf<NativeTimelineClip>()

            for (clip in laneClips) {
                val previous = current.lastOrNull()
                if (previous != null &&
                    abs(previous.timelineEnd - clip.timelineStart) > EDGE_EPSILON
                ) {
                    blocks.add(LaneBlock(current))
                    current = mutableListOf()
                }
                current.add(clip)
            }
            if (current.isNotEmpty()) blocks.add(LaneBlock(current))

            lane.blocks = blocks
            lane.loadedBlockIndex = -1
            if (blocks.isEmpty()) {
                lane.player?.stop()
                lane.player?.clearMediaItems()
                renderer.invalidateLane(lane.index)
            }
        }
    }

    /**
     * Lane 0 is created with the engine; lane 1 only when a timeline actually
     * needs an overlap, so a project without transitions never holds a second
     * hardware decoder.
     */
    private fun ensurePlayer(lane: Lane): ExoPlayer {
        lane.player?.let { return it }

        // Local files need almost no pre-buffer. The default load control waits
        // for 2.5s of buffered media before it will start playing, which on a
        // local clip is pure startup latency — it is what made the first
        // seconds of playback feel slow.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                /* minBufferMs = */ MIN_BUFFER_MS,
                /* maxBufferMs = */ MAX_BUFFER_MS,
                /* bufferForPlaybackMs = */ BUFFER_FOR_PLAYBACK_MS,
                /* bufferForPlaybackAfterRebufferMs = */ BUFFER_AFTER_REBUFFER_MS,
            )
            .build()

        val player = ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .build()
        player.volume = 0f
        lane.appliedVolume = 0f
        // A lane can be created mid-scrub (the second lane comes up at preroll).
        player.isScrubbingModeEnabled = isScrubbing
        // A lane's playlist only ever holds its *current* block, whose clips are
        // temporally adjacent, so ExoPlayer's gapless auto-advance is exactly
        // what we want within a block. (Setting pauseAtEndOfMediaItems here
        // stalled playback at every clip boundary.)
        player.addListener(laneListener(lane))

        // Images never reach the video surface: ExoPlayer decodes them through
        // ImageRenderer and hands out Bitmaps here instead. Without this a
        // photo clip plays — position advances, media items change — against a
        // black canvas.
        // Both callbacks below arrive on ExoPlayer's **playback** thread, not the
        // application thread. Nothing here may touch the player: any getter on
        // it calls `verifyApplicationThread()` and throws, which surfaces as an
        // ExoPlaybackException that kills the lane rather than as an obvious
        // threading error. `renderer` is safe — it takes the bitmap through a
        // @Volatile field and uploads it on the GL thread.
        player.setImageOutput(object : ImageOutput {
            override fun onImageAvailable(presentationTimeUs: Long, bitmap: Bitmap) {
                if (VERBOSE) {
                    Log.i(
                        TAG,
                        "lane[${lane.index}] image available pts=${presentationTimeUs / 1000}ms " +
                            "${bitmap.width}x${bitmap.height}",
                    )
                }
                // The bitmap alone is enough: the renderer measures it at
                // upload and derives the contain fit in the same GL pass that
                // first draws it, so no fit pushed from here (or from the
                // tick) can trail the picture.
                renderer.setLaneImage(lane.index, bitmap)
            }

            /**
             * Deliberately does **not** clear the lane's photo.
             *
             * This fires on the image renderer's own lifecycle, which is not
             * the same thing as the photo leaving the screen. With a photo
             * followed by a video in one playlist, ExoPlayer brings the video
             * renderer up while the photo period is still current — the video
             * decoder is created a beat *before* the item transition — and the
             * image renderer is disabled at that point. Clearing here dropped
             * the photo while it still had seconds left to show, so a photo
             * sitting between other clips looked skipped.
             *
             * `applyClipSpeeds` clears the lane instead, from the timeline's
             * own clip list, which is the only thing that actually knows
             * whether the current clip is a photo.
             */
            override fun onDisabled() {
                if (VERBOSE) Log.i(TAG, "lane[${lane.index}] image renderer disabled")
            }
        })

        lane.player = player

        val surface = laneSurfaces[lane.index]
        if (surface != null) {
            player.setVideoSurface(surface)
            lane.surfaceAttached = true
        } else {
            lane.pendingSurfaceAttach = true
        }
        return player
    }

    private fun laneListener(lane: Lane) = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            if (lane.index != masterLane) return

            when (playbackState) {
                Player.STATE_READY -> {
                    if (!isReady) {
                        isReady = true
                        emit("ready", "isReady" to true)
                    }
                }

                Player.STATE_BUFFERING -> emit("buffering", "isReady" to false)

                Player.STATE_ENDED -> {
                    // A lane only ever holds its current block, so ENDED means
                    // that block is spent — the timeline is over only if this
                    // was the final clip.
                    val isFinalBlock = lane.loadedBlockIndex >= lane.blocks.lastIndex
                    val isFinalClip = lane.blocks.lastOrNull()?.clips?.lastOrNull()?.id ==
                        clips.lastOrNull()?.id
                    if (isFinalBlock && isFinalClip && !hasSentCompleted) {
                        hasSentCompleted = true
                        isPlaying = false
                        lanes.forEach { it.player?.playWhenReady = false }
                        renderer.clearTransition()
                        emit("completed", "positionSeconds" to timelineDurationSeconds)
                    }
                }

                else -> Unit
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            val message = error.message ?: error.errorCodeName
            Log.e(TAG, "Lane ${lane.index} error: $message", error)
            if (lane.index == masterLane) {
                emit("error", "message" to message)
            } else {
                // A second decoder failed to come up. Playback continues on the
                // master lane; the shader falls back to showing one clip, which
                // is a hard cut rather than a stall.
                emit(
                    "warning",
                    "message" to "Transition lane unavailable on this device: $message",
                )
            }
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            if (!VERBOSE) return
            Log.i(
                TAG,
                "lane[${lane.index}] -> item ${lane.player?.currentMediaItemIndex} " +
                    "(${mediaItem?.mediaId}) reason=$reason",
            )
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            if (lane.index != masterLane) return
            if (videoSize.width > 0 && videoSize.height > 0) {
                onEvent(
                    mapOf(
                        "type" to "videoSize",
                        "width" to videoSize.width,
                        "height" to videoSize.height,
                    ),
                )
            }
        }
    }

    private fun loadBlockFor(lane: Lane, blockIndex: Int) {
        if (blockIndex < 0 || blockIndex >= lane.blocks.size) return
        if (lane.loadedBlockIndex == blockIndex) return

        val player = ensurePlayer(lane)
        val block = lane.blocks[blockIndex]

        // Deliberately no stop()/clearMediaItems(): stopping releases the
        // codec, so the next prepare() has to build a fresh decoder instance.
        // That teardown/rebuild is expensive on low-end hardware and was
        // landing right on the clip boundary. Replacing the items in place
        // lets ExoPlayer reuse the decoder when the format is unchanged.
        player.setMediaItems(block.clips.map { it.toMediaItem() }, true)
        player.prepare()
        lane.loadedBlockIndex = blockIndex
        renderer.invalidateLane(lane.index)
    }

    /**
     * Brings the second lane's decoder up while the timeline is being loaded,
     * before the user ever presses play.
     *
     * Creating a codec costs hundreds of milliseconds on low-end hardware. Left
     * until the first preroll it lands mid-playback and shows up as a stutter
     * at the first transition; doing it here moves that cost to load time,
     * where nothing is moving yet.
     */
    private fun prewarmTransitionLane() {
        val firstTransition = transitions.firstOrNull() ?: return
        val incoming = clips.getOrNull(firstTransition.rightClipIndex) ?: return
        val lane = lanes.getOrNull(incoming.laneIndex) ?: return
        if (lane.blocks.isEmpty()) return

        val blockIndex = lane.blockIndexAt(incoming.timelineStart)
        if (blockIndex < 0) return

        loadBlockFor(lane, blockIndex)
        val itemIndex = lane.blocks[blockIndex].clips.indexOfFirst { it.id == incoming.id }
        if (itemIndex < 0) return

        lane.player?.let {
            it.playWhenReady = false
            it.seekTo(itemIndex, 0L)
        }
        prerolledWindowKey = firstTransition.windowKey
    }

    // -------------------------------------------------------------- transport

    fun play() {
        if (clips.isEmpty()) return
        // Defensive: scrubbing mode drops the audio track, so playing while it
        // is still on would play silently. A lost scrub-end must not do that.
        setScrubbing(false)
        isPlaying = true
        hasSentCompleted = false
        applyPlaybackState()
        emit("playing", "isReady" to isReady)
    }

    fun pause() {
        isPlaying = false
        lanes.forEach { it.player?.playWhenReady = false }
        emit("paused", "isReady" to isReady)
    }

    fun setVolume(newVolume: Float) {
        volume = newVolume.coerceIn(0f, 1f)
        applyAudio(timelinePositionSeconds())
    }

    /**
     * Puts the lanes in and out of ExoPlayer's scrubbing mode.
     *
     * A timeline drag produces a seek per gesture frame. Issued as ordinary
     * seeks those are a decoder flush each, which on low-end hardware shows up
     * as the preview flashing while the handle moves. In scrubbing mode
     * ExoPlayer coalesces them instead: it holds at most one queued target,
     * lets a later target replace an unstarted one, and only issues the next
     * seek once a frame from the previous one has actually been rendered. It
     * also drops the audio and metadata tracks for the duration, which is what
     * makes the video seeks cheap enough to keep up with a finger.
     *
     * Must be turned back off on release, or playback keeps the scrubbing
     * track selection and stays silent.
     */
    fun setScrubbing(enabled: Boolean) {
        if (isScrubbing == enabled) return
        isScrubbing = enabled
        for (lane in lanes) {
            lane.player?.isScrubbingModeEnabled = enabled
        }
    }

    /**
     * Positions every lane for [seconds], including landing directly inside a
     * transition: both clips are seeked to their own source position for that
     * timeline instant and the shader is given the matching progress, so a
     * scrub into the middle of a blend renders correctly without playing up to
     * it first.
     */
    fun seek(seconds: Double) {
        if (clips.isEmpty()) {
            pendingSeekSeconds = seconds
            return
        }
        pendingSeekSeconds = null
        resetPositionSmoothing()

        val target = seconds.coerceIn(0.0, timelineDurationSeconds)
        val window = transitions.firstOrNull { it.contains(target) }

        if (window != null) {
            val outgoing = clips.getOrNull(window.leftClipIndex)
            val incoming = clips.getOrNull(window.rightClipIndex)
            if (outgoing != null && incoming != null) {
                masterLane = outgoing.laneIndex
                seekLaneTo(lanes[outgoing.laneIndex], target)
                seekLaneTo(lanes[incoming.laneIndex], target)
                activeWindowKey = window.windowKey
                prerolledWindowKey = window.windowKey
                renderer.setActiveLane(outgoing.laneIndex)
                renderer.setTransition(
                    TransitionDraw(
                        type = window.type,
                        progress = window.progressAt(target),
                        outgoingLane = outgoing.laneIndex,
                        incomingLane = incoming.laneIndex,
                    ),
                )
                applyPlaybackState()
                applyAudio(target)
                return
            }
        }

        val clip = clipAt(target) ?: clips.first()
        masterLane = clip.laneIndex
        activeWindowKey = null
        prerolledWindowKey = null
        renderer.clearTransition()
        renderer.setActiveLane(clip.laneIndex)
        seekLaneTo(lanes[clip.laneIndex], target)
        idleOtherLane(clip.laneIndex)
        applyPlaybackState()
        applyAudio(target)
    }

    private fun seekLaneTo(lane: Lane, timelineSeconds: Double) {
        val blockIndex = lane.blockIndexAt(timelineSeconds)
            .let { if (it >= 0) it else return }
        loadBlockFor(lane, blockIndex)

        val block = lane.blocks[blockIndex]
        val itemIndex = block.indexOfClipAt(timelineSeconds)
        val clip = block.clips[itemIndex]
        val inClipSourceSeconds =
            ((timelineSeconds - clip.timelineStart) * clip.speed).coerceAtLeast(0.0)

        lane.player?.seekTo(itemIndex, (inClipSourceSeconds * 1000.0).toLong())
    }

    private fun idleOtherLane(activeLaneIndex: Int) {
        val other = lanes.getOrNull(1 - activeLaneIndex) ?: return
        other.player?.let {
            it.playWhenReady = false
            it.volume = 0f
        }
    }

    /**
     * True while the export engine owns the renderer.
     *
     * The renderer's lane state (fits, grades, transition draw) has exactly one
     * writer at a time. During an export that writer is [VideoExportEngine],
     * per output frame; the ticker keeps running through an export and its
     * `applyLaneFits`/`applyLaneGrades`/`driveTransitions` would push the clip
     * under the *paused playhead* into the same lanes the export is setting for
     * its own clock — two writers, so every encoded frame took whichever fit
     * landed last. Visible as a photo flashing between two sizes whenever the
     * paused clip's fit differed from the exporting clip's (e.g. two photos
     * pinch-zoomed differently). Main-thread confined, like the ticker.
     */
    private var exportOwnsRenderer = false

    /**
     * Hands the lane surfaces over to the export engine.
     *
     * A `Surface` has one producer. The export decoders render into the very
     * same lane surfaces ExoPlayer fills during preview — which is what makes
     * an exported frame identical to a previewed one — so the players have to
     * let go first, or the two fight over the buffer queue.
     */
    fun detachSurfacesForExport() {
        isPlaying = false
        exportOwnsRenderer = true
        for (lane in lanes) {
            lane.player?.playWhenReady = false
            lane.player?.setVideoSurface(null)
            lane.surfaceAttached = false
        }
    }

    /** Gives the lane surfaces back to playback when the export is done. */
    fun reattachSurfacesAfterExport() {
        exportOwnsRenderer = false
        for (lane in lanes) {
            val surface = laneSurfaces[lane.index] ?: continue
            lane.player?.setVideoSurface(surface)
            lane.surfaceAttached = true
        }
        // The decoders were left wherever export finished with them.
        seek(timelinePositionSeconds())
    }

    fun stopAll() {
        isPlaying = false
        isReady = false
        clips = emptyList()
        transitions = emptyList()
        activeWindowKey = null
        prerolledWindowKey = null
        renderer.clearTransition()
        // `tick` returns early on an empty clip list, so an effect left set here
        // would outlive the timeline that asked for it and be drawn over
        // whatever loads next.
        clipEffects.apply(null, 0.0)
        for (lane in lanes) {
            lane.player?.stop()
            lane.player?.clearMediaItems()
            lane.loadedBlockIndex = -1
            renderer.invalidateLane(lane.index)
        }
    }

    fun release() {
        released = true
        mainHandler.removeCallbacks(ticker)
        // Dropped rather than released: the manager tears the renderer — and
        // with it the EGL context — down immediately after this, which takes
        // every effect program with it. Holding the objects past that would
        // leave passes naming program ids in a context that no longer exists.
        clipEffects.forget()
        for (lane in lanes) {
            lane.player?.setVideoSurface(null)
            lane.player?.release()
            lane.player = null
        }
    }

    // ------------------------------------------------------------------ clock

    /**
     * The one timeline clock. Everything else — shader progress, the incoming
     * lane's target position, both audio gains — is derived from this.
     */
    fun timelinePositionSeconds(): Double {
        val lane = lanes.getOrNull(masterLane) ?: return 0.0
        val player = lane.player ?: return 0.0
        val clip = lane.currentClip() ?: return 0.0
        val inClipSeconds = (player.currentPosition / 1000.0) / clip.speed
        return (clip.timelineStart + inClipSeconds).coerceIn(0.0, timelineDurationSeconds)
    }

    private fun clipAt(seconds: Double): NativeTimelineClip? {
        // The last clip that has started owns the instant, so inside an overlap
        // this resolves to the incoming clip.
        return clips.lastOrNull { seconds >= it.timelineStart - EDGE_EPSILON }
    }

    // ------------------------------------------------------------------- tick

    private fun tick() {
        // See [exportOwnsRenderer]: while an export runs, its engine is the
        // sole writer of renderer lane state. The ticker keeps rescheduling so
        // it resumes by itself when the surfaces come back.
        if (exportOwnsRenderer) return
        if (clips.isEmpty()) return

        val position = timelinePositionSeconds()

        if (isPlaying &&
            !hasSentCompleted &&
            position >= timelineDurationSeconds - COMPLETION_EPSILON
        ) {
            hasSentCompleted = true
            pause()
            renderer.clearTransition()
            emit("completed", "positionSeconds" to timelineDurationSeconds)
            return
        }

        driveTransitions(position)
        applyLaneFits(position)
        applyLaneGrades(position)
        applyClipEffect(position)
        applyClipSpeeds()
        applyAudio(position)
        sendPositionEventIfDue(position)
        logPlaybackIfDue(position)
    }

    /**
     * Keeps each lane's playback rate matched to the clip it is actually on.
     *
     * A lane auto-advances through its block on its own, so a clip with a
     * different speed would otherwise inherit the previous clip's rate —
     * `applyPlaybackState` only runs on play and seek. Change-guarded, so this
     * costs nothing on the ticks where nothing moved.
     */
    /**
     * The clip this lane is showing at [position] — or is about to show.
     *
     * Resolved from the **timeline clock**, not `currentMediaItemIndex`: the
     * player's index trails the boundary by a beat (and by much more mid-seek),
     * so per-clip looks — pinch transform, grade — wore the previous clip's
     * values at every cut. The timeline is the authority on what is on screen
     * (dead-ends entry 19); the player index stays right for player-side state
     * like speed and volume, which must follow what the *player* is doing.
     *
     * Between a lane's clips, the upcoming clip wins so a prerolled lane wears
     * its own fit and grade before the first blended frame; past the last
     * clip, the last one holds so an idle lane's state does not churn.
     */
    private fun laneClipFor(lane: Lane, position: Double): NativeTimelineClip? {
        var current: NativeTimelineClip? = null
        var upcoming: NativeTimelineClip? = null
        var past: NativeTimelineClip? = null
        for (clip in clips) {
            if (clip.laneIndex != lane.index) continue
            if (position < clip.timelineStart - EDGE_EPSILON) {
                if (upcoming == null) upcoming = clip
            } else if (position < clip.timelineEnd - EDGE_EPSILON) {
                current = clip
            } else {
                past = clip
            }
        }
        return current ?: upcoming ?: past
    }

    /**
     * Keeps each lane's grade matched to the clip it is actually on.
     *
     * A lane auto-advances through its block on its own, so without this a clip
     * would inherit the previous clip's filter. The renderer ignores an
     * unchanged matrix, so this costs nothing on the ticks where nothing moved.
     */
    private fun applyLaneGrades(position: Double) {
        for (lane in lanes) {
            if (lane.player == null) continue
            val clip = laneClipFor(lane, position) ?: continue
            renderer.setLaneColorMatrix(lane.index, clip.colorMatrix)
        }
    }

    /**
     * Keeps the renderer's effect passes matched to the clip on screen.
     *
     * Resolved from the **timeline clock** through [laneClipFor], exactly as
     * [applyLaneGrades] does: `lane.currentClip()` reads the player's media item
     * index, which trails the boundary by a beat and by much more mid-seek, so
     * every cut would draw a frame or two of the previous clip's effect. The
     * timeline is the authority on what is on screen (dead-ends entry 19).
     *
     * ### During a transition, the outgoing clip's effect owns the whole window
     *
     * Two overlapping clips may carry different effects, but a pass runs on the
     * **finished composited frame** — one frame, and two answers to what should
     * be drawn on it. The outgoing clip wins, which matches the rule the rest of
     * the window already follows: the outgoing lane is the transition master,
     * its clock drives the blend and it hands over at the window's end.
     *
     * The more correct alternative — render each lane into its own target and
     * effect them separately before the blend, the way per-clip *grades* are
     * applied — was rejected on cost, not on taste: it doubles the offscreen
     * targets and the pass count on exactly the hardware two live decoders
     * already strain. This looks like an oversight otherwise, so: it is a
     * decision, and the seam is where the effect changes, not where the picture
     * does.
     */
    private fun applyClipEffect(position: Double) {
        // Inside a window the outgoing clip is the one whose effect is drawn,
        // whichever lane happens to be master or active.
        val window = transitions.firstOrNull { it.contains(position) }
        val clip = if (window != null) {
            clips.getOrNull(window.leftClipIndex)
        } else {
            // Outside a window the master lane is the one on screen, so its clip
            // is the one whose effect applies.
            lanes.getOrNull(masterLane)?.let { laneClipFor(it, position) }
        } ?: return

        // **The effect clock is the timeline clock.** `position` is the same
        // value that drove the clip resolution two lines up, so the shader's
        // progress and the picture it is drawn over can never disagree — and
        // because it is a position rather than a frame count, the export loop
        // running faster than realtime reaches the identical value at the
        // identical instant of the clip. A counter or `System.nanoTime` here
        // would make the file differ from the canvas, which is the failure the
        // shared `composite` exists to prevent.
        // The intensity is resolved against that same progress, so an envelope
        // or a keyframe row shapes the strength on exactly the clock the shader
        // is drawn on. A flat parameter returns its base value, unchanged.
        val progress = clip.effectProgressAt(position)
        clipEffects.apply(
            clip.effectId,
            clip.effectIntensityAt(progress),
            progress,
        )
    }

    private fun applyClipSpeeds() {
        for (lane in lanes) {
            if (lane.player == null) continue
            val clip = lane.currentClip() ?: continue
            lane.applySpeed(clip.speed)

            // Moving off a photo onto a video: drop the still so the lane goes
            // back to decoder output. `ImageOutput.onDisabled` usually covers
            // this, but it is not guaranteed to fire on every item change.
            if (!clip.isImage) renderer.clearLaneImage(lane.index)
        }
    }

    /**
     * Hands the renderer the project-wide look: which part of the frame is
     * shown, and the colour grade.
     *
     * Both were Flutter-side effects wrapped around the preview widget, which
     * meant zoom magnified the letterbox bars along with the picture and the
     * grade never reached an export rendered from this engine.
     */
    private fun applyCanvasLook(canvas: Map<*, *>?) {
        // The letterbox fill. `blur` has no native implementation yet and falls
        // back to black rather than to the colour — a user who chose blur did
        // not choose that colour, and black is the least wrong stand-in.
        val backgroundType = canvas?.get("backgroundType") as? String ?: "black"
        val backgroundArgb = when (backgroundType) {
            "color" -> (canvas?.get("backgroundColor") as? Number)?.toInt() ?: BLACK
            else -> BLACK
        }
        renderer.setBackgroundColor(backgroundArgb)

        val rect = canvas?.get("contentRect") as? Map<*, *>
        if (rect != null) {
            val left = (rect["left"] as? Number)?.toFloat() ?: 0f
            val top = (rect["top"] as? Number)?.toFloat() ?: 0f
            val width = (rect["width"] as? Number)?.toFloat() ?: 1f
            val height = (rect["height"] as? Number)?.toFloat() ?: 1f
            renderer.setContentRect(left, top, width, height)
        } else {
            renderer.setContentRect(0f, 0f, 1f, 1f)
        }

        val matrix = (canvas?.get("colorMatrix") as? List<*>)
            ?.mapNotNull { (it as? Number)?.toFloat() }
            ?.toFloatArray()
        renderer.setColorMatrix(if (matrix != null && matrix.size >= 20) matrix else null)
    }

    /**
     * Fits each lane's current clip into the project canvas.
     *
     * Clips in one project can differ in shape. Rather than stretching a
     * landscape clip to fill a portrait frame, it is scaled to fit and the
     * space around it stays background — which is what the canvas rule (the
     * tallest imported clip decides the frame) is for.
     *
     * Cheap to run every tick: the renderer ignores an unchanged fit.
     */
    private fun applyLaneFits(position: Double) {
        if (canvasAspect <= 0.0) return

        for (lane in lanes) {
            if (lane.player == null) continue
            val clip = laneClipFor(lane, position) ?: continue
            // The clip's own pinch scale and drag position sit on top of the
            // contain fit — the fit is where the clip *starts*, the transform
            // is what the user did to it. A live gesture's override wins over
            // the committed value until the release lands in the timeline.
            //
            // Resolved at this clip's own progress, so a keyframed transform
            // moves across the clip. The renderer ignores an unchanged value,
            // so a clip carrying no keyframes costs exactly what it did before.
            val clipProgress = clip.clipProgressAt(position)
            val override = transformOverrides[clip.id]
            val scale = override?.get(0) ?: clip.canvasScaleAt(clipProgress)
            val panX = override?.get(1) ?: clip.canvasOffsetXAt(clipProgress)
            val panY = override?.get(2) ?: clip.canvasOffsetYAt(clipProgress)

            if (renderer.laneShowingImage(lane.index)) {
                // A photo's contain fit is derived by the renderer from the
                // bitmap actually drawn, in the same GL pass that first
                // samples it. Pushing the fit from this tick raced the
                // delivery: the bitmap reached the screen up to a tick before
                // the fit that matched it, so every differently-shaped photo
                // flashed the previous clip's shape at the cut. Only the clip
                // transform travels from the timeline side.
                renderer.setLaneImageTransform(
                    lane.index,
                    scale.toFloat(),
                    panX.toFloat(),
                    panY.toFloat(),
                )
            } else {
                val (fitX, fitY) = LaneFit.of(clip.sourceAspect, canvasAspect)
                renderer.setLaneFit(
                    lane.index,
                    fitX * scale.toFloat(),
                    fitY * scale.toFloat(),
                    panX.toFloat(),
                    panY.toFloat(),
                )
            }
        }
    }

    private fun driveTransitions(position: Double) {
        val window = transitions.firstOrNull { it.contains(position) }

        if (window != null) {
            val outgoing = clips.getOrNull(window.leftClipIndex) ?: return
            val incoming = clips.getOrNull(window.rightClipIndex) ?: return
            val incomingLane = lanes[incoming.laneIndex]

            if (activeWindowKey != window.windowKey) {
                activeWindowKey = window.windowKey
                // The outgoing lane stays master through the window: its clock
                // is already running and valid right up to its own end.
                masterLane = outgoing.laneIndex
                startIncoming(incomingLane, incoming, position)
            }

            keepIncomingInStep(incomingLane, incoming, position)

            renderer.setTransition(
                TransitionDraw(
                    type = window.type,
                    progress = window.progressAt(position),
                    outgoingLane = outgoing.laneIndex,
                    incomingLane = incoming.laneIndex,
                ),
            )
            return
        }

        if (activeWindowKey != null) {
            // The window just closed. The outgoing clip is spent; hand the
            // clock to the incoming lane, which is already playing in step.
            val finished = transitions.firstOrNull { it.windowKey == activeWindowKey }
            activeWindowKey = null
            renderer.clearTransition()

            val incoming = finished?.let { clips.getOrNull(it.rightClipIndex) }
            if (incoming != null) {
                masterLane = incoming.laneIndex
                renderer.setActiveLane(incoming.laneIndex)
                idleOtherLane(incoming.laneIndex)
            }
        }

        prerollUpcoming(position)
    }

    /**
     * Brings the incoming lane up before its window opens, so its first blended
     * frame is a real decoded frame rather than a black or stale one.
     */
    private fun prerollUpcoming(position: Double) {
        val upcoming = transitions.firstOrNull {
            position >= it.timelineStartSeconds - PREROLL_SECONDS &&
                position < it.timelineStartSeconds
        } ?: return

        if (prerolledWindowKey == upcoming.windowKey) return
        val incoming = clips.getOrNull(upcoming.rightClipIndex) ?: return
        val lane = lanes[incoming.laneIndex]

        prerolledWindowKey = upcoming.windowKey

        // Seek the lane to the incoming clip's first frame and hold it there,
        // muted. Decoding the first frame now means the window opens on a
        // picture that is already in the texture.
        val blockIndex = lane.blockIndexAt(incoming.timelineStart)
        if (blockIndex < 0) return
        loadBlockFor(lane, blockIndex)

        val block = lane.blocks[blockIndex]
        val itemIndex = block.clips.indexOfFirst { it.id == incoming.id }
        if (itemIndex < 0) return

        val player = lane.player ?: return
        lane.applyVolume(0f)
        player.playWhenReady = false

        // A seek costs a decoder flush. On every replay the lane is usually
        // already parked on exactly this frame from the previous pass, so
        // re-seeking would flush for nothing — and that flush lands right
        // before the window opens.
        val alreadyParked = player.currentMediaItemIndex == itemIndex &&
            player.currentPosition <= PARKED_TOLERANCE_MS
        if (!alreadyParked) {
            player.seekTo(itemIndex, 0L)
        }
    }

    private fun startIncoming(
        lane: Lane,
        incoming: NativeTimelineClip,
        position: Double,
    ) {
        val player = lane.player ?: run {
            // Preroll never ran — a seek dropped us straight into the window.
            seekLaneTo(lane, position)
            lane.player
        } ?: return

        lane.applySpeed(incoming.speed)
        // Give the lane a moment before drift correction is allowed to touch
        // it, so start-up latency is not mistaken for drift.
        lane.lastDriftSeekMs = SystemClock.elapsedRealtime()
        if (isPlaying) player.playWhenReady = true
    }

    /**
     * Keeps the slaved lane locked to the master clock.
     *
     * Correction is deliberately reluctant. A seek costs a decoder flush, and
     * an unconditional correction here is a trap: while the incoming lane is
     * still buffering its position stands still while the expected position
     * keeps advancing, so the drift only grows and every tick issues another
     * seek. That produces a flush storm — `flushed work; ignored`, `Discard
     * frames from previous generation`, and audio buffers being returned out of
     * order — which is far worse than the skew it was trying to fix.
     *
     * So: only correct while the lane is genuinely playing and ready, only when
     * the skew is big enough to see, and never more than once per
     * [DRIFT_SEEK_COOLDOWN_MS].
     */
    private fun keepIncomingInStep(
        lane: Lane,
        incoming: NativeTimelineClip,
        position: Double,
    ) {
        val player = lane.player ?: return
        val clip = lane.currentClip() ?: return
        if (clip.id != incoming.id) return
        if (!player.isPlaying || player.playbackState != Player.STATE_READY) return

        val expectedSeconds = (position - incoming.timelineStart) * incoming.speed
        val actualSeconds = player.currentPosition / 1000.0
        if (abs(actualSeconds - expectedSeconds) <= DRIFT_TOLERANCE_SECONDS) return

        val nowMs = SystemClock.elapsedRealtime()
        if (nowMs - lane.lastDriftSeekMs < DRIFT_SEEK_COOLDOWN_MS) return
        lane.lastDriftSeekMs = nowMs

        player.seekTo((expectedSeconds.coerceAtLeast(0.0) * 1000.0).toLong())
    }

    private fun applyPlaybackState() {
        for (lane in lanes) {
            if (lane.player == null) continue
            lane.currentClip()?.let { lane.applySpeed(it.speed) }
        }

        lanes.getOrNull(masterLane)?.player?.playWhenReady = isPlaying

        val window = transitions.firstOrNull { it.windowKey == activeWindowKey }
        if (window != null) {
            val incoming = clips.getOrNull(window.rightClipIndex)
            if (incoming != null) {
                lanes[incoming.laneIndex].player?.playWhenReady = isPlaying
            }
        }
    }

    /**
     * Audio follows the same timeline as the picture and never stops for a
     * transition.
     *
     * Across a window the two lanes are mixed with an **equal-power** crossfade
     * (`cos`/`sin`), which holds perceived loudness roughly constant instead of
     * dipping through the middle the way a linear fade would.
     */
    private fun applyAudio(position: Double) {
        val window = transitions.firstOrNull { it.contains(position) }

        if (window == null) {
            for (lane in lanes) {
                if (lane.player == null) continue
                val clip = lane.currentClip()
                lane.applyVolume(
                    if (lane.index == masterLane && clip != null) {
                        // **`applyVolume` change-guards on VOLUME_EPSILON**, and
                        // that guard is what makes a keyframed fade safe here:
                        // setting an unchanged volume every tick makes ExoPlayer
                        // rebuild its AudioTrack, which is fault 10 in this
                        // engine's own history. A fade only pushes when the
                        // value has actually moved.
                        (volume * clip.volumeAt(clip.clipProgressAt(position))).toFloat()
                    } else {
                        0f
                    },
                )
            }
            return
        }

        val outgoing = clips.getOrNull(window.leftClipIndex) ?: return
        val incoming = clips.getOrNull(window.rightClipIndex) ?: return
        val progress = window.progressAt(position).toDouble()

        // Each clip's own keyframed gain rides underneath the equal-power
        // crossfade rather than replacing it: a clip fading out by keyframes
        // that also transitions must do both.
        val outGain = outgoing.volumeAt(outgoing.clipProgressAt(position))
        val inGain = incoming.volumeAt(incoming.clipProgressAt(position))
        lanes[outgoing.laneIndex]
            .applyVolume((volume * outGain * cos(progress * PI / 2.0)).toFloat())
        lanes[incoming.laneIndex]
            .applyVolume((volume * inGain * sin(progress * PI / 2.0)).toFloat())
    }

    private fun sendPositionEventIfDue(position: Double) {
        // A paused engine has nothing to report. After completion it would
        // otherwise keep emitting its parked end position at ~30Hz — and the
        // editor's audio-tail ticker, walking the playhead past the video's
        // end, was overwritten right back to the video end on every event.
        if (!isPlaying) return
        val nowMs = SystemClock.elapsedRealtime()
        if (nowMs - lastPositionEventMs < POSITION_EVENT_INTERVAL_MS) return
        lastPositionEventMs = nowMs
        onEvent(
            mapOf(
                "type" to "position",
                "positionSeconds" to smoothedPosition(position, nowMs),
            ),
        )
    }

    /**
     * Fills in the gaps between the player's own position updates.
     *
     * Only the *reported* playhead is smoothed — transitions, drift correction
     * and every other decision still run on the raw clock, so this can never
     * put the engine and the player out of step.
     *
     * The extrapolation is in timeline seconds, which advance at wall-clock
     * rate whatever a clip's playback speed is, and it runs **only** while
     * `ExoPlayer.isPlaying` is true. That is exactly "playWhenReady, READY, and
     * not suppressed", so a stalled or buffering player freezes the playhead
     * instead of letting it run on — the playhead must never move while the
     * picture is stopped. The result is also held monotonic, so a coarse
     * update landing behind the estimate cannot make it jump backwards.
     */
    private fun smoothedPosition(raw: Double, nowMs: Long): Double {
        if (clockSampleSeconds.isNaN() ||
            abs(raw - clockSampleSeconds) > CLOCK_SAMPLE_EPSILON
        ) {
            clockSampleSeconds = raw
            clockSampleAtMs = nowMs
        }

        val advancing = isPlaying && lanes.getOrNull(masterLane)?.player?.isPlaying == true
        if (!advancing) {
            lastEmittedPositionSeconds = raw
            return raw
        }

        val estimate = clockSampleSeconds + (nowMs - clockSampleAtMs) / 1000.0
        var result = estimate.coerceIn(0.0, timelineDurationSeconds)
        if (!lastEmittedPositionSeconds.isNaN() && result < lastEmittedPositionSeconds) {
            result = lastEmittedPositionSeconds
        }
        lastEmittedPositionSeconds = result
        return result
    }

    /** Drops the smoothing state so the playhead lands exactly where it is put. */
    private fun resetPositionSmoothing() {
        clockSampleSeconds = Double.NaN
        clockSampleAtMs = 0L
        lastEmittedPositionSeconds = Double.NaN
    }

    // ------------------------------------------------------------------ parse

    /** Shared with export, so both walk exactly the same clips. */
    private fun parseClips(timeline: Map<String, Any?>): List<NativeTimelineClip> {
        return NativeTimelineClips.fromTimeline(timeline)
    }

    /**
     * Whether [next] plays the same media the current timeline does.
     *
     * Compares only the fields that decide what the players are loaded with —
     * identity, file, ranges, speed, lane, kind — plus the transition windows,
     * which decide lane assignment and prerolling. Grades, transforms, fits
     * and volumes are deliberately ignored: they are per-tick renderer state,
     * and differing there is exactly what makes a soft update worthwhile.
     */
    private fun isSamePlaybackStructure(
        next: List<NativeTimelineClip>,
        nextTransitions: List<NativeTimelineTransitionIntent>,
    ): Boolean {
        if (clips.isEmpty()) return false
        if (clips.size != next.size) return false
        if (transitions != nextTransitions) return false

        for (i in clips.indices) {
            val a = clips[i]
            val b = next[i]
            if (a.id != b.id ||
                a.playbackVideoPath != b.playbackVideoPath ||
                a.sourceStart != b.sourceStart ||
                a.sourceEnd != b.sourceEnd ||
                a.timelineStart != b.timelineStart ||
                a.timelineEnd != b.timelineEnd ||
                a.speed != b.speed ||
                a.laneIndex != b.laneIndex ||
                a.isImage != b.isImage
            ) {
                return false
            }
        }
        return true
    }

    private fun emit(type: String, vararg extras: Pair<String, Any?>) {
        onEvent(mapOf("type" to type) + extras.toMap())
    }

    private companion object {
        const val TAG = "SlimshotEngine"

        /** Playback tracing. Cheap, and the only way to see lane/clock state. */
        const val VERBOSE = true
        const val PLAYBACK_LOG_INTERVAL_MS = 500L
        const val TICK_INTERVAL_MS = 16L
        const val BLACK = 0xFF000000.toInt()

        /**
         * How often the playhead position is pushed to Flutter.
         *
         * This is the playhead's frame rate: the editor moves it only when an
         * event arrives, so at the previous 100ms the playhead advanced ten
         * times a second and visibly stepped along the timeline while the video
         * beside it played smoothly. 32ms is ~30Hz, which reads as continuous
         * motion without sending an event on every one of the 60Hz ticks.
         */
        const val POSITION_EVENT_INTERVAL_MS = 32L
        const val COMPLETION_EPSILON = 0.025
        const val EDGE_EPSILON = 0.001

        /**
         * How much the player's position must move to count as a fresh sample.
         *
         * Below one tick's worth, so ordinary smooth reporting resamples every
         * time and the estimate is never used; a frozen value is what triggers
         * the extrapolation.
         */
        const val CLOCK_SAMPLE_EPSILON = 0.008

        /**
         * How far ahead of a window the incoming lane is prepared.
         *
         * Generous on purpose: a decoder flush plus the first decodes can take
         * a few hundred milliseconds on low-end hardware, and anything that
         * spills past the window opening is visible as a stutter.
         */
        const val PREROLL_SECONDS = 1.2

        /**
         * Local media needs almost no pre-buffer, and the stock 2.5s
         * `bufferForPlayback` is felt directly as startup latency.
         */
        const val MIN_BUFFER_MS = 2_000
        const val MAX_BUFFER_MS = 15_000
        const val BUFFER_FOR_PLAYBACK_MS = 200
        const val BUFFER_AFTER_REBUFFER_MS = 400

        /**
         * Skew below this is ignored.
         *
         * Set high on purpose. The incoming lane inevitably starts a little
         * late — `play()` on a prepared player still takes tens of
         * milliseconds — and that offset then stays constant, because both
         * lanes run at the same rate. A steady ~100ms skew is invisible across
         * a half-second blend, whereas the seek used to correct it flushes the
         * decoder in the middle of that blend and is very visible. Correction
         * exists for a genuine desync, not for start-up latency.
         */
        const val DRIFT_TOLERANCE_SECONDS = 0.25

        /**
         * Hard floor between drift seeks. Also acts as a grace period after the
         * incoming lane starts, since [startIncoming] stamps it — so a typical
         * short transition completes without any correction at all.
         */
        const val DRIFT_SEEK_COOLDOWN_MS = 600L

        /** How close to a clip's first frame still counts as parked there. */
        const val PARKED_TOLERANCE_MS = 60L

        const val VOLUME_EPSILON = 0.01f
        const val SPEED_EPSILON = 0.001
    }
}

internal fun NativeTimelineClip.toMediaItem(): MediaItem {
    val builder = MediaItem.Builder()
        .setMediaId(id)
        .setUri(Uri.fromFile(File(playbackVideoPath)))

    // A photo has no source range to clip — it is shown for a duration.
    // Media3 renders a still as a timed media item once imageDurationMs is set,
    // so a photo flows through the same lane, texture and shader path as video
    // and costs no video decoder at all.
    if (isImage) {
        return builder
            .setImageDurationMs((timelineDuration * 1000.0).toLong().coerceAtLeast(1L))
            .build()
    }

    val isProxy = playbackVideoPath != sourceVideoPath
    val clipStartMs = if (isProxy) 0L else (sourceStart * 1000.0).toLong()
    val clipEndMs = if (isProxy) {
        ((sourceEnd - sourceStart) * 1000.0).toLong()
    } else {
        (sourceEnd * 1000.0).toLong()
    }

    return builder
        .setClippingConfiguration(
            MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(clipStartMs)
                .setEndPositionMs(clipEndMs)
                .build(),
        )
        .build()
}
