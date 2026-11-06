package com.techfamz.slimshotai.camera.react

import android.content.Context
import android.graphics.SurfaceTexture
import android.net.Uri
import android.opengl.EGLSurface
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.camera.core.SurfaceRequest
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.techfamz.slimshotai.export.ExportCapabilities
import com.techfamz.slimshotai.thumbnails.StillImageDecoder
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * REACT recorded live. Your camera (CameraX's preview, into [surfaceProvider])
 * and the video (an ExoPlayer here) are drawn together on every camera frame —
 * into a Flutter texture for the screen and, while recording, into an H.264
 * encoder — while [ReactAudioMixer] mixes the sound, so stop means the file
 * is finished. What the screen shows is the very drawing the file gets.
 *
 * Threads: the GL thread owns EGL, the textures and the video encoder; the
 * player lives on the main thread; the sound on the mixer's own; the file is
 * finished on a worker so the screen keeps moving. [events] is always called
 * on the main thread.
 */
@UnstableApi
internal class ReactLiveRecorder(
    private val context: Context,
    private val previewEntry: TextureRegistry.SurfaceTextureEntry,
    private val events: (Map<String, Any?>) -> Unit,
) {
    private enum class Source { NONE, VIDEO, PHOTO }

    private val main = Handler(Looper.getMainLooper())
    private val mainExecutor = ContextCompat.getMainExecutor(context)
    private val glThread = HandlerThread("slimshot-react-gl").apply { start() }
    private val gl = Handler(glThread.looper)
    private val worker = Executors.newSingleThreadExecutor { task -> Thread(task, "slimshot-react-file") }

    // The GL thread's.
    private val egl = ReactEgl()
    private lateinit var pbuffer: EGLSurface
    private var screen: EGLSurface? = null
    private val compositor = ReactCompositor()
    private var cameraTexture = 0
    private lateinit var cameraInput: SurfaceTexture
    private lateinit var cameraSurface: Surface
    private val cameraMatrix = FloatArray(16)
    private var videoTexture = 0
    private var videoInput: SurfaceTexture? = null
    private var videoSurface: Surface? = null
    private val videoMatrix = FloatArray(16)
    private var videoHasFrame = false
    private var photoTexture = 0
    private var encoder: ReactVideoEncoder? = null
    private var encoderSurface: EGLSurface? = null
    private var encodeWidth = 0
    private var encodeHeight = 0
    private var muxer: ReactMuxer? = null
    private var lastFileNanos = -1L
    private var framesEncoded = 0
    private var missed = MissedFrames()

    @Volatile private var videoFrameWaiting = false
    @Volatile private var scene = ReactScene.EMPTY
    @Volatile private var cameraTurns = 0
    @Volatile private var cameraMirrored = false
    @Volatile private var source = Source.NONE

    @Volatile var isRecording = false
        private set

    @Volatile private var stopping = false

    // The main thread's.
    private val clock = FileClock()
    private val media = MediaTimeMap()
    private var player: ExoPlayer? = null
    private var sourcePath: String? = null
    private var sourceDone: ((String?) -> Unit)? = null
    private var speakerOn = true
    private var playingBeforePause = false
    private var output: ReactOutput? = null
    private var mixer: ReactAudioMixer? = null
    private var ticks = 0
    private var released = false

    init {
        val ready = CountDownLatch(1)
        var failure: Throwable? = null
        gl.post {
            try {
                setupGl()
            } catch (error: Throwable) {
                failure = error
            }
            ready.countDown()
        }
        ready.await(SETUP_WAIT_SECONDS, TimeUnit.SECONDS)
        failure?.let {
            glThread.quitSafely()
            throw IllegalStateException("The live recorder could not start.", it)
        }
    }

    private fun setupGl() {
        egl.setup()
        pbuffer = egl.pbuffer()
        egl.makeCurrent(pbuffer)
        compositor.setup()
        cameraTexture = ReactCompositor.externalTexture()
        cameraInput = SurfaceTexture(cameraTexture).apply {
            setOnFrameAvailableListener({ onCameraFrame() }, gl)
        }
        cameraSurface = Surface(cameraInput)
        val screenTexture = previewEntry.surfaceTexture()
        screenTexture.setDefaultBufferSize(PREVIEW_WIDTH, PREVIEW_HEIGHT)
        screen = egl.windowSurface(screenTexture)
    }

    /**
     * CameraX's preview goes into the recorder's camera texture. The camera's
     * turn also goes to [onInfo]: CameraX keeps one listener per request, and
     * the channel reports it to Dart.
     */
    fun provideSurface(request: SurfaceRequest, onInfo: (SurfaceRequest.TransformationInfo) -> Unit) {
        val size = request.resolution
        cameraInput.setDefaultBufferSize(size.width, size.height)
        request.setTransformationInfoListener(mainExecutor) { info ->
            // Straight from the camera the texture's own matrix turns and
            // mirrors the picture; through a processor it arrives as the
            // sensor wrote it, and is turned here.
            val turned = info.hasCameraTransform()
            cameraTurns = if (turned) 0 else info.rotationDegrees / 90
            cameraMirrored = !turned && info.isMirroring
            onInfo(info)
        }
        request.provideSurface(cameraSurface, mainExecutor) { }
    }

    // ---- The source -------------------------------------------------------

    /** Opens what is reacted to; [done] gets null, or the reason it would not open. */
    fun setSource(path: String, photo: Boolean, done: (String?) -> Unit) {
        clearSource()
        sourcePath = path
        if (photo) {
            worker.execute {
                val bitmap = try {
                    StillImageDecoder.decode(path, PHOTO_MAX_PX, PHOTO_MAX_PX)
                } catch (error: Exception) {
                    null
                }
                if (bitmap == null) {
                    main.post { done(SOURCE_FAILED) }
                    return@execute
                }
                gl.post {
                    ReactCompositor.deleteTexture(photoTexture)
                    photoTexture = ReactCompositor.bitmapTexture(bitmap)
                    bitmap.recycle()
                    source = Source.PHOTO
                    main.post { done(null) }
                }
            }
            return
        }
        val surface = videoSurface() ?: return done(SOURCE_FAILED)
        val created = ExoPlayer.Builder(context).build()
        player = created
        sourceDone = done
        created.addListener(listener)
        created.setVideoSurface(surface)
        created.repeatMode = Player.REPEAT_MODE_OFF
        created.volume = if (speakerOn) 1f else 0f
        created.playWhenReady = false
        created.setMediaItem(MediaItem.fromUri(Uri.fromFile(File(path))))
        created.prepare()
        source = Source.VIDEO
    }

    fun clearSource() {
        player?.let {
            it.removeListener(listener)
            it.release()
        }
        player = null
        sourceDone = null
        sourcePath = null
        source = Source.NONE
        gl.post {
            ReactCompositor.deleteTexture(photoTexture)
            photoTexture = 0
            videoHasFrame = false
        }
    }

    /** The video's texture, made once on the GL thread. */
    private fun videoSurface(): Surface? {
        videoSurface?.let { return it }
        val made = CountDownLatch(1)
        gl.post {
            try {
                videoTexture = ReactCompositor.externalTexture()
                videoInput = SurfaceTexture(videoTexture).apply {
                    setOnFrameAvailableListener({ videoFrameWaiting = true }, gl)
                }
                videoSurface = Surface(videoInput)
            } catch (error: Exception) {
                Log.w(TAG, "no video texture", error)
            }
            made.countDown()
        }
        made.await(SETUP_WAIT_SECONDS, TimeUnit.SECONDS)
        return videoSurface
    }

    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            if (state == Player.STATE_READY) {
                sourceDone?.invoke(null)
                sourceDone = null
            }
            if (state == Player.STATE_ENDED) {
                sampleMedia()
                events(mapOf("type" to "reactVideoEnded"))
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) = sampleMedia()

        override fun onPlayerError(error: PlaybackException) {
            Log.w(TAG, "the video would not play", error)
            val waiting = sourceDone
            sourceDone = null
            if (waiting != null) {
                waiting(SOURCE_FAILED)
            } else {
                sampleMedia()
                events(mapOf("type" to "reactVideoEnded"))
            }
        }
    }

    fun setScene(next: ReactScene) {
        scene = next
    }

    /** A tap on the video mid-take: it stops on its frame, or plays on. */
    fun setPlaying(playing: Boolean) {
        player?.playWhenReady = playing
        sampleMedia()
    }

    fun setSpeakerOn(on: Boolean) {
        speakerOn = on
        player?.volume = if (on) 1f else 0f
    }

    private fun sampleMedia() {
        val current = player ?: return
        media.sample(System.nanoTime(), current.currentPosition, current.isPlaying)
    }

    // ---- Drawing ----------------------------------------------------------

    private fun onCameraFrame() {
        try {
            cameraInput.updateTexImage()
            cameraInput.getTransformMatrix(cameraMatrix)
            val arrival = System.nanoTime()
            val stamp = cameraInput.timestamp
            val input = videoInput
            if (videoFrameWaiting && input != null) {
                videoFrameWaiting = false
                input.updateTexImage()
                input.getTransformMatrix(videoMatrix)
                videoHasFrame = true
            }
            val drawn = scene
            val camera = ReactCompositor.Picture(cameraTexture, true, cameraMatrix, cameraTurns, cameraMirrored)
            val video = when (source) {
                Source.VIDEO -> if (videoHasFrame) ReactCompositor.Picture(videoTexture, true, videoMatrix) else null
                Source.PHOTO -> if (photoTexture != 0) ReactCompositor.Picture(photoTexture, false, ReactCompositor.IDENTITY) else null
                Source.NONE -> null
            }
            screen?.let {
                egl.makeCurrent(it)
                compositor.draw(drawn, PREVIEW_WIDTH, PREVIEW_HEIGHT, camera, video)
                egl.swap(it)
            }
            if (isRecording && !stopping) encodeFrame(FileClock.frameNanos(stamp, arrival), drawn, camera, video)
        } catch (error: Exception) {
            Log.w(TAG, "a REACT frame failed", error)
            if (isRecording && !stopping) main.post { fail(error) }
        }
    }

    private fun encodeFrame(
        frameNanos: Long,
        drawn: ReactScene,
        camera: ReactCompositor.Picture,
        video: ReactCompositor.Picture?,
    ) {
        val surface = encoderSurface ?: return
        val target = encoder ?: return
        val file = muxer ?: return
        val fileNanos = clock.fileNanos(frameNanos) ?: return
        if (fileNanos <= lastFileNanos) return
        egl.makeCurrent(surface)
        compositor.draw(drawn, encodeWidth, encodeHeight, camera, video)
        egl.presentationTime(surface, fileNanos)
        egl.swap(surface)
        target.drainTo(file, false)
        lastFileNanos = fileNanos
        framesEncoded++
        missed.onFrame(fileNanos)
    }

    // ---- Recording --------------------------------------------------------

    /**
     * Starts a take into [path] (or the gallery), at [shortSide]; [done] gets
     * null once it runs, or the reason it could not.
     */
    fun start(path: String, toGallery: Boolean, audio: Boolean, shortSide: Int, take: TakeSound, done: (String?) -> Unit) {
        if (isRecording || stopping) return done("A recording is already running.")
        val (width, height) = ExportCapabilities.alignedEncoderSize(shortSide, shortSide * 16 / 9)
        val videoPath = if (source == Source.VIDEO) sourcePath else null
        worker.execute {
            var opened: ReactOutput? = null
            var sound: ReactAudioMixer? = null
            try {
                val out = ReactOutput.open(context, path, toGallery).also { opened = it }
                val mix = ReactAudioMixer(audio, videoPath, take, clock, media).also { sound = it }
                val hasSound = mix.prepare()
                val file = ReactMuxer(out.stream, if (hasSound) 2 else 1)
                val video = ReactVideoEncoder(width, height, FRAME_RATE)
                val started = CountDownLatch(1)
                var glFailure: Exception? = null
                gl.post {
                    try {
                        encoderSurface = egl.windowSurface(video.inputSurface)
                        encoder = video
                        muxer = file
                        encodeWidth = width
                        encodeHeight = height
                        lastFileNanos = -1L
                        framesEncoded = 0
                        missed = MissedFrames()
                        clock.start(System.nanoTime())
                        isRecording = true
                    } catch (error: Exception) {
                        glFailure = error
                    }
                    started.countDown()
                }
                started.await(SETUP_WAIT_SECONDS, TimeUnit.SECONDS)
                glFailure?.let {
                    video.release()
                    throw it
                }
                if (hasSound) mix.start(file) else mix.release()
                main.post {
                    output = out
                    mixer = if (hasSound) mix else null
                    player?.play()
                    sampleMedia()
                    ticks = 0
                    main.postDelayed(tick, TICK_MS)
                    done(null)
                }
            } catch (error: Exception) {
                Log.w(TAG, "the live take could not start", error)
                sound?.release()
                opened?.abandon()
                main.post { done(START_FAILED) }
            }
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            if (!isRecording || released) return
            sampleMedia()
            if (++ticks % (PROGRESS_MS / TICK_MS).toInt() == 0) emitProgress()
            main.postDelayed(this, TICK_MS)
        }
    }

    private fun emitProgress() {
        events(
            mapOf(
                "type" to "recording",
                "durationMs" to clock.durationNanos(System.nanoTime()) / 1_000_000L,
                "paused" to clock.isPaused,
            ),
        )
    }

    fun pause() {
        if (!isRecording || clock.isPaused) return
        clock.pause(System.nanoTime())
        playingBeforePause = player?.playWhenReady == true
        player?.pause()
        sampleMedia()
        emitProgress()
    }

    fun resume() {
        if (!isRecording || !clock.isPaused) return
        clock.resume(System.nanoTime())
        if (playingBeforePause) player?.play()
        sampleMedia()
        emitProgress()
    }

    /** Finishes the take; [done] gets `{path, uri?, durationMs, frames, missedFrames}`, or nothing usable. */
    fun stop(done: (Map<String, Any?>) -> Unit) {
        if (!isRecording || stopping) return done(emptyMap())
        stopping = true
        player?.pause()
        sampleMedia()
        main.removeCallbacks(tick)
        val sound = mixer
        val out = output
        mixer = null
        output = null
        gl.post {
            val video = encoder
            val file = muxer
            try {
                video?.signalEndOfStream()
                if (file != null) video?.drainTo(file, true)
            } catch (error: Exception) {
                Log.w(TAG, "the picture did not finish cleanly", error)
            }
            val lastNanos = lastFileNanos
            val frames = framesEncoded
            val lost = missed.missed
            egl.makeCurrent(pbuffer)
            egl.releaseSurface(encoderSurface)
            encoderSurface = null
            video?.release()
            encoder = null
            muxer = null
            isRecording = false
            worker.execute {
                try {
                    sound?.finish(if (lastNanos >= 0) lastNanos + FRAME_NANOS else 0)
                } catch (error: Exception) {
                    Log.w(TAG, "the sound did not finish cleanly", error)
                }
                val finished = file?.close() == true && frames > 0
                val kept = if (finished) out?.publish() else null.also { out?.abandon() }
                val answer: Map<String, Any?> = if (kept == null) {
                    emptyMap()
                } else {
                    mapOf(
                        "path" to kept.first,
                        "uri" to kept.second,
                        "durationMs" to (lastNanos + FRAME_NANOS) / 1_000_000L,
                        "frames" to frames,
                        "missedFrames" to lost,
                    )
                }
                main.post {
                    stopping = false
                    player?.seekTo(0)
                    done(answer)
                }
            }
        }
    }

    /** The recorder broke mid-take: say so, and keep what was written. */
    private fun fail(error: Exception) {
        if (!isRecording || stopping) return
        events(mapOf("type" to "reactFailed", "message" to (error.message ?: "The live recorder stopped.")))
        stop { answer -> events(mapOf("type" to "recordingEnded") + answer) }
    }

    /** Lets everything go. A take still running is thrown away. */
    fun release() {
        if (released) return
        released = true
        main.removeCallbacks(tick)
        player?.let {
            it.removeListener(listener)
            it.release()
        }
        player = null
        mixer?.release()
        mixer = null
        output?.abandon()
        output = null
        val done = CountDownLatch(1)
        gl.post {
            try {
                encoder?.release()
                encoder = null
                egl.makeCurrent(pbuffer)
                egl.releaseSurface(encoderSurface)
                egl.releaseSurface(screen)
                screen = null
                compositor.release()
                ReactCompositor.deleteTexture(cameraTexture)
                ReactCompositor.deleteTexture(videoTexture)
                ReactCompositor.deleteTexture(photoTexture)
                cameraSurface.release()
                cameraInput.release()
                videoSurface?.release()
                videoInput?.release()
                egl.releaseSurface(pbuffer)
                egl.release()
            } catch (error: Exception) {
                Log.w(TAG, "the live recorder did not let go cleanly", error)
            }
            done.countDown()
        }
        done.await(SETUP_WAIT_SECONDS, TimeUnit.SECONDS)
        glThread.quitSafely()
        worker.shutdown()
    }

    private companion object {
        const val TAG = "SlimshotCamera"
        const val PREVIEW_WIDTH = 720
        const val PREVIEW_HEIGHT = 1280
        const val PHOTO_MAX_PX = 2048
        const val FRAME_RATE = 30
        const val FRAME_NANOS = 33_333_333L
        const val TICK_MS = 30L
        const val PROGRESS_MS = 240L
        const val SETUP_WAIT_SECONDS = 3L
        const val SOURCE_FAILED = "This can't be opened."
        const val START_FAILED = "The reaction could not start recording."
    }
}
