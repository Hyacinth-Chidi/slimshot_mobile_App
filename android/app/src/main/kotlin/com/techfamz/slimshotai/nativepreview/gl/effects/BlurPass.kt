package com.techfamz.slimshotai.nativepreview.gl.effects

import android.opengl.GLES20
import com.techfamz.slimshotai.nativepreview.gl.EffectPass
import com.techfamz.slimshotai.nativepreview.gl.GlUtil
import com.techfamz.slimshotai.nativepreview.gl.RenderTarget
import com.techfamz.slimshotai.nativepreview.gl.createRenderTarget
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * A gaussian blur, as two one-dimensional passes.
 *
 * **Separable, never an NxN grid.** A 2D gaussian factorises into a horizontal
 * convolution followed by a vertical one, which is the whole reason this is two
 * passes: a radius of 12 costs 25 texture reads per pixel per axis — 50 in
 * total — where the equivalent square kernel costs 625. On the low-end target
 * that difference is the entire frame budget, and a blur is exactly the effect a
 * user will drag a slider on while playback runs.
 *
 * Build the pair with [chain] and hand it straight to
 * `TransitionRenderer.setEffectPasses`; the two halves share one linked program,
 * because the shader is identical and only the axis differs.
 *
 * **The axis lives on the instance, not on `passIndex`.** The interface offers
 * `passIndex` precisely so a shader used twice can tell its invocations apart,
 * but that index is the pass's position in the *whole* chain — so an instance
 * deriving its axis from `index % 2` blurs along the wrong one the moment
 * anything else is scheduled before it. A blur that silently smears diagonally
 * when a second effect is added is the kind of coupling worth one extra object
 * to avoid.
 *
 * Everything here runs on the GL thread with the context current.
 */
