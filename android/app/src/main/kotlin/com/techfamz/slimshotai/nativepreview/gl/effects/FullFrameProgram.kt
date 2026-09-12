package com.techfamz.slimshotai.nativepreview.gl.effects

import android.opengl.GLES20
import com.techfamz.slimshotai.nativepreview.gl.GlUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * The plumbing every full-frame effect shader shares: one quad, one source
 * texture, an intensity, and the frame's shape.
 *
 * Each effect differs only in its fragment source, so everything around that
 * — the vertex shader, the attribute binding, the draw call, the uniform
 * lookups — is written once here. A copy of it per effect is sixteen chances to
 * mistype an attribute name into a shader that compiles, links, and draws
 * nothing.
 *
 * **`uAspect` is why this class carries the viewport at all.** An effect that
 * measures distance in texture coordinates measures it in a space where one
 * unit across is not one unit down, so a vignette on a 9:16 frame would be an
 * ellipse and a fisheye would bulge sideways. The shaders correct with this
 * rather than each deciding for itself, which also means the correction is the
 * same in a 400px preview and a 1080p export.
 *
 * GL thread only — construction links a program.
 */
internal class FullFrameProgram(fragmentSource: String) {

    private var handle = GlUtil.createProgram(VERTEX, fragmentSource)

    private val aPosition = GLES20.glGetAttribLocation(handle, "aPosition")
    private val aTexCoord = GLES20.glGetAttribLocation(handle, "aTexCoord")
    private val uTexture = GLES20.glGetUniformLocation(handle, "uTexture")
    private val uIntensity = GLES20.glGetUniformLocation(handle, "uIntensity")
    private val uAspect = GLES20.glGetUniformLocation(handle, "uAspect")

    fun use() = GLES20.glUseProgram(handle)

    /**
     * The effect's normalised 0..1 strength.
     *
     * Silently ignored by a shader that declares no `uIntensity` — the uniform
     * location is simply -1, which `glUniform1f` treats as a no-op. That is the
     * documented GL behaviour and it is what lets one program class serve
     * shaders with different uniform sets.
     */
    fun setIntensity(value: Float) {
        GLES20.glUniform1f(uIntensity, value)
    }

    /** Width over height of the frame being drawn, for distance correction. */
    fun setAspect(value: Float) {
        GLES20.glUniform1f(uAspect, value)
    }

    /** An extra uniform this program's shader declares. -1 when it does not. */
    fun location(name: String): Int = GLES20.glGetUniformLocation(handle, name)

    fun bindSource(textureId: Int) {
        bindTexture(GLES20.GL_TEXTURE0, 0, uTexture, textureId)
    }

    /**
     * Binds [textureId] to [unit] and points [location] at it.
     *
     * Used by the multi-texture passes — glow's composite reads the blurred
     * frame and the original scene at once. Always `GL_TEXTURE_2D`: a pass only
     * ever samples a render target, never a decoder's external texture, because
     * the lanes are composited before the chain runs.
     */
    fun bindTexture(textureUnit: Int, unitIndex: Int, location: Int, textureId: Int) {
        GLES20.glActiveTexture(textureUnit)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glUniform1i(location, unitIndex)
    }

    fun drawQuad() {
        QUAD_VERTICES.position(0)
        QUAD_TEX_COORDS.position(0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 0, QUAD_VERTICES)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, QUAD_TEX_COORDS)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)

        // Left on TEXTURE0 so the next program's single `bindSource` lands on
        // the unit it expects. A multi-texture pass leaves the active unit at
        // whatever it bound last, and the next pass would then bind its source
        // over that unit instead of unit 0 — a pass sampling a stale texture,
        // which reads as the effect showing the previous frame.
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
    }

    /** Deletes the program. Idempotent — several passes may share one. */
    fun release() {
        if (handle == 0) return
        GLES20.glDeleteProgram(handle)
        handle = 0
    }

    internal companion object {
        /**
         * Shared by every full-frame effect: a quad already in clip space, so
         * there is no matrix and nothing to get wrong per effect.
         */
        const val VERTEX = """
attribute vec2 aPosition;
attribute vec2 aTexCoord;
varying vec2 vTexCoord;
void main() {
    vTexCoord = aTexCoord;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}
"""

        private val QUAD_VERTICES: FloatBuffer =
            floatBufferOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)

        private val QUAD_TEX_COORDS: FloatBuffer =
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
    }
}
