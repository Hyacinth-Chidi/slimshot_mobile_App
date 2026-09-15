package com.techfamz.slimshotai.nativepreview.gl.effects

import android.opengl.GLES20
import com.techfamz.slimshotai.nativepreview.gl.EffectPass
import com.techfamz.slimshotai.nativepreview.gl.GlUtil
import com.techfamz.slimshotai.nativepreview.gl.RenderTarget
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
            field = value.coerceIn(0.0, MAX_RADIUS_FRACTION)
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
        if (radiusPx <= 0.0) return

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
         * blur that large wants a downsampled pass rather than a wider stride.
         * 0.014 is ~15px at 1080 on the short side, comfortably inside the
         * unstrided kernel.
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
        fun chain(radiusFraction: Double = DEFAULT_RADIUS_FRACTION): List<BlurPass> {
            val program = BlurProgram()
            val horizontal = BlurPass(program, 1f, 0f, "blur.h")
            val vertical = BlurPass(program, 0f, 1f, "blur.v")
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
 * intensity has to reach the radius without a rebuild — but with a **different
 * mapping**, which is why the two cannot be one class. Here the blur *is* the
 * effect, so intensity 1 means as soft as the kernel will honestly go; in a
 * bloom the radius is a supporting parameter and tops out lower. One class
 * holding both mappings would need a mode flag deciding which is in force.
 *
 * Unlike glow's halves this runs at **full resolution**. A bloom is by
 * definition the low-frequency part of the picture and is screened back over a
 * sharp scene, so nobody can see it computed small; a foreground blur is the
 * picture itself, and a half-resolution one would read as the upsample's
 * softness rather than as the gaussian's. If `blur` ever wants a radius past
 * the cap, that is the moment to reconsider — not before.
 */
internal class StandaloneBlurPass(
    private val blur: BlurPass,
) : EffectPass by blur, IntensityControlled {

    override fun applyIntensity(intensity: Float) {
        val clamped = intensity.coerceIn(0f, 1f)
        blur.radiusFraction = (
            MIN_RADIUS_FRACTION + (MAX_RADIUS_FRACTION - MIN_RADIUS_FRACTION) * clamped
            ).toDouble()
    }

    /** Deletes the shared program. Idempotent — both halves hold the same one. */
    fun release() {
        blur.release()
    }

    internal companion object {
        /**
         * Radius at intensity 0.
         *
         * Not zero: an effect the user has applied must visibly do something at
         * every slider position, or the bottom of the range reads as the effect
         * being broken. A touch of softening is the honest floor.
         */
        const val MIN_RADIUS_FRACTION = 0.002f

        /**
         * Radius at intensity 1 — the full kernel, right at the density cap.
         *
         * [BlurPass.MAX_RADIUS_FRACTION] is where 16 taps begin to band as the
         * stride widens, and a blur is exactly the effect where banding would be
         * obvious, so this sits on the cap rather than past it.
         */
        const val MAX_RADIUS_FRACTION = BlurPass.MAX_RADIUS_FRACTION.toFloat()
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