internal class BlurPass private constructor(
    private val program: BlurProgram,
    /** (1, 0) for the horizontal half, (0, 1) for the vertical one. */
    private val axisX: Float,
    private val axisY: Float,
    override val id: String,
    /**
     * The largest [radiusFraction] this instance accepts.
     *
     * [MAX_RADIUS_FRACTION] — the full-resolution kernel's density cap — for
     * every caller that draws at the frame's own size. Soft Blur raises it,
     * because it draws a large radius into a reduced copy where the taps cover
     * it at the same density ([StandaloneBlurPass]).
     */
    private val maxRadiusFraction: Double = MAX_RADIUS_FRACTION,
) : EffectPass {

    /**
     * Blur radius as a fraction of the frame's **short side**.
     *
     * Not pixels, and this is load-bearing. The preview canvas is capped at
     * `kMaxPreviewCanvasPx` while an export renders at whatever the SD/HD/2K
     * selector asked for, so the same pixel radius would blur the canvas
     * several times as hard as the file — the preview/export mismatch this
     * codebase has hit with overlay geometry (device pixels in the timeline
     * contract) and again with text raster density. A fraction resolves against
     * whatever viewport is being drawn, so one stored value looks the same in
     * both.
     *
     * Written from the main thread, read on the GL thread, like the renderer's
     * other per-frame state.
     */
    @Volatile
    var radiusFraction: Double = DEFAULT_RADIUS_FRACTION
        set(value) {
            field = value.coerceIn(0.0, maxRadiusFraction)
        }

    override fun render(
        sourceTextureId: Int,
        target: RenderTarget?,
        viewportWidth: Int,
        viewportHeight: Int,
        passIndex: Int,
    ) {
        if (viewportWidth <= 0 || viewportHeight <= 0) return

        // A null target means "whatever is bound", so the viewport has to be set
        // here — the pass cannot ask the bound framebuffer how big it is.
        if (target != null) {
            target.bind()
        } else {
            GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
        }

        // The short side, so a portrait and a landscape frame of the same
        // resolution blur by the same visible amount.
        val shortSide = min(viewportWidth, viewportHeight)
        val radiusPx = radiusFraction * shortSide

        // **A zero radius still has to draw.** Returning here would leave the
        // target holding whatever the ping-pong buffer had from two frames ago,
        // and the chain hands that texture on as its result — a stale frame
        // presented as the current one, which reads as the picture freezing.
        // Nothing hit this while every caller had a non-zero minimum radius;
        // `blur_in` drives the radius to exactly zero as it settles, which is
        // the correct settled state and must be a passthrough, not a skip.
        //
        // One tap at the centre with weight 1 *is* the identity: the loop's
        // other taps carry zero weight, so the result is exactly the source
        // texel, and the frame is copied rather than filtered.
        if (radiusPx <= 0.0) {
            GLES20.glDisable(GLES20.GL_BLEND)
            program.use()
            program.setStep(0f, 0f)
            program.setWeights(weightsFor(0))
            program.bindSource(sourceTextureId)
            program.drawQuad(quadVertices, quadTexCoords)
            return
        }

        // **When the radius outruns the tap budget, spread the taps — never
        // clamp the radius.** The kernel is a fixed 16 taps per side, so a
        // 2K export asking for 20px would otherwise be truncated to 16 and come
        // out *less* blurred than the 1080 preview it was checked against: the
        // exact resolution-dependent mismatch the fraction exists to prevent,
        // reappearing at the one end nobody looks at. Striding instead keeps the
        // blur the same *size* at every resolution and pays for it in sampling
        // density, which is the right way round — a slightly coarser 2K blur is
        // invisible, a smaller one is wrong.
        //
        // The lower bound of 1 is not decoration: a sub-pixel radius on a small
        // viewport rounds to zero taps, and `radiusPx / 0` is an infinite stride
        // — every tap sampling the clamped edge, i.e. a frame of flat colour.
        // One tap at a sub-texel stride is the honest answer there: a blur too
        // small to see, which is what was asked for.
        val taps = radiusPx.roundToInt().coerceIn(1, MAX_TAPS)
        val stride = (radiusPx / taps).toFloat()

        // A pass *replaces* its target's contents; it never composites onto
        // them. Blending is context state, so leaving it to whoever drew last
        // means the blur would mix with whatever the ping-pong buffer held from
        // two frames ago the moment something upstream enables it — a ghost of
        // the previous frame, which reads as the blur being wrong rather than as
        // a stray GL flag.
        GLES20.glDisable(GLES20.GL_BLEND)

        program.use()

        // **Texels of the texture being sampled**, which is the scene target —
        // allocated at exactly the output size, so the output viewport's
        // dimensions are the right denominator. ES 2.0 has no `textureSize()`,
        // so the step has to arrive as a uniform. `stride` widens the gap
        // between taps when the radius needed more of them than there are.
        program.setStep(
            axisX * stride / viewportWidth.toFloat(),
            axisY * stride / viewportHeight.toFloat(),
        )
        program.setWeights(weightsFor(taps))
        program.bindSource(sourceTextureId)
        program.drawQuad(quadVertices, quadTexCoords)
    }

    /**
     * Frees the shared program.
     *
     * Idempotent, and safe to call on every pass of a [chain] — both halves
     * hold the same [BlurProgram], and the caller holding a list has no way to
     * know that. The alternative, asking callers to release exactly one, is the
     * kind of rule that leaks a program the first time someone loops over the
     * list.
     *
     * GL thread only.
     */
    fun release() {
        program.release()
    }

    internal companion object {
        /**
         * Taps per side of centre, fixed because **ES 2.0 requires a
         * compile-time constant loop bound**: `for (int i = 0; i < uRadius; i++)`
         * does not compile, and the failure only shows up as a black frame on a
         * device, never at build time.
         *
         * The alternative — a shader variant per radius bucket — was rejected:
         * it puts a `glLinkProgram` in the render path every time a slider
         * crosses a bucket edge, which is the cost `warmUpShaders` exists to
         * keep out of it. Zero-weighting the unused taps instead costs a few
         * wasted samples of a texture already in cache and keeps one program for
         * every radius.
         */
        const val MAX_TAPS = 16

        /**
         * Ceiling on the stored fraction — a sanity bound, not a tap budget.
         *
         * The stride in [render] means the taps never truncate the radius, so
         * what this guards is sampling density: past roughly this much the 16
         * taps are far enough apart that the gaussian starts to band, and a
         * blur that large wants a downsampled pass rather than a wider stride —
         * which is what Soft Blur does ([StandaloneBlurPass]), raising its own
         * instances' cap through [chain]. 0.014 is ~15px at 1080 on the short
         * side, comfortably inside the unstrided kernel.
         *
         * **A fraction of whatever viewport the pass is handed**, so drawing
         * into a half-size target with the half-size viewport blurs the same
         * share of the picture: the reduction buys sampling density, not reach.
         */
        const val MAX_RADIUS_FRACTION = 0.014

        const val DEFAULT_RADIUS_FRACTION = 0.008

        /**
         * Sigma as a fraction of the radius. A gaussian is ~0.3% of its peak at
         * three sigma, so a kernel truncated at 3*sigma loses nothing visible
         * while keeping every tap doing useful work.
         */
        const val SIGMA_SCALE = 1.0 / 3.0

        /**
         * Normalised weights for the centre tap and [MAX_TAPS] on each side.
         *
         * [taps] counts taps per side, **not** pixels: the caller may have
         * widened the stride, in which case tap `i` sits at `i * stride` texels
         * and the gaussian is shaped in tap space. That is what keeps the curve
         * the same shape whatever the stride is.
         *
         * Index 0 is the centre; anything past [taps] is **exactly zero**, which
         * is what makes the fixed loop bound correct rather than merely
         * survivable — those taps still sample, but contribute nothing, so the
         * picture is the kernel the caller asked for.
         *
         * Zero taps gives a pure passthrough (centre 1, everything else 0)
         * rather than a division by a zero sigma.
         */
        fun weightsFor(taps: Int): FloatArray {
            val weights = FloatArray(MAX_TAPS + 1)
            val radiusPx = taps.coerceAtMost(MAX_TAPS)
            if (radiusPx <= 0) {
                weights[0] = 1f
                return weights
            }

            val sigma = radiusPx * SIGMA_SCALE
            val twoSigmaSquared = 2.0 * sigma * sigma
            var sum = 0.0
            for (i in 0..radiusPx) {
                val weight = exp(-(i * i) / twoSigmaSquared)
                weights[i] = weight.toFloat()
                // Every tap but the centre is sampled on both sides, so it
                // counts twice toward the total the kernel is normalised by.
                sum += if (i == 0) weight else 2.0 * weight
            }

            // Normalising to 1 is what keeps the frame's brightness unchanged;
            // an unnormalised gaussian darkens or blows out the picture in
            // proportion to the radius, which reads as the effect being wrong
            // rather than as a missing divide.
            val scale = (1.0 / max(sum, 1e-6)).toFloat()
            for (i in 0..radiusPx) {
                weights[i] *= scale
            }
            return weights
        }

        /** Fullscreen quad in NDC, and its texcoords. Same layout the renderer uses. */
        val quadVertices: FloatBuffer =
            floatBufferOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)

        val quadTexCoords: FloatBuffer =
            floatBufferOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f)

        private fun floatBufferOf(vararg values: Float): FloatBuffer {
            return ByteBuffer.allocateDirect(values.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .apply {
                    put(values)
                    position(0)
                }
        }

        /**
         * The two halves of one blur, in the order they must run.
         *
         * Both share a program, and [radiusFraction] is set on each — which is
         * deliberate: a radius that differed between the axes would be a
         * directional smear, not a gaussian.
         *
         * **Call on the GL thread**: it links a program.
         */
        fun chain(
            radiusFraction: Double = DEFAULT_RADIUS_FRACTION,
            maxRadiusFraction: Double = MAX_RADIUS_FRACTION,
        ): List<BlurPass> {
            val program = BlurProgram()
            val horizontal = BlurPass(program, 1f, 0f, "blur.h", maxRadiusFraction)
            val vertical = BlurPass(program, 0f, 1f, "blur.v", maxRadiusFraction)
            horizontal.radiusFraction = radiusFraction
            vertical.radiusFraction = radiusFraction
            return listOf(horizontal, vertical)
        }
    }
}

