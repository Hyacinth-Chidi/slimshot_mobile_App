package com.techfamz.slimshotai.nativepreview.gl

import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.EGLSurface
import android.opengl.GLUtils
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Surface
import com.techfamz.slimshotai.nativepreview.LaneFit
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Which decoder lane is being drawn, and how. */
internal data class TransitionDraw(
    val type: String,
    val progress: Float,
    val outgoingLane: Int,
    val incomingLane: Int,
)

/**
 * Draws the preview from **two live decoder lanes**.
 *
 * Each lane owns an external OES texture that a Media3 player decodes into
 * directly. Outside a transition the active lane is drawn straight through.
 * During a transition both lanes are sampled by a shader and blended by
 * `progress`.
 *
 * Nothing here captures, freezes, or copies a frame. There is no FBO, no
 * bitmap, no pixel readback, and the players are never paused for the
 * renderer's benefit — the transition is a pure GPU composition of two
 * advancing video streams.
 *
 * Threading: public methods are safe from any thread and post onto the GL
 * thread. `@Volatile` fields are written from the main thread and read on the
 * GL thread.
 */
internal class TransitionRenderer(
    private val onLaneSurfaceReady: (Int, Surface) -> Unit,
    private val onError: (String) -> Unit,
    /**
     * Something rendered, but not the way the project asks for.
     *
     * Deliberately separate from [onError]: an effect the device refused is not
     * a playback failure — the picture is still there, just unprocessed — and
     * reporting it as an error would put a failure toast over a working preview.
     * Without this the chain's warnings reached logcat only, which breaks the
     * degrade-loudly rule: a device that would not allocate the effect buffers
     * rendered the plain picture with nothing telling the user why.
     */
    private val onWarning: (String) -> Unit = {},
) {

    /** One decoder's output: an external texture plus its surface plumbing. */
    private class Lane(val index: Int) {
        var textureId = 0
        var surfaceTexture: SurfaceTexture? = null
        var surface: Surface? = null
        val texMatrix = FloatArray(16)

        /**
         * Fraction of the canvas this lane's clip occupies once fitted inside
         * it. (1,1) fills the frame; anything smaller leaves background bars.
         */
        @Volatile
        var fitX = 1f

        @Volatile
        var fitY = 1f

        /** Where the clip's centre sits, as an offset from the canvas centre. */
        @Volatile
        var panX = 0f

        @Volatile
        var panY = 0f

        /** The clip's rotation about its own centre, in radians. */
        @Volatile
        var rotation = 0f

        /**
         * Set once the decoder has delivered at least one frame. Sampling a
         * lane before this would read undefined texture memory, so a
         * transition falls back to the outgoing lane alone until it flips.
         */
        @Volatile
        var hasFrame = false

        private val frameLock = ReentrantLock()
        private val frameArrived = frameLock.newCondition()

        /**
         * Count of frames the producer has queued into [surfaceTexture].
         *
         * Playback only needs to know *that* a frame exists, which [hasFrame]
         * answers. Export drives the clock itself and needs to know that the
         * frame it just asked for has actually landed:
         * `MediaCodec.releaseOutputBuffer(index, true)` only **queues** a frame,
         * and it arrives on the producer's own thread some time later. A
         * sequence rather than a flag, so a waiter cannot mistake a frame that
         * was already there for the one it is waiting on.
         */
        private var frameSequence = 0L

        fun onFrameQueued() {
            frameLock.withLock {
                frameSequence++
                frameArrived.signalAll()
            }
            hasFrame = true
        }

        fun frameSequence(): Long = frameLock.withLock { frameSequence }

        /** Waits for a frame queued after [since]. False if it never came. */
        fun awaitFrameAfter(since: Long, timeoutMs: Long): Boolean = frameLock.withLock {
            var remainingNanos = TimeUnit.MILLISECONDS.toNanos(timeoutMs)
            while (frameSequence <= since) {
                if (remainingNanos <= 0L) return false
                remainingNanos = try {
                    frameArrived.awaitNanos(remainingNanos)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return false
                }
            }
            return true
        }

        /** Wakes any waiter, so a torn-down lane cannot hold an export up. */
        private fun cancelFrameWaits() {
            frameLock.withLock { frameArrived.signalAll() }
        }

        /**
         * A still photo uploaded from a `Bitmap`, or 0 when this lane is
         * showing decoder output.
         *
         * ExoPlayer does not render images to the video surface — its
         * `ImageRenderer` hands out `Bitmap`s through an `ImageOutput` — so a
         * photo clip arrives here instead of through [surfaceTexture] and is
         * sampled as an ordinary 2D texture.
         */
        var imageTextureId = 0

        /**
         * Pixel size of the uploaded photo, recorded at upload on the GL
         * thread.
         *
         * An image lane's contain fit is derived from these **at draw time**
         * rather than pushed by the engine's tick, so the bitmap and its fit
         * are one atomic thing. Pushed separately, the fit trailed the
         * delivery by up to a tick, and every differently-shaped photo was
         * composited inside the previous photo's box for a frame or two at
         * each cut — visible as the new photo flashing and snapping to size.
         */
        var imageWidth = 0
        var imageHeight = 0

        /**
         * The clip's pinch scale on top of the photo's contain fit. Pan
         * reuses [panX]/[panY]. Engine-supplied, like a video lane's fit.
         */
        @Volatile
        var imageScale = 1f

        /** This clip's own grade, already column-major. Null when ungraded. */
        var colorMatrix: FloatArray? = null
        var colorOffset = floatArrayOf(0f, 0f, 0f, 0f)

        /** Set from the player thread; uploaded on the GL thread at next draw. */
        @Volatile
        var pendingImage: Bitmap? = null

        @Volatile
        var showingImage = false

        /** Bitmaps are top-left origin; the quad's texcoords run y-up. */
        val imageMatrix = floatArrayOf(
            1f, 0f, 0f, 0f,
            0f, -1f, 0f, 0f,
            0f, 0f, 1f, 0f,
            0f, 1f, 0f, 1f,
        )

        /** True once this lane has something to draw, photo or decoded frame. */
        val hasContent: Boolean
            get() = if (showingImage) imageTextureId != 0 else hasFrame

        fun releaseImage() {
            GlUtil.deleteTexture(imageTextureId)
            imageTextureId = 0
            imageWidth = 0
            imageHeight = 0
            imageScale = 1f
            pendingImage = null
            showingImage = false
        }

        fun release() {
            surface?.release()
            surface = null
            surfaceTexture?.setOnFrameAvailableListener(null)
            surfaceTexture?.release()
            surfaceTexture = null
            GlUtil.deleteTexture(textureId)
            textureId = 0
            hasFrame = false
            cancelFrameWaits()
            releaseImage()
        }
    }

    private val thread = HandlerThread("slimshot-gl").apply { start() }
    private val handler = Handler(thread.looper)

    /**
     * Where `onFrameAvailable` is delivered.
     *
     * Deliberately **not** the GL thread. A `SurfaceTexture` dispatches its
     * callback on the looper of the thread that registered the listener, and
     * export runs its whole loop as one runnable on the GL thread — so a
     * listener registered there cannot be delivered for the entire length of an
     * export. The lane's frame counter would never move, and a lane that was not
     * already marked as having a frame would never have its texture updated:
     * the picture freezes on whatever happened to be in the texture when export
     * began, while audio, duration and progress all stay correct.
     */
    private val frameThread = HandlerThread("slimshot-gl-frames").apply { start() }
    private val frameHandler = Handler(frameThread.looper)

    private val egl = EglCore()
    private var offscreenSurface: EGLSurface? = null
    private var windowSurface: EGLSurface? = null

    private val lanes = arrayOf(Lane(0), Lane(1))

    private var surfaceWidth = 0
    private var surfaceHeight = 0

    /**
     * Aspect of the viewport being composited, set at the top of [composite].
     * GL thread only. Image-lane fits are derived against this, so preview
     * (canvas-sized texture) and export (encoder-sized surface) letterbox a
     * photo identically for free.
     */
    private var viewportAspect = 0f

    private val programs = mutableMapOf<String, TransitionProgram>()

    private val quadVertices: FloatBuffer = floatBuffer(
        floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f),
    )
    private val quadTexCoords: FloatBuffer = floatBuffer(
        floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f),
    )

    @Volatile
    private var activeLane = 0

    @Volatile
    private var transition: TransitionDraw? = null

    /** Crop, zoom and pan resolved into one source rect: x, y, width, height. */
    @Volatile
    private var contentRect = floatArrayOf(0f, 0f, 1f, 1f)

    /** Column-major 4×4 colour matrix, or null when no filter is applied. */
    @Volatile
    private var colorMatrix: FloatArray? = null

    @Volatile
    private var colorOffset = floatArrayOf(0f, 0f, 0f, 0f)

    /** Letterbox and empty-canvas colour, linear 0..1 RGB. */
    @Volatile
    private var backgroundColor = floatArrayOf(0f, 0f, 0f)

    @Volatile
    private var released = false

    private val renderRunnable = Runnable { renderFrame() }

    /**
     * The encoder's input surface while an export is running, else null.
     *
     * Non-null suppresses ordinary preview drawing: export renders frames one
     * at a time, on its own clock, and a preview draw landing in the middle
     * would take the GL context and the output target out from under it.
     */
    private var exportSurface: EGLSurface? = null
    private var exportWidth = 0
    private var exportHeight = 0

    /**
     * Photo and video overlays, painted over the composite during export.
     *
     * Export-only for now: in the preview the same overlays are live Flutter
     * widgets stacked above this texture, so drawing them here as well would
     * show every overlay twice. Owned by this class so its GL resources live
     * and die with the context.
     */
    val overlays: OverlayRenderer by lazy { OverlayRenderer(frameHandler) }

    /**
     * Full-frame effect passes run over the composite, in order. Empty is the
     * default and the case every project takes today.
     *
     * `@Volatile` because it is written from the main thread and read on the GL
     * thread, like the rest of the per-frame state above. The list itself is
     * replaced wholesale, never mutated, so the GL thread always reads a
     * complete one.
     */
    @Volatile
    private var effectPasses: List<EffectPass> = emptyList()

    /**
     * Where the lanes are drawn when [effectPasses] is non-empty, so the passes
     * have something to sample. Null until the first effected frame: a project
     * without effects must never pay for the allocation.
     */
    private var sceneTarget: RenderTarget? = null

    /**
     * Ping-pong buffers for the passes themselves.
     *
     * Warnings go to logcat **and** to [onWarning], which the manager turns into
     * a channel event. The chain already de-duplicates by cause, so this cannot
     * become a toast at 60Hz; what it does mean is that a device refusing the
     * effect buffers says so instead of quietly rendering the plain picture.
     */
    private val effectChain = EffectPassChain { message ->
        Log.w(TAG, message)
        onWarning(message)
    }

    // ------------------------------------------------------------------ export

    /**
     * Runs [block] on the GL thread and waits for it.
     *
     * The export loop has to run here: the EGL context belongs to this thread,
     * and export composites through exactly the same code the preview does.
     */
    fun <T> callOnGlThread(block: () -> T): T {
        // Already on the GL thread: run it here. Posting would queue the block
        // behind the very call that is waiting for it, and the thread would
        // block on itself forever.
        //
        // Export is exactly that shape and hit it: `runVideo` runs *inside* a
        // `callOnGlThread`, and per output frame it resolves the clip's effect,
        // which hops to the GL thread to link or release shader programs. The
        // export froze at the first frame whose clip carried an effect — around
        // 15% of a short clip — with no error, because a deadlock is not a
        // failure anything can report.
        if (Looper.myLooper() === thread.looper) {
            return block()
        }

        val result = java.util.concurrent.SynchronousQueue<Result<T>>()
        handler.post {
            result.put(runCatching(block))
        }
        return result.take().getOrThrow()
    }

    /** The surface a decoder for [index] should render into. */
    fun laneSurface(index: Int): Surface? = lanes.getOrNull(index)?.surface

    /** How many frames lane [index] has been handed so far. */
    fun laneFrameSequence(index: Int): Long = lanes.getOrNull(index)?.frameSequence() ?: 0L

    /**
     * Blocks until lane [index] is handed a frame newer than [since].
     *
     * The export loop renders one frame at a time and has to know its decoder's
     * output has actually reached the lane before compositing — otherwise it
     * draws the previous frame, or, on a lane that has never had one, nothing.
     * False on timeout, which the caller reports rather than waiting forever.
     */
    fun awaitLaneFrame(index: Int, since: Long, timeoutMs: Long): Boolean {
        return lanes.getOrNull(index)?.awaitFrameAfter(since, timeoutMs) ?: false
    }

    /** Whether lane [index] holds a decoded frame. For export diagnostics. */
    fun laneHasFrame(index: Int): Boolean = lanes.getOrNull(index)?.hasFrame ?: false

    /**
     * Points rendering at an encoder's input surface.
     *
     * Must be called on the GL thread. The preview's own window surface is left
     * alone and resumes when [endExport] restores it.
     */
    fun beginExport(encoderSurface: Surface, width: Int, height: Int) {
        check(egl.isReady) { "GL context is not ready." }
        endExport()
        exportSurface = egl.createWindowSurface(encoderSurface)
        exportWidth = width
        exportHeight = height
        egl.makeCurrent(exportSurface!!)
    }

    /**
     * Tears down and rebuilds one lane's `Surface`/`SurfaceTexture` around the
     * same GL texture. **Must be called on the GL thread** — export's loop
     * owns it, which is the one caller.
     *
     * The cure for a decoder that will not configure on the lane's surface:
     * `MediaCodec.release()` disconnects its surface asynchronously, and on
     * some devices the old connection never clears in time, so every
     * subsequent `configure` on that surface fails — one clip in the middle
     * of an export simply never decoded. ExoPlayer ships a device workaround
     * for the same class of failure. A fresh `SurfaceTexture` on the same
     * texture id carries no stale connection.
     */
    fun recreateLaneSurfaceForExport(laneIndex: Int): Surface? {
        val lane = lanes.getOrNull(laneIndex) ?: return null
        if (lane.textureId == 0) return null

        lane.surfaceTexture?.setOnFrameAvailableListener(null)
        lane.surface?.release()
        lane.surfaceTexture?.release()
        lane.hasFrame = false

        val surfaceTexture = SurfaceTexture(lane.textureId)
        surfaceTexture.setOnFrameAvailableListener(
            {
                lane.onFrameQueued()
                requestRender()
            },
            frameHandler,
        )
        lane.surfaceTexture = surfaceTexture
        val surface = Surface(surfaceTexture)
        lane.surface = surface
        // The engine records it for the post-export reattach; during export
        // its players are detached, so nothing connects to it but export.
        onLaneSurfaceReady(laneIndex, surface)
        Log.w(TAG, "lane[$laneIndex] surface recreated for export")
        return surface
    }

    /**
     * Composites one frame and hands it to the encoder.
     *
     * [presentationTimeNs] is where this frame sits in the *output*, not when
     * it happened to be rendered — export runs faster than realtime, so without
     * it the file's timing would be meaningless.
     */
    fun drawExportFrame(
        presentationTimeNs: Long,
        overlayDraws: List<OverlayRenderer.Draw> = emptyList(),
    ) {
        val surface = exportSurface ?: return
        egl.makeCurrent(surface)
        updateLaneTextures()
        composite(exportWidth, exportHeight)
        // Over the finished frame and outside the project grade, exactly where
        // the preview's Flutter overlay widgets sit.
        overlays.draw(overlayDraws, exportWidth, exportHeight)
        egl.setPresentationTime(surface, presentationTimeNs)
        egl.swapBuffers(surface)
    }

    /** Releases the encoder surface and gives the preview its target back. */
    fun endExport() {
        val surface = exportSurface ?: return
        exportSurface = null
        exportWidth = 0
        exportHeight = 0
        // Overlay textures and decode targets are export-scoped; the next
        // export re-uploads what it needs.
        overlays.releaseAll()
        // The effect buffers are export-*sized* — up to three full frames at the
        // encode resolution, which is larger than the preview canvas. They would
        // be reallocated at the preview's size on the next effected frame
        // anyway, so dropping them here just avoids holding that memory over an
        // editing session that may never ask for an effect again.
        releaseEffectTargets()
        egl.releaseSurface(surface)
        makeRenderTargetCurrent()
        requestRender()
    }

    // ---------------------------------------------------------------- lifecycle

    fun start() {
        handler.post {
            try {
                egl.setup()
                offscreenSurface = egl.createOffscreenSurface()
                egl.makeCurrent(offscreenSurface!!)

                for (lane in lanes) {
                    Matrix.setIdentityM(lane.texMatrix, 0)
                    lane.textureId = GlUtil.createExternalTexture()

                    val surfaceTexture = SurfaceTexture(lane.textureId)
                    surfaceTexture.setOnFrameAvailableListener(
                        {
                            lane.onFrameQueued()
                            requestRender()
                        },
                        // On its own looper: see [frameThread]. Registering
                        // without a handler would bind the callback to whichever
                        // looper this runs on — the GL thread — which an export
                        // blocks for its whole run.
                        frameHandler,
                    )
                    lane.surfaceTexture = surfaceTexture

                    val surface = Surface(surfaceTexture)
                    lane.surface = surface
                    onLaneSurfaceReady(lane.index, surface)
                }

                // Shader links are slow enough to drop frames, so the
                // passthrough programs are built before anything asks to draw.
                programFor(PASSTHROUGH, incomingIsImage = false, outgoingIsImage = false)
                programFor(PASSTHROUGH, incomingIsImage = true, outgoingIsImage = true)
            } catch (error: Exception) {
                reportError("GL setup failed", error)
            }
        }
    }

    /**
     * Links every transition shader ahead of time.
     *
     * Called when a timeline arrives, so the first frame of a transition never
     * pays for a `glLinkProgram` in the render path.
     */
    fun warmUpShaders(types: Collection<String>, includeImageVariants: Boolean) {
        if (released || types.isEmpty()) return
        handler.post {
            if (released) return@post
            if (makeRenderTargetCurrent() == null) return@post
            for (type in types) {
                programFor(type, incomingIsImage = false, outgoingIsImage = false)
                if (!includeImageVariants) continue
                // A photo can sit on either side of a transition, so both mixed
                // pairings are possible as well as photo-to-photo.
                programFor(type, incomingIsImage = true, outgoingIsImage = false)
                programFor(type, incomingIsImage = false, outgoingIsImage = true)
                programFor(type, incomingIsImage = true, outgoingIsImage = true)
            }
        }
    }

    /**
     * Attaches the Flutter-owned output texture.
     *
     * The [SurfaceTexture] belongs to Flutter's `TextureRegistry`; this class
     * only builds an EGL window surface on top of it and must never release it.
     */
    fun attachOutputSurface(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        handler.post {
            if (released || !egl.isReady) return@post
            try {
                releaseWindowSurface()
                windowSurface = egl.createWindowSurface(surfaceTexture)
                surfaceWidth = width
                surfaceHeight = height
                egl.makeCurrent(windowSurface!!)
                renderFrame()
            } catch (error: Exception) {
                reportError("GL surface attach failed", error)
            }
        }
    }

    fun release() {
        released = true
        val latch = CountDownLatch(1)
        val posted = handler.post {
            programs.values.forEach { it.release() }
            programs.clear()
            releaseEffectTargets()
            releaseWindowSurface()
            lanes.forEach { it.release() }
            egl.releaseSurface(offscreenSurface)
            offscreenSurface = null
            egl.release()
            latch.countDown()
            thread.quitSafely()
        }
        // Wait briefly so GL teardown finishes before Flutter releases the
        // output texture underneath us. The timeout keeps a wedged render
        // thread from turning into an ANR.
        if (posted) latch.await(SURFACE_TEARDOWN_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        // Outside the runnable so it is still shut down if the GL thread was
        // already gone and nothing could be posted to it.
        frameThread.quitSafely()
    }

    // ------------------------------------------------------------------- state

    /** The lane drawn straight through when no transition is running. */
    fun setActiveLane(laneIndex: Int) {
        if (released || activeLane == laneIndex) return
        activeLane = laneIndex
        requestRender()
    }

    /**
     * Sets the full-frame effect passes, replacing whatever was there.
     *
     * An empty list — the default, and every project today — puts [composite]
     * back on its single-pass path: no scene target, no chain, the same draw
     * straight to the output.
     */
    fun setEffectPasses(passes: List<EffectPass>) {
        if (released) return
        // Copied because the caller may keep mutating its own list, and the GL
        // thread reads this one between frames.
        effectPasses = passes.toList()
        requestRender()
    }

    fun setTransition(draw: TransitionDraw) {
        if (released) return
        transition = draw
        requestRender()
    }

    fun clearTransition() {
        if (released || transition == null) return
        transition = null
        requestRender()
    }

    /**
     * Marks a lane as having no valid picture, after its player is stopped or
     * its media replaced.
     */
    fun invalidateLane(laneIndex: Int) {
        lanes.getOrNull(laneIndex)?.hasFrame = false
    }

    /**
     * Hands a lane a still photo to display.
     *
     * Image clips never reach the video surface, so their frames arrive here
     * from the player's `ImageOutput` instead. Uploading happens on the GL
     * thread at the next draw.
     */
    fun setLaneImage(laneIndex: Int, bitmap: Bitmap) {
        if (released) return
        val lane = lanes.getOrNull(laneIndex) ?: return
        lane.pendingImage = bitmap
        lane.showingImage = true
        requestRender()
    }

    /** Whether [laneIndex] is currently sampling an uploaded photo. */
    fun laneShowingImage(laneIndex: Int): Boolean {
        return lanes.getOrNull(laneIndex)?.showingImage == true
    }

    /**
     * The pinch scale and drag offset of the clip on an image lane.
     *
     * Only the clip's *transform* travels this way. The contain fit itself is
     * derived at draw time from the uploaded bitmap's own pixels
     * ([Lane.imageWidth]/[Lane.imageHeight]), so a newly delivered photo can
     * never be drawn inside the previous photo's box while a separately
     * pushed fit is still in flight — that lag flashed at every photo cut.
     * Video lanes keep the whole fit through [setLaneFit].
     */
    fun setLaneImageTransform(
        laneIndex: Int,
        scale: Float,
        panX: Float,
        panY: Float,
        rotationRadians: Float = 0f,
    ) {
        val lane = lanes.getOrNull(laneIndex) ?: return
        val next = scale.coerceIn(0.005f, 16f)
        if (lane.imageScale == next && lane.panX == panX && lane.panY == panY &&
            lane.rotation == rotationRadians
        ) {
            return
        }
        lane.imageScale = next
        lane.panX = panX
        lane.panY = panY
        lane.rotation = rotationRadians
        requestRender()
    }

    /** Returns a lane to decoder output after an image clip. */
    fun clearLaneImage(laneIndex: Int) {
        if (released) return
        val lane = lanes.getOrNull(laneIndex) ?: return
        if (!lane.showingImage && lane.pendingImage == null) return
        lane.showingImage = false
        lane.pendingImage = null
        requestRender()
    }

    /**
     * How the clip on this lane sits inside the project canvas.
     *
     * Clips in one project can differ in shape — a portrait video next to a
     * landscape photo — so each is fitted rather than stretched, and the space
     * around it stays background.
     */
    /**
     * The part of each source frame that reaches the canvas, with crop, zoom
     * and pan already resolved into one rect by the Dart side.
     */
    fun setContentRect(x: Float, y: Float, width: Float, height: Float) {
        if (released) return
        if (width <= 0f || height <= 0f) return
        val next = floatArrayOf(x, y, width, height)
        if (next.contentEquals(contentRect)) return
        contentRect = next
        requestRender()
    }

    /**
     * Sets the project colour filter.
     *
     * [matrix] is Flutter's 4×5 `ColorFilter.matrix` layout — 20 row-major
     * values with the offsets on a 0–255 scale. Null clears the filter.
     */
    fun setColorMatrix(matrix: FloatArray?) {
        if (released) return

        if (matrix == null || matrix.size < 20) {
            if (colorMatrix == null) return
            colorMatrix = null
            colorOffset = floatArrayOf(0f, 0f, 0f, 0f)
            requestRender()
            return
        }

        // GLSL ES 2.0 rejects transposed uniform uploads, so the row-major
        // matrix is converted to column-major here rather than at bind time.
        val columnMajor = floatArrayOf(
            matrix[0], matrix[5], matrix[10], matrix[15],
            matrix[1], matrix[6], matrix[11], matrix[16],
            matrix[2], matrix[7], matrix[12], matrix[17],
            matrix[3], matrix[8], matrix[13], matrix[18],
        )
        // Offsets are authored on a 0–255 scale; GL works in 0–1.
        val offset = floatArrayOf(
            matrix[4] / 255f,
            matrix[9] / 255f,
            matrix[14] / 255f,
            matrix[19] / 255f,
        )

        if (columnMajor.contentEquals(colorMatrix) && offset.contentEquals(colorOffset)) {
            return
        }
        colorMatrix = columnMajor
        colorOffset = offset
        requestRender()
    }

    /**
     * Sets the colour filter belonging to the clip currently on [laneIndex].
     *
     * Applied to that lane's pixels before a transition blends them, so two
     * clips with different filters cross-fade between their looks. Same layout
     * as [setColorMatrix]; null clears the lane's grade.
     */
    fun setLaneColorMatrix(laneIndex: Int, matrix: FloatArray?) {
        if (released) return
        val lane = lanes.getOrNull(laneIndex) ?: return

        if (matrix == null || matrix.size < 20) {
            if (lane.colorMatrix == null) return
            lane.colorMatrix = null
            lane.colorOffset = floatArrayOf(0f, 0f, 0f, 0f)
            requestRender()
            return
        }

        val columnMajor = floatArrayOf(
            matrix[0], matrix[5], matrix[10], matrix[15],
            matrix[1], matrix[6], matrix[11], matrix[16],
            matrix[2], matrix[7], matrix[12], matrix[17],
            matrix[3], matrix[8], matrix[13], matrix[18],
        )
        val offset = floatArrayOf(
            matrix[4] / 255f,
            matrix[9] / 255f,
            matrix[14] / 255f,
            matrix[19] / 255f,
        )

        if (columnMajor.contentEquals(lane.colorMatrix) &&
            offset.contentEquals(lane.colorOffset)
        ) {
            return
        }
        lane.colorMatrix = columnMajor
        lane.colorOffset = offset
        requestRender()
    }

    /**
     * How the clip on [laneIndex] sits on the canvas: its fitted size (which a
     * user's pinch scales beyond or below the plain contain-fit) and where its
     * centre is dragged to, in canvas fractions.
     *
     * The upper bound is generous rather than 1: a clip scaled up past the
     * canvas is a deliberate crop-to-fill, exactly what a pinch out is for.
     */
    fun setLaneFit(
        laneIndex: Int,
        fitX: Float,
        fitY: Float,
        panX: Float = 0f,
        panY: Float = 0f,
        rotationRadians: Float = 0f,
    ) {
        val lane = lanes.getOrNull(laneIndex) ?: return
        val nextX = fitX.coerceIn(0.005f, 16f)
        val nextY = fitY.coerceIn(0.005f, 16f)
        if (lane.fitX == nextX && lane.fitY == nextY &&
            lane.panX == panX && lane.panY == panY &&
            lane.rotation == rotationRadians
        ) {
            return
        }
        lane.fitX = nextX
        lane.fitY = nextY
        lane.panX = panX
        lane.panY = panY
        lane.rotation = rotationRadians
        requestRender()
    }

    /**
     * Colour of the letterbox bars and empty canvas, from the background tool.
     *
     * `blur` is not implemented natively yet and falls back to black — the
     * caller decides that mapping, this just takes a colour.
     */
    fun setBackgroundColor(argb: Int) {
        val next = floatArrayOf(
            ((argb shr 16) and 0xFF) / 255f,
            ((argb shr 8) and 0xFF) / 255f,
            (argb and 0xFF) / 255f,
        )
        if (next.contentEquals(backgroundColor)) return
        backgroundColor = next
        requestRender()
    }

    // ----------------------------------------------------------------- drawing

    /**
     * Coalescing render request. Safe from any thread: frame-available
     * callbacks arrive on decoder threads while transition updates come from
     * the main thread, so scheduling is funnelled through the render handler
     * rather than guarded by a flag.
     */
    private fun requestRender() {
        if (released) return
        handler.removeCallbacks(renderRunnable)
        handler.post(renderRunnable)
    }

    private fun renderFrame() {
        if (released) return
        // While exporting, frames are drawn one at a time by the export engine
        // against the encoder's surface. A preview draw in the middle of that
        // would fight it for the GL context and the output target.
        if (exportSurface != null) return
        val surface = makeRenderTargetCurrent() ?: return

        updateLaneTextures()
        composite(surfaceWidth, surfaceHeight)

        egl.swapBuffers(surface)

        // Progress advances continuously, so keep drawing through the window
        // even on a frame where neither decoder handed us anything new.
        if (transition != null) {
            handler.removeCallbacks(renderRunnable)
            handler.postDelayed(renderRunnable, FRAME_INTERVAL_MS)
        }
    }

    /**
     * Pulls the newest frame for every attached lane.
     *
     * `updateTexImage` is a no-op when nothing new has arrived, so this never
     * blocks and never leaves a lane showing a stale frame while a newer one
     * waits.
     */
    private fun updateLaneTextures() {
        for (lane in lanes) {
            uploadPendingImage(lane)

            val surfaceTexture = lane.surfaceTexture ?: continue
            if (!lane.hasFrame) continue
            try {
                surfaceTexture.updateTexImage()
                surfaceTexture.getTransformMatrix(lane.texMatrix)
            } catch (error: Exception) {
                // Thrown if the surface was torn down between the callback and
                // this draw. Dropping the frame is the right response — but it
                // also strands the lane until a new frame is queued, which
                // during an export is long enough to freeze the picture, so it
                // is never swallowed silently.
                Log.w(TAG, "lane[${lane.index}] updateTexImage failed", error)
                lane.hasFrame = false
            }
        }
    }

    /**
     * Draws the finished frame into whatever surface is currently bound.
     *
     * **This is the one implementation of what a frame looks like.** Preview
     * draws it to Flutter's texture and export draws it to the encoder's input
     * surface; because both come through here, an exported frame is the
     * previewed frame rather than a second interpretation of the timeline.
     */
    private fun composite(viewportWidth: Int, viewportHeight: Int) {
        // **Set before anything branches.** The image-lane contain fit reads it
        // at draw time, so a path that skips the assignment letterboxes photos
        // against a stale viewport — the bug CLAUDE.md's batch items 4 and 10
        // are both about. The scene target is the output's size, so the value is
        // the same either way; what matters is that it is always written.
        viewportAspect =
            if (viewportHeight > 0) viewportWidth.toFloat() / viewportHeight else 0f

        val passes = effectPasses
        val scene = if (passes.isEmpty()) {
            null
        } else {
            // Null here means the device refused the buffers. The chain has
            // already warned; drawing straight to the output loses the effect
            // and keeps the picture, which is the right trade on the GL thread.
            prepareEffectTargets(viewportWidth, viewportHeight)
        }

        if (scene == null) {
            // The single-pass path, unchanged: framebuffer 0, one clear, one
            // draw. Every project without an effect is this one.
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
            GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
            drawScene()
            return
        }

        // Lanes into the scene texture, then the passes over it. `bind` sets the
        // viewport to the target's own size, which is the output's size here.
        scene.bind()
        drawScene()

        // Every pass `run` executes writes to one of its own targets — it has to
        // return a sampleable texture, so it cannot use the interface's null
        // target for the last one. The result therefore still has to be brought
        // to the output here, and this bind is what puts it there: every target
        // `bind` left both the framebuffer and the viewport pointing at an FBO.
        val result = effectChain.run(scene.textureId, passes, viewportWidth, viewportHeight)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
        // When the chain hands back the scene texture unchanged — an unavailable
        // chain, or a list it capped — this presents the unprocessed frame,
        // which is the missing effect degrading to the plain picture rather than
        // to black.
        presentTexture(result)
    }

    /**
     * Allocates the scene target and the chain's buffers for a
     * [width] x [height] frame, or null if the device refused either.
     *
     * **Reallocation is guarded on the size**, not done per frame: these are
     * three full-frame RGBA textures — around 24MB at 1080x1920 — and churning
     * them every frame is exactly what turns a working effect into a stutter on
     * the low-end target.
     */
    private fun prepareEffectTargets(width: Int, height: Int): RenderTarget? {
        if (width <= 0 || height <= 0) return null

        val existing = sceneTarget
        val scene = if (existing != null && existing.width == width && existing.height == height) {
            existing
        } else {
            existing?.release()
            sceneTarget = null
            val created = createRenderTarget(width, height) ?: return null
            sceneTarget = created
            created
        }

        // `resize` no-ops on an unchanged size, so this is cheap per frame; it
        // returns false when the device refused, which latches the chain off.
        if (!effectChain.resize(width, height)) return null
        return scene
    }

    /**
     * Drops the scene target and the chain's buffers. **GL thread only** —
     * every caller is already on it (teardown and [endExport]).
     */
    private fun releaseEffectTargets() {
        sceneTarget?.release()
        sceneTarget = null
        effectChain.release()
    }

    /**
     * Draws [textureId] over the bound framebuffer.
     *
     * Used only to present an effect chain's result. The passthrough program's
     * canvas uniforms are neutralised — no crop, no grade, a full fit — because
     * the scene texture already carries all of that: applying them a second time
     * would crop a cropped frame and grade a graded one.
     */
    private fun presentTexture(textureId: Int) {
        val program = programFor(PASSTHROUGH, incomingIsImage = true, outgoingIsImage = true)
            ?: return
        program.use()
        program.bindCanvas(FULL_FRAME_RECT, null, NO_COLOR_OFFSET, backgroundColor, viewportAspect)
        program.bindIncoming(
            textureId,
            GLES20.GL_TEXTURE_2D,
            IDENTITY_MATRIX,
            1f,
            1f,
            0f,
            0f,
        )
        program.bindIncomingGrade(null, NO_COLOR_OFFSET)
        drawQuad(program)
    }

    /**
     * Clears to the background and draws the lanes into the bound framebuffer.
     *
     * Split out of [composite] so the lane draw can land either on the output or
     * on a scene texture the effect passes read. **The body is unchanged from
     * when this was inline** — one clear, one program, one quad — which is what
     * keeps a project without effects rendering exactly as it did.
     */
    private fun drawScene() {
        GLES20.glClearColor(backgroundColor[0], backgroundColor[1], backgroundColor[2], 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        val draw = transition
        val outgoing = draw?.let { lanes.getOrNull(it.outgoingLane) }
        val incoming = draw?.let { lanes.getOrNull(it.incomingLane) }

        // Blend only once both lanes actually hold a picture. Until then show
        // the outgoing clip alone, which reads as the transition simply not
        // having started rather than as a black flash.
        val canBlend = draw != null &&
            outgoing != null && outgoing.hasContent &&
            incoming != null && incoming.hasContent

        if (canBlend) {
            val program = programFor(
                draw!!.type,
                incoming!!.showingImage,
                outgoing!!.showingImage,
            )
            if (program != null) {
                program.use()
                program.bindCanvas(contentRect, colorMatrix, colorOffset, backgroundColor, viewportAspect)
                bindLaneAsIncoming(program, incoming)
                bindLaneAsOutgoing(program, outgoing)
                program.setProgress(draw.progress)
                drawQuad(program)
            }
        } else {
            val lane = when {
                // Mid-transition but not ready to blend: hold the outgoing clip.
                outgoing != null && outgoing.hasContent -> outgoing
                incoming != null && incoming.hasContent -> incoming
                else -> lanes.getOrNull(activeLane)
            }
            if (lane != null && lane.hasContent) {
                val program = programFor(PASSTHROUGH, lane.showingImage, lane.showingImage)
                if (program != null) {
                    program.use()
                    program.bindCanvas(contentRect, colorMatrix, colorOffset, backgroundColor, viewportAspect)
                    bindLaneAsIncoming(program, lane)
                    drawQuad(program)
                }
            }
        }
    }

    /** Uploads a photo handed to this lane, replacing whatever it held. */
    private fun uploadPendingImage(lane: Lane) {
        val bitmap = lane.pendingImage ?: return
        lane.pendingImage = null
        if (bitmap.isRecycled) return

        if (lane.imageTextureId == 0) {
            lane.imageTextureId = GlUtil.createTexture2D(bitmap.width, bitmap.height)
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, lane.imageTextureId)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
        // Measured here, on the GL thread, in the same pass that will first
        // composite this bitmap — which is what makes the photo's fit atomic
        // with its picture.
        lane.imageWidth = bitmap.width
        lane.imageHeight = bitmap.height
        GlUtil.checkGlError("uploadPendingImage")
    }

    /**
     * Contain fit of the photo actually uploaded on [lane], times its clip's
     * pinch scale.
     *
     * Computed from the drawn pixels at draw time — see
     * [setLaneImageTransform] for why it must never be pushed separately. The
     * decoded bitmap is also the authority on shape: it has EXIF rotation and
     * downsampling already applied, where probed clip metadata may not.
     */
    private fun imageFit(lane: Lane): Pair<Float, Float> {
        if (lane.imageWidth <= 0 || lane.imageHeight <= 0 || viewportAspect <= 0f) {
            // Nothing measured yet — fall back to the engine-pushed fit.
            return Pair(lane.fitX, lane.fitY)
        }
        val aspect = lane.imageWidth.toDouble() / lane.imageHeight
        val (fitX, fitY) = LaneFit.of(aspect, viewportAspect.toDouble())
        return Pair(fitX * lane.imageScale, fitY * lane.imageScale)
    }

    private fun bindLaneAsIncoming(program: TransitionProgram, lane: Lane) {
        if (lane.showingImage) {
            val (fitX, fitY) = imageFit(lane)
            program.bindIncoming(
                lane.imageTextureId,
                GLES20.GL_TEXTURE_2D,
                lane.imageMatrix,
                fitX,
                fitY,
                lane.panX,
                lane.panY,
                lane.rotation,
            )
        } else {
            program.bindIncoming(
                lane.textureId,
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                lane.texMatrix,
                lane.fitX,
                lane.fitY,
                lane.panX,
                lane.panY,
                lane.rotation,
            )
        }
        program.bindIncomingGrade(lane.colorMatrix, lane.colorOffset)
    }

    private fun bindLaneAsOutgoing(program: TransitionProgram, lane: Lane) {
        if (lane.showingImage) {
            val (fitX, fitY) = imageFit(lane)
            program.bindOutgoing(
                lane.imageTextureId,
                GLES20.GL_TEXTURE_2D,
                lane.imageMatrix,
                fitX,
                fitY,
                lane.panX,
                lane.panY,
                lane.rotation,
            )
        } else {
            program.bindOutgoing(
                lane.textureId,
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                lane.texMatrix,
                lane.fitX,
                lane.fitY,
                lane.panX,
                lane.panY,
                lane.rotation,
            )
        }
        program.bindOutgoingGrade(lane.colorMatrix, lane.colorOffset)
    }

    private fun drawQuad(program: TransitionProgram) {
        program.bindGeometry(quadVertices, quadTexCoords)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        program.unbindGeometry()
    }

    private fun makeRenderTargetCurrent(): EGLSurface? {
        if (!egl.isReady) return null
        val target = windowSurface ?: offscreenSurface ?: return null
        return try {
            egl.makeCurrent(target)
            target
        } catch (error: Exception) {
            reportError("GL makeCurrent failed", error)
            null
        }
    }

    /**
     * A linked program for this transition and pair of source kinds.
     *
     * Keyed on the sampler types too: GLSL cannot switch a sampler at runtime,
     * so a photo-backed lane needs a separately compiled variant. Only the
     * combinations a timeline actually uses are ever built.
     */
    private fun programFor(
        type: String,
        incomingIsImage: Boolean,
        outgoingIsImage: Boolean,
    ): TransitionProgram? {
        val key = "$type|$incomingIsImage|$outgoingIsImage"
        programs[key]?.let { return it }
        return try {
            val fragment = if (type == PASSTHROUGH) {
                TransitionShaders.passthroughFragment(incomingIsImage)
            } else {
                TransitionShaders.fragmentShaderFor(type, incomingIsImage, outgoingIsImage)
            }
            val program = TransitionProgram(
                GlUtil.createProgram(TransitionShaders.VERTEX_SHADER, fragment),
            )
            programs[key] = program
            program
        } catch (error: Exception) {
            reportError("Transition shader '$type' failed to build", error)
            null
        }
    }

    private fun releaseWindowSurface() {
        val surface = windowSurface ?: return
        egl.makeNothingCurrent()
        egl.releaseSurface(surface)
        windowSurface = null
    }

    private fun reportError(message: String, error: Exception?) {
        val detail = error?.message ?: error?.javaClass?.simpleName
        val full = if (detail == null) message else "$message: $detail"
        Log.e(TAG, full, error)
        onError(full)
    }

    private fun floatBuffer(values: FloatArray): FloatBuffer {
        return ByteBuffer
            .allocateDirect(values.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply {
                put(values)
                position(0)
            }
    }

    companion object {
        private const val TAG = "TransitionRenderer"
        private const val PASSTHROUGH = "__passthrough"
        private const val FRAME_INTERVAL_MS = 16L
        private const val SURFACE_TEARDOWN_TIMEOUT_MS = 250L

        /**
         * Neutral canvas state for [presentTexture]: the whole source, no grade,
         * no texture transform. Shared and never written — the bind calls only
         * read them — so one copy each is enough.
         */
        private val FULL_FRAME_RECT = floatArrayOf(0f, 0f, 1f, 1f)
        private val NO_COLOR_OFFSET = floatArrayOf(0f, 0f, 0f, 0f)
        private val IDENTITY_MATRIX = FloatArray(16).also { Matrix.setIdentityM(it, 0) }
    }
}

/** A linked GL program plus its uniform and attribute locations. */
internal class TransitionProgram(private val handle: Int) {

    private val aPosition = GLES20.glGetAttribLocation(handle, "aPosition")
    private val aTexCoord = GLES20.glGetAttribLocation(handle, "aTexCoord")
    private val uIncoming = GLES20.glGetUniformLocation(handle, "uIncoming")
    private val uOutgoing = GLES20.glGetUniformLocation(handle, "uOutgoing")
    private val uTexMatrixIncoming =
        GLES20.glGetUniformLocation(handle, "uTexMatrixIncoming")
    private val uTexMatrixOutgoing =
        GLES20.glGetUniformLocation(handle, "uTexMatrixOutgoing")
    private val uFitIncoming = GLES20.glGetUniformLocation(handle, "uFitIncoming")
    private val uFitOutgoing = GLES20.glGetUniformLocation(handle, "uFitOutgoing")
    private val uPanIncoming = GLES20.glGetUniformLocation(handle, "uPanIncoming")
    private val uPanOutgoing = GLES20.glGetUniformLocation(handle, "uPanOutgoing")
    private val uRotationIncoming =
        GLES20.glGetUniformLocation(handle, "uRotationIncoming")
    private val uRotationOutgoing =
        GLES20.glGetUniformLocation(handle, "uRotationOutgoing")
    private val uCanvasAspect = GLES20.glGetUniformLocation(handle, "uCanvasAspect")
    private val uBackground = GLES20.glGetUniformLocation(handle, "uBackground")
    private val uContentRect = GLES20.glGetUniformLocation(handle, "uContentRect")
    private val uColorMatrix = GLES20.glGetUniformLocation(handle, "uColorMatrix")
    private val uColorOffset = GLES20.glGetUniformLocation(handle, "uColorOffset")
    private val uColorEnabled = GLES20.glGetUniformLocation(handle, "uColorEnabled")
    private val uProgress = GLES20.glGetUniformLocation(handle, "uProgress")
    private val uClipMatrixIncoming =
        GLES20.glGetUniformLocation(handle, "uClipMatrixIncoming")
    private val uClipOffsetIncoming =
        GLES20.glGetUniformLocation(handle, "uClipOffsetIncoming")
    private val uClipColorIncoming =
        GLES20.glGetUniformLocation(handle, "uClipColorIncoming")
    private val uClipMatrixOutgoing =
        GLES20.glGetUniformLocation(handle, "uClipMatrixOutgoing")
    private val uClipOffsetOutgoing =
        GLES20.glGetUniformLocation(handle, "uClipOffsetOutgoing")
    private val uClipColorOutgoing =
        GLES20.glGetUniformLocation(handle, "uClipColorOutgoing")

    fun use() = GLES20.glUseProgram(handle)

    /** The grade belonging to the clip on the incoming lane. */
    fun bindIncomingGrade(colorMatrix: FloatArray?, colorOffset: FloatArray) {
        bindGrade(
            colorMatrix,
            colorOffset,
            uClipColorIncoming,
            uClipMatrixIncoming,
            uClipOffsetIncoming,
        )
    }

    /** The grade belonging to the clip on the outgoing lane. */
    fun bindOutgoingGrade(colorMatrix: FloatArray?, colorOffset: FloatArray) {
        bindGrade(
            colorMatrix,
            colorOffset,
            uClipColorOutgoing,
            uClipMatrixOutgoing,
            uClipOffsetOutgoing,
        )
    }

    private fun bindGrade(
        colorMatrix: FloatArray?,
        colorOffset: FloatArray,
        enabledLocation: Int,
        matrixLocation: Int,
        offsetLocation: Int,
    ) {
        if (colorMatrix == null) {
            GLES20.glUniform1f(enabledLocation, 0f)
            return
        }
        GLES20.glUniform1f(enabledLocation, 1f)
        GLES20.glUniformMatrix4fv(matrixLocation, 1, false, colorMatrix, 0)
        GLES20.glUniform4f(
            offsetLocation,
            colorOffset[0],
            colorOffset[1],
            colorOffset[2],
            colorOffset[3],
        )
    }

    /** Project-wide state: what part of the frame is shown, and the grade. */
    fun bindCanvas(
        contentRect: FloatArray,
        colorMatrix: FloatArray?,
        colorOffset: FloatArray,
        background: FloatArray,
        canvasAspect: Float = 1f,
    ) {
        GLES20.glUniform4f(
            uContentRect,
            contentRect[0],
            contentRect[1],
            contentRect[2],
            contentRect[3],
        )
        GLES20.glUniform3f(uBackground, background[0], background[1], background[2])
        // The rotation helper needs the canvas shape to rotate without shearing.
        // Guarded against zero: a viewport that has not been sized yet would
        // otherwise divide every sampled coordinate by nothing.
        GLES20.glUniform1f(uCanvasAspect, if (canvasAspect > 0f) canvasAspect else 1f)

        if (colorMatrix == null) {
            GLES20.glUniform1f(uColorEnabled, 0f)
            return
        }
        GLES20.glUniform1f(uColorEnabled, 1f)
        GLES20.glUniformMatrix4fv(uColorMatrix, 1, false, colorMatrix, 0)
        GLES20.glUniform4f(
            uColorOffset,
            colorOffset[0],
            colorOffset[1],
            colorOffset[2],
            colorOffset[3],
        )
    }

    /** [target] is `GL_TEXTURE_EXTERNAL_OES` for video, `GL_TEXTURE_2D` for a photo. */
    fun bindIncoming(
        textureId: Int,
        target: Int,
        texMatrix: FloatArray,
        fitX: Float,
        fitY: Float,
        panX: Float,
        panY: Float,
        rotationRadians: Float = 0f,
    ) {
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(target, textureId)
        GLES20.glUniform1i(uIncoming, 0)
        GLES20.glUniformMatrix4fv(uTexMatrixIncoming, 1, false, texMatrix, 0)
        GLES20.glUniform2f(uFitIncoming, fitX, fitY)
        GLES20.glUniform2f(uPanIncoming, panX, panY)
        GLES20.glUniform1f(uRotationIncoming, rotationRadians)
    }

    fun bindOutgoing(
        textureId: Int,
        target: Int,
        texMatrix: FloatArray,
        fitX: Float,
        fitY: Float,
        panX: Float,
        panY: Float,
        rotationRadians: Float = 0f,
    ) {
        GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
        GLES20.glBindTexture(target, textureId)
        GLES20.glUniform1i(uOutgoing, 1)
        GLES20.glUniformMatrix4fv(uTexMatrixOutgoing, 1, false, texMatrix, 0)
        GLES20.glUniform2f(uFitOutgoing, fitX, fitY)
        GLES20.glUniform2f(uPanOutgoing, panX, panY)
        GLES20.glUniform1f(uRotationOutgoing, rotationRadians)
    }

    fun setProgress(progress: Float) {
        GLES20.glUniform1f(uProgress, progress)
    }

    fun bindGeometry(vertices: FloatBuffer, texCoords: FloatBuffer) {
        vertices.position(0)
        texCoords.position(0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 0, vertices)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, texCoords)
    }

    fun unbindGeometry() {
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
    }

    fun release() {
        GLES20.glDeleteProgram(handle)
    }
}
