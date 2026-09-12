package com.techfamz.slimshotai.nativepreview.gl

import android.opengl.GLES20
import android.util.Log

/**
 * An offscreen colour buffer a pass can draw into instead of the screen.
 *
 * The renderer has always been single-pass — [TransitionRenderer] binds
 * framebuffer 0 and the finished frame goes straight to the output — which is
 * why the background's `blur` option falls back to black and why no effect that
 * needs to read its own result can exist. A shader cannot sample the texture it
 * is writing, so anything multi-pass needs somewhere to put the intermediate
 * frame. This is that somewhere.
 *
 * Colour only: one `GL_TEXTURE_2D` attachment, no depth and no stencil. Nothing
 * in this renderer is 3D — every pass is a full-screen quad — so a depth buffer
 * would be memory spent on a test that always passes.
 *
 * All of this is GL state, so every method here must run on the GL thread with
 * the context current.
 */
internal class RenderTarget private constructor(
    val textureId: Int,
    val width: Int,
    val height: Int,
    private var framebufferId: Int,
) {

    /**
     * Directs subsequent drawing into this target, at this target's size.
     *
     * The viewport is set here rather than left to the caller because the two
     * always belong together: `glViewport` is context state, so a target bound
     * without it inherits whatever size the previous bind left behind — and a
     * pass writing a 1080x1920 frame through a viewport still set to a
     * thumbnail renders into one corner of its target and leaves the rest of
     * the buffer as it was.
     */
    fun bind() {
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, framebufferId)
        GLES20.glViewport(0, 0, width, height)
    }

    /** Drops the framebuffer and its colour texture. Safe to call twice. */
    fun release() {
        if (framebufferId != 0) {
            GLES20.glDeleteFramebuffers(1, intArrayOf(framebufferId), 0)
            framebufferId = 0
        }
        GlUtil.deleteTexture(textureId)
    }

    internal companion object {
        const val TAG = "SlimshotGl"

        /**
         * Wraps an already-created colour texture in a framebuffer, or null.
         *
         * Kept private so a [RenderTarget] can only be built through
         * [createRenderTarget], which owns the texture's lifetime — a caller
         * that passed in its own texture would have to know not to delete it,
         * since [release] does.
         */
        fun wrap(textureId: Int, width: Int, height: Int): RenderTarget? {
            val framebuffers = IntArray(1)
            GLES20.glGenFramebuffers(1, framebuffers, 0)
            val framebufferId = framebuffers[0]
            if (framebufferId == 0) {
                Log.e(TAG, "glGenFramebuffers returned 0 for ${width}x$height")
                return null
            }

            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, framebufferId)
            GLES20.glFramebufferTexture2D(
                GLES20.GL_FRAMEBUFFER,
                GLES20.GL_COLOR_ATTACHMENT0,
                GLES20.GL_TEXTURE_2D,
                textureId,
                0,
            )

            // **Completeness is a real failure mode, not a formality.** A driver
            // is entitled to refuse a size or a format, and it refuses here
            // rather than at the allocation — so an unchecked attachment turns
            // into every later draw silently going nowhere, which reaches the
            // user as a black frame with nothing in the logs to explain it.
            // minSdk is 24 and this app spans a decade of hardware; the rule is
            // to probe at runtime and degrade loudly.
            val status = GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER)
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
            if (status != GLES20.GL_FRAMEBUFFER_COMPLETE) {
                Log.e(
                    TAG,
                    "Framebuffer incomplete for ${width}x$height: " +
                        "0x${Integer.toHexString(status)}",
                )
                GLES20.glDeleteFramebuffers(1, intArrayOf(framebufferId), 0)
                return null
            }

            return RenderTarget(textureId, width, height, framebufferId)
        }
    }
}

/**
 * A colour render target of [width] x [height], or null if the device refused.
 *
 * **Null, never a throw.** The caller's job is to disable whatever effect
 * wanted the target and warn, so the frame still renders — unprocessed, but
 * rendered. Throwing from the GL thread would take the preview down with the
 * effect, which is a far worse outcome than the effect simply not appearing.
 *
 * The texture is `GL_LINEAR` / `GL_CLAMP_TO_EDGE` from [GlUtil.createTexture2D].
 * Clamping is load-bearing for the blur this exists to enable: a blur kernel
 * samples past the frame's edge, and under `GL_REPEAT` those samples wrap round
 * and pull the opposite edge in, smearing the left of the picture into the
 * right. Clamping repeats the edge texel instead, which is what a blur of a
 * finite image is supposed to do.
 */
internal fun createRenderTarget(width: Int, height: Int): RenderTarget? {
    if (width <= 0 || height <= 0) {
        Log.e(RenderTarget.TAG, "Refusing a ${width}x$height render target")
        return null
    }

    val textureId = GlUtil.createTexture2D(width, height)
    GlUtil.checkGlError("createRenderTarget texture ${width}x$height")
    if (textureId == 0) {
        Log.e(RenderTarget.TAG, "Failed to allocate a ${width}x$height colour texture")
        return null
    }

    val target = RenderTarget.wrap(textureId, width, height)
    if (target == null) {
        // The texture is ours and nothing else has it, so it leaks unless this
        // path drops it explicitly.
        GlUtil.deleteTexture(textureId)
    }
    return target
}
