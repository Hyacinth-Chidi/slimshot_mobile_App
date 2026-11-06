package com.techfamz.slimshotai.camera

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import android.util.Size
import android.view.Display
import android.view.OrientationEventListener
import android.view.Surface
import android.view.WindowManager
import android.provider.MediaStore
import androidx.camera.core.AspectRatio
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraState
import androidx.camera.core.DisplayOrientedMeteringPointFactory
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.MirrorMode
import androidx.camera.core.Preview
import androidx.camera.core.UseCase
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.PendingRecording
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.media3.common.util.UnstableApi
import com.techfamz.slimshotai.camera.react.ReactCapabilityProbe
import com.techfamz.slimshotai.camera.react.ReactLiveRecorder
import com.techfamz.slimshotai.camera.react.ReactScene
import com.techfamz.slimshotai.camera.react.TakeSound
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * `slimshot_ai/camera`: the Camera feature's camera, CameraX driven from here,
 * its preview a Flutter texture (the editor's own path to the screen).
 *
 * One camera at a time, bound to the activity's lifecycle so it closes when
 * the app leaves the screen. **Only the current mode's use cases are bound**
 * — preview + photo, or preview + video — because a low-end device may refuse
 * all three at once, and a camera that will not open is worse than the
 * moment a mode switch takes. Both modes frame **16:9** (portrait 9:16), the
 * format the editor's canvas and short-form video share, so what the screen
 * shows is what a photo or a video holds.
 *
 * - `open({lens, mode, flash})` / `configure({lens, mode, flash})` → [describe]. The mode's
 *   flash comes with the bind, so a torch is never switched on for the mode being left.
 * - `setFlash({mode})`: `off` / `auto` / `on` — a photo's flash; on in video
 *   mode it is the torch.
 * - `setZoom({ratio})`, `focus({x, y})` in display-oriented 0..1 of the
 *   uncropped preview.
 * - `takePhoto({path})` → `{path}`; `startRecording({path, audio})`,
 *   `pauseRecording`, `resumeRecording`, `stopRecording` → `{path, durationMs}`.
 * - `close()`.
 *
 * Events on `slimshot_ai/camera_events`: `preview` (buffer size, rotation,
 * mirroring, whether the camera turned the picture itself — CameraX tells these
 * after the surface is handed over), `camera` (open, or closed with the reason —
 * another app took it), `recording` (duration, paused), `recordingEnded` (a
 * recording that ended without being asked to — the app left the screen).
 *
 * Photos and videos are turned to the way the phone is **held**
 * ([orientation]), while the screen stays upright: a photo taken sideways is a
 * landscape photo, as every camera app saves it.
 *
 * **REACT recorded live** is the mode `react_live` (with `liveShortSide`,
 * 1080 or 720): Preview only, into a [ReactLiveRecorder] that draws your
 * camera and the video together into its own Flutter texture — the
 * `textureId` answered — and, while recording, into the file. The record
 * calls are the video mode's, routed to it; `reactLiveFacts`, `reactSource`,
 * `reactClearSource`, `reactScene`, `reactPlayback` and `reactSound` are its
 * own, and it says `reactVideoEnded` and `reactFailed`. The app leaving the
 * screen mid-take finishes the file and says `recordingEnded`, as the video
 * mode does.
 */
@OptIn(UnstableApi::class)
class CameraChannel(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val textureRegistry: TextureRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val mainExecutor = ContextCompat.getMainExecutor(context)

    /** Bakes a selfie's mirror into its pixels ([PhotoBaker]) off the main thread. */
    private val photoWorker: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "slimshot-camera-photo").apply { isDaemon = true }
    }
    private var events: EventChannel.EventSink? = null

    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var texture: TextureRegistry.SurfaceTextureEntry? = null

    /**
     * One [Surface] for the texture, kept across rebinds: a new one per bind
     * would connect a second producer to the texture's buffer queue while the
     * camera may still hold the first.
     */
    private var previewSurface: Surface? = null
    private var imageCapture: ImageCapture? = null
    private var videoCapture: VideoCapture<Recorder>? = null

    private var lens = LENS_BACK
    private var mode = MODE_PHOTO
    private var flash = FLASH_OFF
    private var previewSize: Size? = null
    private var rotationDegrees = 0
    private var mirrored = false
    private var cameraTransform = true
    private var observedCamera: Camera? = null

    private var recording: Recording? = null
    private var recordingPath: String? = null

    /** The sound settings of the live take being started. */
    private var pendingTake = TakeSound.PLAIN

    /** REACT recorded live: the recorder and the Flutter texture it draws into. */
    private var live: ReactLiveRecorder? = null
    private var liveEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var liveShortSide = 1080

    /** The app leaving the screen mid-take: the live file is finished with what it has. */
    private val lifecycleWatcher = LifecycleEventObserver { _, event ->
        if (event == Lifecycle.Event.ON_STOP) {
            val recorder = live
            if (recorder != null && recorder.isRecording) {
                recorder.stop { answer -> events?.success(mapOf("type" to "recordingEnded") + answer) }
            }
        }
    }

    init {
        lifecycleOwner.lifecycle.addObserver(lifecycleWatcher)
    }

    /** The recording goes into the gallery, its file found at the end. */
    private var recordingToGallery = false
    private var recordingPaused = false
    private var recordedMs = 0L
    private var pendingStop: MethodChannel.Result? = null

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open", "configure" -> {
                lens = call.argument<String>("lens") ?: lens
                mode = call.argument<String>("mode") ?: mode
                flash = call.argument<String>("flash") ?: flash
                call.argument<Int>("liveShortSide")?.let { liveShortSide = it }
                withProvider(result) { provider ->
                    try {
                        bind(provider)
                        result.success(describe())
                    } catch (error: Exception) {
                        // CameraX's own words name surface combinations and
                        // camera ids; the user is told what happened.
                        Log.e(TAG, "camera bind failed", error)
                        result.error("camera_unavailable", CAMERA_UNAVAILABLE, null)
                    }
                }
            }

            "setFlash" -> {
                flash = call.argument<String>("mode") ?: FLASH_OFF
                applyFlash()
                result.success(null)
            }

            "setZoom" -> {
                val ratio = call.argument<Number>("ratio")?.toFloat() ?: 1f
                camera?.cameraControl?.setZoomRatio(ratio)
                result.success(null)
            }

            "focus" -> {
                focus(
                    call.argument<Number>("x")?.toFloat() ?: 0.5f,
                    call.argument<Number>("y")?.toFloat() ?: 0.5f,
                )
                result.success(null)
            }

            "reactLiveFacts" -> photoWorker.execute {
                val facts = try {
                    ReactCapabilityProbe.facts()
                } catch (error: Exception) {
                    Log.w(TAG, "REACT live facts failed", error)
                    emptyMap()
                }
                mainExecutor.execute { result.success(facts) }
            }
            "reactSource" -> {
                val recorder = live
                val path = call.argument<String>("path")
                if (recorder == null || path.isNullOrEmpty()) {
                    result.error("react_source_failed", REACT_SOURCE_FAILED, null)
                } else {
                    recorder.setSource(path, call.argument<Boolean>("photo") == true) { error ->
                        if (error == null) result.success(null) else result.error("react_source_failed", error, null)
                    }
                }
            }
            "reactClearSource" -> {
                live?.clearSource()
                result.success(null)
            }
            "reactScene" -> {
                live?.setScene(ReactScene.fromMap(call.arguments as? Map<*, *>))
                result.success(null)
            }
            "reactPlayback" -> {
                live?.setPlaying(call.argument<Boolean>("playing") == true)
                result.success(null)
            }
            "reactSound" -> {
                live?.setSpeakerOn(call.argument<Boolean>("on") != false)
                result.success(null)
            }
            "takePhoto" -> takePhoto(
                call.argument<String>("path"),
                call.argument<Boolean>("gallery") ?: false,
                result,
            )
            "startRecording" -> startRecording(
                call.argument<String>("path").also { pendingTake = TakeSound.fromMap(call.argument<Map<*, *>>("react")) },
                call.argument<Boolean>("audio") ?: true,
                call.argument<Boolean>("gallery") ?: false,
                result,
            )
            "deleteShot" -> {
                val uri = call.argument<String>("uri")
                result.success(uri != null && GalleryShots.delete(context, Uri.parse(uri)))
            }
            "publishVideo" -> publishVideo(call.argument<String>("path"), result)
            "headphones" -> result.success(Headphones.connected(context))
            "pauseRecording" -> {
                live?.takeIf { mode == MODE_REACT_LIVE }?.pause() ?: recording?.pause()
                result.success(null)
            }
            "resumeRecording" -> {
                live?.takeIf { mode == MODE_REACT_LIVE }?.resume() ?: recording?.resume()
                result.success(null)
            }
            "stopRecording" -> stopRecording(result)
            "close" -> {
                close()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun withProvider(result: MethodChannel.Result, then: (ProcessCameraProvider) -> Unit) {
        provider?.let { return then(it) }
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            try {
                val ready = future.get()
                provider = ready
                then(ready)
            } catch (error: Exception) {
                Log.e(TAG, "camera provider failed", error)
                result.error("camera_unavailable", CAMERA_UNAVAILABLE, null)
            }
        }, mainExecutor)
    }

    private fun bind(provider: ProcessCameraProvider) {
        // A recording belongs to the use case being replaced.
        recording?.close()
        recording = null
        provider.unbindAll()
        camera = null
        if (mode == MODE_REACT_LIVE) return bindLive(provider)
        releaseLive()

        val selector = selectorFor(provider)
        val entry = texture ?: textureRegistry.createSurfaceTexture().also { texture = it }
        val frame = ResolutionSelector.Builder()
            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY)
            .build()
        val targetRotation = displayRotation()

        val preview = Preview.Builder()
            .setResolutionSelector(frame)
            .setTargetRotation(targetRotation)
            .build()
        preview.setSurfaceProvider(mainExecutor) { request ->
            val size = request.resolution
            val surfaceTexture = entry.surfaceTexture()
            surfaceTexture.setDefaultBufferSize(size.width, size.height)
            previewSize = size
            val surface = previewSurface ?: Surface(surfaceTexture).also { previewSurface = it }
            request.setTransformationInfoListener(mainExecutor) { info ->
                rotationDegrees = info.rotationDegrees
                mirrored = info.isMirroring
                // Straight from the camera, the texture's own transform turns and
                // mirrors the picture; through a processor it arrives as the sensor
                // wrote it and the screen has to turn it.
                cameraTransform = info.hasCameraTransform()
                emitPreview()
            }
            // Kept for the next bind; released with the texture in close().
            request.provideSurface(surface, mainExecutor) { }
            emitPreview()
        }

        val useCases = mutableListOf<UseCase>(preview)
        imageCapture = null
        videoCapture = null
        if (mode == MODE_VIDEO) {
            val recorder = Recorder.Builder()
                .setQualitySelector(
                    QualitySelector.from(
                        Quality.FHD,
                        FallbackStrategy.lowerQualityOrHigherThan(Quality.SD),
                    ),
                )
                .setAspectRatio(AspectRatio.RATIO_16_9)
                .build()
            // Mirrored as it was seen, the front camera's convention.
            val capture = VideoCapture.Builder(recorder)
                .setMirrorMode(MirrorMode.MIRROR_MODE_ON_FRONT_ONLY)
                .setTargetRotation(targetRotation)
                .build()
            videoCapture = capture
            useCases += capture
        } else {
            val capture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .setResolutionSelector(frame)
                .setTargetRotation(targetRotation)
                .build()
            imageCapture = capture
            useCases += capture
        }

        val bound = provider.bindToLifecycle(lifecycleOwner, selector, *useCases.toTypedArray())
        camera = bound
        observe(bound)
        orientation.enable()
        applyFlash()
    }

    /**
     * REACT recorded live: Preview only, into the recorder — a low-end phone is
     * never asked for more than one use case here.
     */
    private fun bindLive(provider: ProcessCameraProvider) {
        val selector = selectorFor(provider)
        val recorder = live ?: run {
            val entry = textureRegistry.createSurfaceTexture().also { liveEntry = it }
            ReactLiveRecorder(context, entry) { event -> events?.success(event) }.also { live = it }
        }
        val frame = ResolutionSelector.Builder()
            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY)
            .build()
        val preview = Preview.Builder()
            .setResolutionSelector(frame)
            .setTargetRotation(displayRotation())
            .build()
        preview.setSurfaceProvider(mainExecutor) { request ->
            previewSize = request.resolution
            recorder.provideSurface(request) { info ->
                rotationDegrees = info.rotationDegrees
                mirrored = info.isMirroring
                cameraTransform = info.hasCameraTransform()
                emitPreview()
            }
            emitPreview()
        }
        imageCapture = null
        videoCapture = null
        val bound = provider.bindToLifecycle(lifecycleOwner, selector, preview)
        camera = bound
        observe(bound)
        orientation.enable()
        applyFlash()
    }

    /** Leaving REACT recorded live: the recorder and its texture go. */
    private fun releaseLive() {
        live?.release()
        live = null
        liveEntry?.release()
        liveEntry = null
    }

    /**
     * The torch only takes while the camera is open — CameraX drops a request
     * made before — and the camera closes whenever the app leaves the screen,
     * so the flash is applied again each time it opens. A camera taken away
     * (another app, a policy) is said to Dart, and so is its return.
     */
    private fun observe(bound: Camera) {
        observedCamera?.cameraInfo?.cameraState?.removeObservers(lifecycleOwner)
        observedCamera = bound
        bound.cameraInfo.cameraState.observe(lifecycleOwner) { state ->
            if (camera !== bound) return@observe
            val error = state.error
            when {
                state.type == CameraState.Type.OPEN -> {
                    applyFlash()
                    events?.success(mapOf("type" to "camera", "open" to true))
                }
                error != null && state.type != CameraState.Type.OPENING -> {
                    Log.w(TAG, "camera state ${state.type} error ${error.code}")
                    events?.success(
                        mapOf("type" to "camera", "open" to false, "message" to cameraErrorMessage(error.code)),
                    )
                }
            }
        }
    }

    private fun cameraErrorMessage(code: Int): String = when (code) {
        CameraState.ERROR_CAMERA_IN_USE, CameraState.ERROR_MAX_CAMERAS_IN_USE ->
            "The camera is in use by another app."
        CameraState.ERROR_CAMERA_DISABLED -> "The camera is turned off on this phone."
        CameraState.ERROR_DO_NOT_DISTURB_MODE_ENABLED -> "Turn off Do Not Disturb to use the camera."
        CameraState.ERROR_CAMERA_REMOVED -> "The camera is no longer available."
        else -> "The camera stopped working."
    }

    /** Turns photos and new recordings to the way the phone is held. */
    private val orientation = object : OrientationEventListener(context) {
        override fun onOrientationChanged(degrees: Int) {
            if (degrees == ORIENTATION_UNKNOWN) return
            val rotation = when (degrees) {
                in 45..134 -> Surface.ROTATION_270
                in 135..224 -> Surface.ROTATION_180
                in 225..314 -> Surface.ROTATION_90
                else -> Surface.ROTATION_0
            }
            imageCapture?.targetRotation = rotation
            // A recording keeps the turn it started with.
            if (recording == null) videoCapture?.targetRotation = rotation
        }
    }

    /** The asked-for lens, or the other one where this phone has only that. */
    private fun selectorFor(provider: ProcessCameraProvider): CameraSelector {
        val front = CameraSelector.DEFAULT_FRONT_CAMERA
        val back = CameraSelector.DEFAULT_BACK_CAMERA
        val wanted = if (lens == LENS_FRONT) front else back
        val other = if (lens == LENS_FRONT) back else front
        return when {
            provider.hasCamera(wanted) -> wanted
            provider.hasCamera(other) -> {
                lens = if (lens == LENS_FRONT) LENS_BACK else LENS_FRONT
                other
            }
            else -> throw IllegalStateException("This phone has no camera.")
        }
    }

    private fun describe(): Map<String, Any?> {
        val info = camera?.cameraInfo
        val zoom = info?.zoomState?.value
        val providerNow = provider
        return mapOf(
            "textureId" to if (mode == MODE_REACT_LIVE) liveEntry?.id() else texture?.id(),
            "lens" to lens,
            "mode" to mode,
            "hasFlash" to (info?.hasFlashUnit() ?: false),
            "minZoom" to (zoom?.minZoomRatio ?: 1f).toDouble(),
            "maxZoom" to (zoom?.maxZoomRatio ?: 1f).toDouble(),
            "canFlip" to (
                providerNow != null &&
                    providerNow.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) &&
                    providerNow.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
                ),
            "galleryNeedsPermission" to GalleryShots.needsPermission,
        ) + previewInfo()
    }

    private fun previewInfo(): Map<String, Any?> = mapOf(
        "previewWidth" to previewSize?.width,
        "previewHeight" to previewSize?.height,
        "rotation" to rotationDegrees,
        "mirrored" to mirrored,
        "cameraTransform" to cameraTransform,
        "displayRotation" to displayRotationDegrees(),
    )

    private fun emitPreview() {
        events?.success(mapOf("type" to "preview") + previewInfo())
    }

    private fun applyFlash() {
        val cam = camera ?: return
        if (mode == MODE_VIDEO || mode == MODE_REACT_LIVE) {
            if (cam.cameraInfo.hasFlashUnit()) {
                cam.cameraControl.enableTorch(flash == FLASH_ON)
            }
            return
        }
        val hasFlash = cam.cameraInfo.hasFlashUnit()
        if (hasFlash) cam.cameraControl.enableTorch(false)
        imageCapture?.flashMode = when {
            !hasFlash -> ImageCapture.FLASH_MODE_OFF
            flash == FLASH_ON -> ImageCapture.FLASH_MODE_ON
            flash == FLASH_AUTO -> ImageCapture.FLASH_MODE_AUTO
            else -> ImageCapture.FLASH_MODE_OFF
        }
    }

    private fun focus(x: Float, y: Float) {
        val cam = camera ?: return
        val display = display() ?: return
        val point = DisplayOrientedMeteringPointFactory(display, cam.cameraInfo, 1f, 1f)
            .createPoint(x.coerceIn(0f, 1f), y.coerceIn(0f, 1f))
        val action = FocusMeteringAction.Builder(point)
            .setAutoCancelDuration(3, TimeUnit.SECONDS)
            .build()
        cam.cameraControl.startFocusAndMetering(action)
    }

    private fun takePhoto(path: String?, gallery: Boolean, result: MethodChannel.Result) {
        val capture = imageCapture
        if (path.isNullOrEmpty() || capture == null) {
            result.error("camera_unavailable", "The camera is not ready for a photo.", null)
            return
        }
        val file = File(path).also { it.parentFile?.mkdirs() }
        // A selfie is kept as it was seen on the screen.
        val metadata = ImageCapture.Metadata().apply { isReversedHorizontal = lens == LENS_FRONT }
        val options = ImageCapture.OutputFileOptions.Builder(file).setMetadata(metadata).build()
        capture.takePicture(options, mainExecutor, object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                // Answered once the file is upright in its pixels, so the
                // review and the editor read the same picture.
                // Then into the gallery; a gallery that will not take it
                // leaves the photo in the camera's folder, never lost.
                photoWorker.execute {
                    PhotoBaker.bakeIfFlipped(file)
                    val saved = if (gallery) GalleryShots.publishPhoto(context, file) else null
                    val answer = if (saved != null) {
                        mapOf("path" to saved.first, "uri" to saved.second.toString())
                    } else {
                        mapOf("path" to file.absolutePath)
                    }
                    mainExecutor.execute { result.success(answer) }
                }
            }

            override fun onError(error: ImageCaptureException) {
                Log.e(TAG, "photo failed", error)
                file.delete()
                result.error("photo_failed", "The photo could not be taken.", null)
            }
        })
    }

    /**
     * A finished video into the gallery's album, copied off the main thread —
     * a reaction is tens of megabytes. Answers its path and address there, or
     * nothing when the gallery would not take it (the file then stays).
     */
    private fun publishVideo(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrEmpty()) {
            result.success(null)
            return
        }
        photoWorker.execute {
            val saved = GalleryShots.publishVideo(context, File(path))
            val answer = saved?.let { mapOf("path" to it.first, "uri" to it.second.toString()) }
            mainExecutor.execute { result.success(answer) }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startRecording(path: String?, audio: Boolean, gallery: Boolean, result: MethodChannel.Result) {
        val recorder = live
        if (mode == MODE_REACT_LIVE && recorder != null) {
            if (path.isNullOrEmpty()) {
                result.error("camera_unavailable", "The camera is not ready to record.", null)
                return
            }
            val micGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
            recorder.start(path, gallery, audio && micGranted, liveShortSide, pendingTake) { error ->
                if (error == null) result.success(null) else result.error("camera_unavailable", error, null)
            }
            return
        }
        val capture = videoCapture
        if (path.isNullOrEmpty() || capture == null) {
            result.error("camera_unavailable", "The camera is not ready to record.", null)
            return
        }
        if (recording != null) {
            result.error("already_recording", "A recording is already running.", null)
            return
        }
        val file = File(path).also { it.parentFile?.mkdirs() }
        // Straight into the gallery: no copy of a long video afterwards.
        var pending: PendingRecording = if (gallery) {
            val options = MediaStoreOutputOptions.Builder(
                context.contentResolver,
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            ).setContentValues(GalleryShots.values(GalleryShots.galleryName(file), "video/mp4")).build()
            capture.output.prepareRecording(context, options)
        } else {
            capture.output.prepareRecording(context, FileOutputOptions.Builder(file).build())
        }
        // Asked for by the Dart side before recording; without it the video is
        // silent rather than refused.
        val micGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (audio && micGranted) pending = pending.withAudioEnabled()

        recordingPath = file.absolutePath
        recordingToGallery = gallery
        recordingPaused = false
        recordedMs = 0L
        recording = pending.start(mainExecutor) { event ->
            when (event) {
                is VideoRecordEvent.Status -> {
                    recordedMs = TimeUnit.NANOSECONDS.toMillis(event.recordingStats.recordedDurationNanos)
                    events?.success(
                        mapOf("type" to "recording", "durationMs" to recordedMs, "paused" to recordingPaused),
                    )
                }
                is VideoRecordEvent.Pause -> {
                    recordingPaused = true
                    events?.success(mapOf("type" to "recording", "durationMs" to recordedMs, "paused" to true))
                }
                is VideoRecordEvent.Resume -> {
                    recordingPaused = false
                    events?.success(mapOf("type" to "recording", "durationMs" to recordedMs, "paused" to false))
                }
                is VideoRecordEvent.Finalize -> onFinalized(event)
                else -> Unit
            }
        }
        result.success(null)
    }

    private fun onFinalized(event: VideoRecordEvent.Finalize) {
        val toGallery = recordingToGallery
        val uri = event.outputResults.outputUri.takeIf { toGallery && it != Uri.EMPTY }
        val path = if (toGallery) uri?.let { GalleryShots.pathOf(context, it) } else recordingPath
        val durationMs = TimeUnit.NANOSECONDS.toMillis(event.recordingStats.recordedDurationNanos)
        recording = null
        recordingPath = null
        recordingToGallery = false
        // A file is usable even when the recording ended with an error such as
        // the camera going away mid-take — CameraX finalizes what it has.
        val usable = path != null && File(path).let { it.exists() && it.length() > 0 } &&
            (!event.hasError() || event.error != VideoRecordEvent.Finalize.ERROR_NO_VALID_DATA)
        if (event.hasError()) {
            Log.w(TAG, "recording finalized with error ${event.error}", event.cause)
        }
        val waiting = pendingStop
        pendingStop = null
        val answer = when {
            !usable -> emptyMap()
            uri != null -> mapOf("path" to path, "uri" to uri.toString(), "durationMs" to durationMs)
            else -> mapOf("path" to path, "durationMs" to durationMs)
        }
        if (usable && uri != null && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            GalleryShots.scan(context, path!!, "video/mp4")
        }
        if (!usable) {
            if (uri != null) GalleryShots.delete(context, uri) else path?.let { File(it).delete() }
        }
        if (waiting != null) {
            waiting.success(answer)
        } else {
            // Ended without a stop: the app left the screen mid-take.
            events?.success(mapOf("type" to "recordingEnded") + answer)
        }
    }

    private fun stopRecording(result: MethodChannel.Result) {
        val recorder = live
        if (mode == MODE_REACT_LIVE && recorder != null) {
            recorder.stop { answer -> result.success(answer) }
            return
        }
        val current = recording
        if (current == null) {
            result.success(emptyMap<String, Any>())
            return
        }
        pendingStop = result
        current.stop()
    }

    private fun close() {
        pendingStop?.success(emptyMap<String, Any>())
        pendingStop = null
        provider?.unbindAll()
        releaseLive()
        recording?.close()
        recording = null
        recordingPath?.let { File(it).delete() }
        recordingPath = null
        orientation.disable()
        camera?.let { if (it.cameraInfo.hasFlashUnit()) it.cameraControl.enableTorch(false) }
        observedCamera?.cameraInfo?.cameraState?.removeObservers(lifecycleOwner)
        observedCamera = null
        provider?.unbindAll()
        camera = null
        imageCapture = null
        videoCapture = null
        previewSurface?.release()
        previewSurface = null
        texture?.release()
        texture = null
        previewSize = null
    }

    fun release() {
        close()
        lifecycleOwner.lifecycle.removeObserver(lifecycleWatcher)
        photoWorker.shutdown()
    }

    private fun display(): Display? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.display
        } else {
            @Suppress("DEPRECATION")
            (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay
        }
    }

    private fun displayRotation(): Int = display()?.rotation ?: Surface.ROTATION_0

    private fun displayRotationDegrees(): Int = when (displayRotation()) {
        Surface.ROTATION_90 -> 90
        Surface.ROTATION_180 -> 180
        Surface.ROTATION_270 -> 270
        else -> 0
    }

    companion object {
        const val channelName = "slimshot_ai/camera"
        const val eventChannelName = "slimshot_ai/camera_events"
        private const val TAG = "SlimshotCamera"
        private const val CAMERA_UNAVAILABLE = "The camera could not be opened."

        const val LENS_FRONT = "front"
        const val LENS_BACK = "back"
        const val MODE_PHOTO = "photo"
        const val MODE_VIDEO = "video"
        const val MODE_REACT_LIVE = "react_live"
        private const val REACT_SOURCE_FAILED = "This can't be opened."
        const val FLASH_OFF = "off"
        const val FLASH_AUTO = "auto"
        const val FLASH_ON = "on"
    }
}