/**
 * The `blur` catalog entry: a plain gaussian softening of the whole frame.
 *
 * A wrapper around [BlurPass] for the same reason [GlowBlurPass] is one — the
 * intensity has to reach the radius without a rebuild — with its own mapping,
 * because here the blur *is* the effect.
 *
 * ### Drawn small once it is wide
 *
 * It used to stop at [BlurPass.MAX_RADIUS_FRACTION], ~15px at 1080, and on a
 * phone that read as barely soft (device-reported, alongside a `ramp_out`
 * envelope that held the middle of every bar at the floor). The 16-tap kernel
 * cannot reach further at full resolution without banding, so a wide blur is
 * drawn into a **reduced copy**: the horizontal half writes it, the vertical
 * half reads it back up into the chain's full-size target — the arrangement
 * [GlowBlurPass] uses for the bloom. The radius is a fraction of the viewport
 * each draw is handed, so the reduction changes the sampling grid, not the
 * size of the blur.
 *
 * **The reduction is chosen per frame from the radius in pixels**
 * ([downscaleFor]): the least power of two that brings the radius inside the
 * taps. So a light blur stays at full resolution, exactly as it always drew,
 * and the copy only shrinks once the gaussian is wide enough — two and a half
 * reduced texels of sigma or more — that neither the cheap downsample nor the
 * bilinear upsample can show. The choice follows the frame being drawn, so the
 * ~720px preview and a 1080 export blur the same share of the picture, each
 * on the finest grid its taps can cover.
 *
 * Copies are kept per scale once made — a slider dragged across a threshold,
 * or a keyframed blur crossing one, never allocates per frame — and dropped
 * when the frame's size changes. A device that refuses a copy gets the
 * full-resolution blur, coarser past the cap but still a blur.
 *
 * Like glow's halves, this relies on `EffectPassChain.run` giving every pass a
 * target: the vertical half sets the viewport by binding it.
 */
