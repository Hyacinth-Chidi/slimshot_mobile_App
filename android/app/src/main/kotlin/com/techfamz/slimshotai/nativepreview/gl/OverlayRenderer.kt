package com.techfamz.slimshotai.nativepreview.gl

import com.techfamz.slimshotai.nativepreview.NativeTimelineClip
import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import android.os.Handler
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import kotlin.math.cos
import kotlin.math.sin

/**
 * Draws photo and video overlays on top of the composited frame.
 *
 * Overlays are painted **after** [TransitionRenderer.composite] and are
 * deliberately outside the project colour grade: in the preview they are
 * Flutter widgets stacked over the graded texture, so grading them here would
 * make an exported sticker a different colour than the previewed one.
 *
 * Geometry arrives normalised to the canvas and is turned into NDC on the CPU —
 * four vertices per overlay is nothing, and it keeps rotation correct: rotating
 * in normalised coordinates on a non-square canvas shears, so corners are
 * rotated in an aspect-true space and only then divided back.
 *
 * Everything here runs on the GL thread. Export already lives there.
 */
internal class OverlayRenderer(private val frameHandler: Handler) {

    /** One overlay, resolved for one frame. */
    data class Draw(
        val textureId: Int,
        val isExternal: Boolean,
        /** Content shape (w/h) after EXIF/rotation, for the fit inside the box. */
        val contentAspect: Double,
        val centerX: Double,
        val centerY: Double,
        val boxWidth: Double,
        val boxHeight: Double,
        val scale: Double,
        val rotation: Double,
        val opacity: Double,
        /** `SurfaceTexture` transform for video; null for a bitmap. */
        val texMatrix: FloatArray?,
        /**
         * Sub-rect of the texture to sample (u0, v0, u1, v1), or null for the
         * whole texture. A glyph reads one cell of the atlas.
         */
        val srcRect: FloatArray? = null,
        /**
         * The overlay's shape as two vec4s, in the overlay's own box. See
         * `NativeTimelineOverlay.mask`. Defaults to no mask, so every existing
         * caller draws exactly as it did.
         */
        val mask: FloatArray = NativeTimelineClip.NO_MASK,
        /**
         * Where to place the quad inside the overlay's box, as box fractions
         * (left, top, right, bottom), or null to contain-fit the whole box —
         * which is what every image and video overlay does.
         *
         * For a glyph this is the **full padded cell**, not the glyph's box
         * rect: the cell is drawn whole so its bleed spills past the placement,
         * and the caller has already positioned the cell so that its `src`
         * sub-rect lands exactly on the box rect.
         */
        val boxRect: FloatArray? = null,
        /**
         * Per-glyph scale about the **glyph's own centre**, not the overlay's.
         *
         * Only meaningful with [boxRect] set; the defaults below are the
         * resting state, so an image or video overlay — which never sets
         * [boxRect] — is untouched by all four.
         */
        val glyphScale: Double = 1.0,
        /** Per-glyph rotation in radians, clockwise, about the glyph's centre. */
        val glyphRotation: Double = 0.0,
        /**
         * Per-glyph displacement of the glyph's centre, in **box-height
         * fractions** on both axes — a height metric for x as well as y, so a
         * diagonal move stays diagonal on a non-square box.
         */
        val glyphOffsetX: Double = 0.0,
        val glyphOffsetY: Double = 0.0,
    )

    /** A video overlay's decoder target: its own OES texture and surface. */
    class VideoLane {
        var textureId = 0
        var surfaceTexture: SurfaceTexture? = null
        var surface: Surface? = null
        val texMatrix = FloatArray(16)

        private val frameLock = ReentrantLock()
        private val frameArrived = frameLock.newCondition()
        private var frameSequence = 0L

        fun onFrameQueued() {
            frameLock.withLock {
                frameSequence++
                frameArrived.signalAll()
            }
        }

        fun frameSequence(): Long = frameLock.withLock { frameSequence }

        fun awaitFrameAfter(since: Long, timeoutMs: Long): Boolean = frameLock.withLock {
            var remaining = TimeUnit.MILLISECONDS.toNanos(timeoutMs)
            while (frameSequence <= since) {
                if (remaining <= 0L) return false
                remaining = try {
                    frameArrived.awaitNanos(remaining)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return false
                }
            }
            return true
        }