internal class StandaloneBlurPass(
    private val blur: BlurPass,
    /** True for the half that draws into the reduced copy — the horizontal one. */
    private val ownsDownscale: Boolean,
) : EffectPass, IntensityControlled {

    override val id: String = blur.id

    /** The reduced copies made so far, by scale, at [copiesWidth] x [copiesHeight]. */
    private val copies = HashMap<Int, RenderTarget>()

    /** Scales the device refused at this size; not asked for again until it changes. */
    private val refused = HashSet<Int>()
    private var copiesWidth = 0
    private var copiesHeight = 0

    /**
     * The copy the horizontal half drew into this frame, or null for full
     * resolution. Set on every draw, so the vertical half — drawn straight
     * after it in the same chain — always reads this frame's choice.
     */
    private var drawnInto: RenderTarget? = null

    /** The horizontal half, for the vertical one. */
    private var owner: StandaloneBlurPass? = null

    override fun applyIntensity(intensity: Float) {
        blur.radiusFraction = radiusFractionFor(intensity)
    }

    override fun render(
        sourceTextureId: Int,
        target: RenderTarget?,
        viewportWidth: Int,
        viewportHeight: Int,
        passIndex: Int,
    ) {
        if (viewportWidth <= 0 || viewportHeight <= 0) return

        if (ownsDownscale) {
            val radiusPx = blur.radiusFraction * min(viewportWidth, viewportHeight)
            val small = copyFor(viewportWidth, viewportHeight, downscaleFor(radiusPx))
            drawnInto = small
            if (small == null) {
                blur.render(sourceTextureId, target, viewportWidth, viewportHeight, passIndex)
            } else {
                // Down: the viewport handed on is the copy's, so the radius and
                // the step are measured against the texture being written.
                blur.render(sourceTextureId, small, small.width, small.height, passIndex)
            }
        } else {
            val small = owner?.drawnInto
            if (small == null) {
                blur.render(sourceTextureId, target, viewportWidth, viewportHeight, passIndex)
            } else {
                // Up: the step divides by the copy being sampled, and binding
                // the full-size target sets the real viewport. The chain's
                // source here is the horizontal half's untouched target.
                blur.render(small.textureId, target, small.width, small.height, passIndex)
            }
        }
    }

    /** The reduced copy at [scale] for a [width] x [height] frame; null for none. */
    private fun copyFor(width: Int, height: Int, scale: Int): RenderTarget? {
        if (width != copiesWidth || height != copiesHeight) {
            releaseCopies()
            copiesWidth = width
            copiesHeight = height
        }
        if (scale <= 1 || scale in refused) return null
        copies[scale]?.let { return it }

        val created = createRenderTarget(max(1, width / scale), max(1, height / scale))
        if (created == null) {
            refused += scale
            return null
        }
        copies[scale] = created
        return created
    }

    private fun releaseCopies() {
        for (copy in copies.values) copy.release()
        copies.clear()
        refused.clear()
        drawnInto = null
    }

    /** Pairs this horizontal half with its vertical half. */
    fun shareDownscaleWith(other: StandaloneBlurPass) {
        other.owner = this
    }

    /** Deletes the shared program and any copies. Idempotent. GL thread only. */
    fun release() {
        blur.release()
        releaseCopies()
    }

    internal companion object {
        /**
         * Radius at intensity 0, as a fraction of the short side: a touch of
         * softening, because an applied effect must do something at every
         * slider position.
         */
        const val MIN_RADIUS_FRACTION = 0.002

        /**
         * Radius at intensity 1: four times the full-resolution kernel's cap,
         * ~60px at 1080 — a sigma of about 2% of the frame, which reads as the
         * picture blurred rather than as the picture soft. The default 0.4
         * lands near 0.024, already past the old maximum.
         */
        const val MAX_RADIUS_FRACTION = BlurPass.MAX_RADIUS_FRACTION * 4

        /** The most a copy is reduced: a 2K export's strongest blur fits at 1/8. */
        const val MAX_DOWNSCALE = 8

        fun radiusFractionFor(intensity: Float): Double {
            val clamped = intensity.coerceIn(0f, 1f).toDouble()
            return MIN_RADIUS_FRACTION + (MAX_RADIUS_FRACTION - MIN_RADIUS_FRACTION) * clamped
        }

        /**
         * How much smaller to draw a blur of [radiusPx] full-resolution
         * pixels: 1 while the taps cover it, else the least power of two that
         * brings it inside them, up to [MAX_DOWNSCALE].
         */
        fun downscaleFor(radiusPx: Double): Int {
            var scale = 1
            while (scale < MAX_DOWNSCALE && radiusPx / scale > BlurPass.MAX_TAPS) scale *= 2
            return scale
        }
    }
}

/**
 * The linked blur program and its uniform locations.
 *
 * One program serves both axes: the axis is a uniform, so there is nothing to
 * specialise and a second link would be pure cost.
 */
internal class BlurProgram {

    private var handle = GlUtil.createProgram(VERTEX, FRAGMENT)

    private val aPosition = GLES20.glGetAttribLocation(handle, "aPosition")
    private val aTexCoord = GLES20.glGetAttribLocation(handle, "aTexCoord")
    private val uTexture = GLES20.glGetUniformLocation(handle, "uTexture")
    private val uStep = GLES20.glGetUniformLocation(handle, "uStep")
    private val uWeights = GLES20.glGetUniformLocation(handle, "uWeights")

    fun use() = GLES20.glUseProgram(handle)

    /** The offset between neighbouring taps, in texture coordinates. */
    fun setStep(x: Float, y: Float) {
        GLES20.glUniform2f(uStep, x, y)
    }

    fun setWeights(weights: FloatArray) {
        GLES20.glUniform1fv(uWeights, weights.size, weights, 0)
    }

    fun bindSource(textureId: Int) {
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        // Always `GL_TEXTURE_2D`: a pass only ever reads a [RenderTarget]'s
        // colour attachment, never a decoder's external texture — the scene is
        // composited before the chain ever runs.
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glUniform1i(uTexture, 0)
    }

    fun drawQuad(vertices: FloatBuffer, texCoords: FloatBuffer) {
        vertices.position(0)
        texCoords.position(0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 0, vertices)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, texCoords)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
    }

    /** Deletes the program. Safe to call twice: both blur halves share one. */
    fun release() {
        if (handle == 0) return
        GLES20.glDeleteProgram(handle)
        handle = 0
    }

    private companion object {
        const val VERTEX = """
attribute vec2 aPosition;
attribute vec2 aTexCoord;
varying vec2 vTexCoord;
void main() {
    vTexCoord = aTexCoord;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}
"""

        /**
         * One axis of a gaussian.
         *
         * Written against GLSL ES 1.00 (`#version 100`, the implicit default),
         * which is stricter than it looks and is compiled at runtime — a mistake
         * here is a black frame on a device, not a build failure:
         *
         * * `attribute`/`varying`, never `in`/`out`.
         * * `texture2D`, never `texture`.
         * * An explicit fragment precision, because ES 2.0 defines no default
         *   `float` precision in a fragment shader and a shader without one
         *   fails to compile on a conforming driver.
         * * **A constant loop bound.** `MAX_TAPS` is substituted as a literal,
         *   so the loop is unrollable — a loop over a uniform is not, and ES 2.0
         *   rejects it outright.
         *
         * Taps past the requested radius carry a zero weight, so they cost a
         * cached texture read and change nothing. Sampling symmetrically about
         * the centre in one statement keeps the tap count at `2N+1` rather than
         * looping twice.
         *
         * `GL_CLAMP_TO_EDGE` on the render target is what makes the off-frame
         * taps correct: under `GL_REPEAT` a kernel reaching past the left edge
         * would pull the right edge in and smear one side of the picture into
         * the other.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform vec2 uStep;
uniform float uWeights[${BlurPass.MAX_TAPS + 1}];
void main() {
    vec4 sum = texture2D(uTexture, vTexCoord) * uWeights[0];
    for (int i = 1; i <= ${BlurPass.MAX_TAPS}; i++) {
        vec2 offset = uStep * float(i);
        sum += (texture2D(uTexture, vTexCoord + offset) +
                texture2D(uTexture, vTexCoord - offset)) * uWeights[i];
    }
    gl_FragColor = sum;
}
"""
    }
}