        fun release() {
            frameLock.withLock { frameArrived.signalAll() }
            surface?.release()
            surface = null
            surfaceTexture?.release()
            surfaceTexture = null
            GlUtil.deleteTexture(textureId)
            textureId = 0
        }
    }

    private var program2d = 0
    private var programOes = 0
    private var aPosition2d = -1
    private var aTexCoord2d = -1
    private var uAlpha2d = -1
    private var uMaskA2d = -1
    private var uMaskB2d = -1
    private var aPositionOes = -1
    private var aTexCoordOes = -1
    private var uAlphaOes = -1
    private var uMaskAOes = -1
    private var uMaskBOes = -1
    private var uTexMatrixOes = -1

    /** Uploaded bitmap textures, keyed by file path. */
    private val imageTextures = mutableMapOf<String, Pair<Int, Double>>()

    /** Live video overlay decode targets, keyed by overlay id. */
    private val videoLanes = mutableMapOf<String, VideoLane>()

    private val positions: FloatBuffer =
        ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()

    /** Rewritten per glyph; the draw consumes it before the next one is built. */
    private val glyphTexCoords: FloatBuffer =
        ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()

    // v=0 at the top for bitmaps (top-left origin), at the bottom for video
    // (the SurfaceTexture transform expects y-up coordinates).
    private val texCoordsTopDown: FloatBuffer = floatBufferOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f)
    private val texCoordsBottomUp: FloatBuffer = floatBufferOf(0f, 1f, 1f, 1f, 0f, 0f, 1f, 0f)

    /** Links both programs. Call once on the GL thread with a current context. */
    fun ensurePrograms() {
        if (program2d != 0) return

        program2d = GlUtil.createProgram(VERTEX, fragment(external = false))
        aPosition2d = GLES20.glGetAttribLocation(program2d, "aPosition")
        aTexCoord2d = GLES20.glGetAttribLocation(program2d, "aTexCoord")
        uAlpha2d = GLES20.glGetUniformLocation(program2d, "uAlpha")
        uMaskA2d = GLES20.glGetUniformLocation(program2d, "uMaskA")
        uMaskB2d = GLES20.glGetUniformLocation(program2d, "uMaskB")

        programOes = GlUtil.createProgram(VERTEX, fragment(external = true))
        aPositionOes = GLES20.glGetAttribLocation(programOes, "aPosition")
        aTexCoordOes = GLES20.glGetAttribLocation(programOes, "aTexCoord")
        uAlphaOes = GLES20.glGetUniformLocation(programOes, "uAlpha")
        uMaskAOes = GLES20.glGetUniformLocation(programOes, "uMaskA")
        uMaskBOes = GLES20.glGetUniformLocation(programOes, "uMaskB")
        uTexMatrixOes = GLES20.glGetUniformLocation(programOes, "uTexMatrix")
    }

    /** The already-uploaded texture for [path], so a hit skips the decode. */
    fun cachedImageTexture(path: String): Pair<Int, Double>? = imageTextures[path]

    /** The texture for [path], uploading [bitmap] on first sight. */
    fun imageTexture(path: String, bitmap: Bitmap): Pair<Int, Double> {
        imageTextures[path]?.let { return it }

        val textureId = GlUtil.createTexture2D(bitmap.width, bitmap.height)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
        GlUtil.checkGlError("overlay image upload")

        val entry = Pair(textureId, bitmap.width.toDouble() / bitmap.height)
        imageTextures[path] = entry
        return entry
    }

    /**
     * The decode target for video overlay [id], created on first use.
     *
     * The frame-available listener lands on [frameHandler]'s looper — never the
     * GL thread's, which the export loop occupies — the same arrangement the
     * clip lanes use for the same reason.
     */
    fun videoLane(id: String): VideoLane {
        videoLanes[id]?.let { return it }

        val lane = VideoLane()
        lane.textureId = GlUtil.createExternalTexture()
        Matrix.setIdentityM(lane.texMatrix, 0)
        val surfaceTexture = SurfaceTexture(lane.textureId)
        surfaceTexture.setOnFrameAvailableListener({ lane.onFrameQueued() }, frameHandler)
        lane.surfaceTexture = surfaceTexture
        lane.surface = Surface(surfaceTexture)
        videoLanes[id] = lane
        return lane
    }

    fun activeVideoLaneCount(): Int = videoLanes.size

    /** Pulls the newest decoded frame into [id]'s texture. */
    fun updateVideoLane(id: String) {
        val lane = videoLanes[id] ?: return
        try {
            lane.surfaceTexture?.updateTexImage()
            lane.surfaceTexture?.getTransformMatrix(lane.texMatrix)
        } catch (error: Exception) {
            Log.w(TAG, "Overlay $id texture update failed", error)
        }
    }

    /** Releases one video overlay whose window the playhead has left. */
    fun releaseVideoLane(id: String) {
        videoLanes.remove(id)?.release()
    }

    /**
     * Paints [draws] over whatever is in the framebuffer.
     *
     * Bitmaps upload premultiplied (that is how Android stores them), so the
     * blend is `ONE / ONE_MINUS_SRC_ALPHA` and opacity multiplies the whole
     * texel — which also fades an opaque video correctly.
     */
    fun draw(draws: List<Draw>, viewportWidth: Int, viewportHeight: Int) {
        if (draws.isEmpty() || viewportWidth <= 0 || viewportHeight <= 0) return
        ensurePrograms()

        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)

        val canvasAspect = viewportWidth.toDouble() / viewportHeight

        for (draw in draws) {
            if (draw.opacity <= 0.0 || draw.scale <= 0.0 || draw.textureId == 0) continue
            writeCorners(draw, canvasAspect)

            if (draw.isExternal) {
                GLES20.glUseProgram(programOes)
                GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
                GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, draw.textureId)
                GLES20.glUniform1f(uAlphaOes, draw.opacity.toFloat())
                bindMask(uMaskAOes, uMaskBOes, draw.mask)
                GLES20.glUniformMatrix4fv(
                    uTexMatrixOes,
                    1,
                    false,
                    draw.texMatrix ?: IDENTITY,
                    0,
                )
                drawQuad(aPositionOes, aTexCoordOes, texCoordsBottomUp)
            } else {
                GLES20.glUseProgram(program2d)
                GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, draw.textureId)
                GLES20.glUniform1f(uAlpha2d, draw.opacity.toFloat())
                bindMask(uMaskA2d, uMaskB2d, draw.mask)
                val texCoords = draw.srcRect?.let { writeGlyphTexCoords(it) }
                    ?: texCoordsTopDown
                drawQuad(aPosition2d, aTexCoord2d, texCoords)
            }
        }

        GLES20.glDisable(GLES20.GL_BLEND)
    }

    /**
     * The overlay's four corners in NDC, rotation applied in an aspect-true
     * space so a rotated overlay keeps its shape on a non-square canvas.
     */
    private fun writeCorners(draw: Draw, canvasAspect: Double) {
        val halfW: Double
        val halfH: Double
        var offsetX = 0.0
        var offsetY = 0.0
        // The glyph's own rotation, applied to its corners about its own centre
        // before the placement offset is added. Zero for every non-glyph draw.
        var glyphCos = 1.0
        var glyphSin = 0.0

        val boxRect = draw.boxRect
        if (boxRect != null) {
            // An exact placement inside the box: the quad covers this rect, no
            // contain-fit. A glyph's cell already has the right shape, so
            // fitting it again would letterbox a letter.
            val left = boxRect[0].toDouble()
            val top = boxRect[1].toDouble()
            val right = boxRect[2].toDouble()
            val bottom = boxRect[3].toDouble()
            // The glyph's own scale multiplies its half-extents, so it grows
            // about its own centre — `cornersX/Y` below are measured from that
            // centre, and `offsetX/Y` place the centre afterwards. Scaling the
            // offset too would push the letter away from the text block instead
            // of swelling it in place.
            halfW = 0.5 * draw.boxWidth * (right - left) * draw.scale * draw.glyphScale
            halfH = 0.5 * draw.boxHeight * (bottom - top) * draw.scale * draw.glyphScale
            // The rect's centre relative to the box's centre, displaced by the
            // glyph's own animated offset. That offset arrives in box-**height**
            // fractions on both axes (the catalog measures in glyph heights), so
            // both are scaled by `boxHeight`: converting x through `boxWidth`
            // would shear a diagonal slide on a non-square box.
            offsetX = draw.boxWidth * ((left + right) / 2.0 - 0.5) * draw.scale +
                draw.glyphOffsetX * draw.boxHeight * draw.scale
            offsetY = draw.boxHeight * ((top + bottom) / 2.0 - 0.5) * draw.scale +
                draw.glyphOffsetY * draw.boxHeight * draw.scale
            glyphCos = cos(draw.glyphRotation)
            glyphSin = sin(draw.glyphRotation)
        } else {
            // Content fitted inside the box, preserving its own shape — the same
            // contain-fit `ConstrainedBox` + `Image` produce in the preview.
            val fitW = if (draw.contentAspect >= 1.0) 1.0 else draw.contentAspect
            val fitH = if (draw.contentAspect >= 1.0) 1.0 / draw.contentAspect else 1.0
            halfW = 0.5 * draw.boxWidth * fitW * draw.scale
            halfH = 0.5 * draw.boxHeight * fitH * draw.scale
        }

        // Clockwise rotation with y-down, in height units so x and y rotate
        // through the same metric.
        val cosR = cos(draw.rotation)
        val sinR = sin(draw.rotation)

        // Order matches the texcoord buffers: TL, TR, BL, BR.
        val cornersX = doubleArrayOf(-halfW, halfW, -halfW, halfW)
        val cornersY = doubleArrayOf(-halfH, -halfH, halfH, halfH)

        positions.clear()
        for (i in 0 until 4) {
            // **Glyph transform first, in glyph space; overlay transform after,
            // in box space.** `cornersX/Y` are half-extents about the glyph's
            // own centre, so rotating them here spins the letter in place. Doing
            // it after `offsetX/Y` were added would rotate the letter about the
            // *text block's* centre instead — a bouncing letter swinging around
            // the whole caption rather than hopping where it sits.
            //
            // Rotation happens in the same aspect-true space the overlay's does:
            // x scaled up by `canvasAspect`, rotated, scaled back. Rotating in
            // raw normalised coordinates on a non-square canvas shears.
            //
            // The `glyphSin == 0` shortcut is not an optimisation: it keeps the
            // unrotated path — every image and video overlay, and any unrotated
            // glyph — on exactly the arithmetic it had before, rather than
            // through a multiply-by-`canvasAspect`-then-divide round trip that
            // is only *almost* the identity in floating point.
            val glyphX: Double
            val glyphY: Double
            if (glyphSin == 0.0 && glyphCos == 1.0) {
                glyphX = cornersX[i]
                glyphY = cornersY[i]
            } else {
                val gx = cornersX[i] * canvasAspect
                val gy = cornersY[i]
                glyphX = (gx * glyphCos - gy * glyphSin) / canvasAspect
                glyphY = gx * glyphSin + gy * glyphCos
            }

            // The glyph's own offset rotates with the box, so a rotated text
            // keeps its letters in line rather than each spinning in place.
            val px = (glyphX + offsetX) * canvasAspect
            val py = glyphY + offsetY
            val rx = (px * cosR - py * sinR) / canvasAspect
            val ry = px * sinR + py * cosR

            val xFrac = draw.centerX + rx
            val yFrac = draw.centerY + ry
            positions.put((xFrac * 2.0 - 1.0).toFloat())
            positions.put((1.0 - yFrac * 2.0).toFloat())
        }
        positions.flip()
    }

    /**
     * Texcoords for one atlas cell, in the TL, TR, BL, BR order the quad uses.
     *
     * v grows downward, matching [texCoordsTopDown] — an atlas is a bitmap, so
     * its origin is top-left and the rect arrives in that same sense.
     */
    private fun writeGlyphTexCoords(srcRect: FloatArray): FloatBuffer {
        val u0 = srcRect[0]
        val v0 = srcRect[1]
        val u1 = srcRect[2]
        val v1 = srcRect[3]
        glyphTexCoords.clear()
        glyphTexCoords.put(u0)
        glyphTexCoords.put(v0)
        glyphTexCoords.put(u1)
        glyphTexCoords.put(v0)
        glyphTexCoords.put(u0)
        glyphTexCoords.put(v1)
        glyphTexCoords.put(u1)
        glyphTexCoords.put(v1)
        glyphTexCoords.flip()
        return glyphTexCoords
    }

    private fun drawQuad(aPosition: Int, aTexCoord: Int, texCoords: FloatBuffer) {
        positions.position(0)
        texCoords.position(0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 0, positions)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, texCoords)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
    }

    /** Drops every export-scoped resource. Call on the GL thread. */
    fun releaseAll() {
        for ((textureId, _) in imageTextures.values) {
            GlUtil.deleteTexture(textureId)
        }
        imageTextures.clear()
        for (lane in videoLanes.values) {
            lane.release()
        }
        videoLanes.clear()
    }

    private fun fragment(external: Boolean): String {
        val declaration = if (external) {
            "#extension GL_OES_EGL_image_external : require\n" +
                "precision mediump float;\nuniform samplerExternalOES uTexture;\n" +
                "uniform mat4 uTexMatrix;\n"
        } else {
            "precision mediump float;\nuniform sampler2D uTexture;\n"
        }
        val lookup = if (external) {
            "texture2D(uTexture, (uTexMatrix * vec4(vTexCoord, 0.0, 1.0)).xy)"
        } else {
            "texture2D(uTexture, vTexCoord)"
        }
        return """$declaration
varying vec2 vTexCoord;
uniform float uAlpha;
uniform vec4 uMaskA;
uniform vec4 uMaskB;

// The overlay's shape, read in the overlay's own box. The same arithmetic as
// `maskCoverage` in TransitionShaders and its Dart twin in
// logic/mask/clip_mask.dart — if one changes they all must.
//
// a = (shape, centerX, centerY, feather), b = (width, height, inverted, radius)
float overlayMaskCoverage(vec2 p, vec4 a, vec4 b) {
    if (a.x < 0.5) {
        return 1.0;
    }
    vec2 c = a.yz;
    float feather = max(a.w, 0.001);
    vec2 halfSize = max(b.xy * 0.5, vec2(0.001));
    float coverage;
    if (a.x < 1.5) {
        vec2 d = abs(p - c) - halfSize;
        coverage = 1.0 - smoothstep(0.0, feather, max(d.x, d.y));
    } else if (a.x < 2.5) {
        float r = length((p - c) / halfSize);
        coverage = 1.0 - smoothstep(1.0, 1.0 + feather / max(halfSize.x, halfSize.y), r);
    } else if (a.x < 3.5) {
        coverage = 1.0 - smoothstep(c.x - feather, c.x + feather, p.x);
    } else {
        float rad = min(b.w, min(halfSize.x, halfSize.y));
        vec2 q = abs(p - c) - (halfSize - vec2(rad));
        float outside = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - rad;
        coverage = 1.0 - smoothstep(0.0, feather, outside);
    }
    return mix(coverage, 1.0 - coverage, b.z);
}

void main() {
    // The quad's own 0..1, which is the overlay's box — the space the mask is
    // authored in. Premultiplied alpha, so the coverage multiplies the whole
    // texel exactly as uAlpha does.
    float keep = overlayMaskCoverage(vTexCoord, uMaskA, uMaskB);
    gl_FragColor = $lookup * uAlpha * keep;
}
"""
    }

    /** The mask's two vec4s, or a no-mask pair when the uniform is absent. */
    private fun bindMask(uA: Int, uB: Int, mask: FloatArray) {
        if (uA < 0 || uB < 0 || mask.size < 8) return
        GLES20.glUniform4f(uA, mask[0], mask[1], mask[2], mask[3])
        GLES20.glUniform4f(uB, mask[4], mask[5], mask[6], mask[7])
    }

    private fun floatBufferOf(vararg values: Float): FloatBuffer {
        return ByteBuffer.allocateDirect(values.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .put(values)
            .apply { flip() } as FloatBuffer
    }

    private companion object {
        const val TAG = "SlimshotExport"

        val IDENTITY = FloatArray(16).also { Matrix.setIdentityM(it, 0) }

        const val VERTEX = """
attribute vec2 aPosition;
attribute vec2 aTexCoord;
varying vec2 vTexCoord;
void main() {
    vTexCoord = aTexCoord;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}
"""
    }
}
