package com.techfamz.slimshotai.nativepreview.gl

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.opengl.GLES11Ext
import android.util.Log
import android.view.Surface

/**
 * Minimal EGL 1.4 / OpenGL ES 2.0 context owner for the preview renderer.
 *
 * One instance lives on the render thread and owns the display, config and
 * context. Window surfaces are created from the preview [SurfaceTexture] and
 * recreated whenever the platform view resizes or is torn down.
 */
internal class EglCore {

    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private var config: EGLConfig? = null

    val isReady: Boolean
        get() = context != EGL14.EGL_NO_CONTEXT

    fun setup() {
        if (isReady) return

        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(display != EGL14.EGL_NO_DISPLAY) { "Unable to get an EGL display." }

        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) {
            "Unable to initialize EGL14."
        }

        val attributes = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val configCount = IntArray(1)
        check(
            EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, configCount, 0) &&
                configCount[0] > 0,
        ) { "Unable to find a suitable RGBA8888 EGL config." }
        config = configs[0]

        val contextAttributes = intArrayOf(
            EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL14.EGL_NONE,
        )
        context = EGL14.eglCreateContext(
            display,
            config,
            EGL14.EGL_NO_CONTEXT,
            contextAttributes,
            0,
        )
        checkEglError("eglCreateContext")
        check(context != EGL14.EGL_NO_CONTEXT) { "Unable to create an EGL context." }
    }

    /**
     * A 1x1 offscreen surface, used only so the context can be made current
     * before the platform view's surface exists. GL objects such as the
     * decoder's external texture have to be created against a current context,
     * and the player needs its surface well before the view is laid out.
     */
    fun createOffscreenSurface(): EGLSurface {
        val attributes = intArrayOf(
            EGL14.EGL_WIDTH, 1,
            EGL14.EGL_HEIGHT, 1,
            EGL14.EGL_NONE,
        )
        val surface = EGL14.eglCreatePbufferSurface(display, config, attributes, 0)
        checkEglError("eglCreatePbufferSurface")
        check(surface != EGL14.EGL_NO_SURFACE) { "Unable to create an EGL pbuffer surface." }
        return surface
    }

    fun createWindowSurface(surfaceTexture: SurfaceTexture): EGLSurface {
        return createWindowSurfaceFor(surfaceTexture)
    }

    /**
     * A window surface over an encoder's input [Surface].
     *
     * Export renders through the same GL path as the preview; the only
     * difference is where the finished frame goes — Flutter's texture while
     * previewing, `MediaCodec`'s input surface while exporting. That is what
     * makes an exported frame identical to the previewed one.
     */
    fun createWindowSurface(surface: Surface): EGLSurface {
        return createWindowSurfaceFor(surface)
    }

    private fun createWindowSurfaceFor(nativeWindow: Any): EGLSurface {
        val attributes = intArrayOf(EGL14.EGL_NONE)
        val surface = EGL14.eglCreateWindowSurface(
            display,
            config,
            nativeWindow,
            attributes,
            0,
        )
        checkEglError("eglCreateWindowSurface")
        check(surface != EGL14.EGL_NO_SURFACE) { "Unable to create an EGL window surface." }
        return surface
    }

    /**
     * Stamps the frame about to be swapped with its position in the output.
     *
     * The encoder takes its timestamps from the surface, so without this every
     * exported frame would carry the wall-clock time at which it happened to be
     * rendered — which is meaningless when the export runs faster than
     * realtime, and produces a file whose duration bears no relation to the
     * timeline's.
     */
    fun setPresentationTime(surface: EGLSurface, nanoseconds: Long) {
        EGLExt.eglPresentationTimeANDROID(display, surface, nanoseconds)
    }

    fun makeCurrent(surface: EGLSurface) {
        check(EGL14.eglMakeCurrent(display, surface, surface, context)) {
            "eglMakeCurrent failed."
        }
    }

    fun makeNothingCurrent() {
        EGL14.eglMakeCurrent(
            display,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_CONTEXT,
        )
    }

    fun swapBuffers(surface: EGLSurface): Boolean {
        return EGL14.eglSwapBuffers(display, surface)
    }

    fun releaseSurface(surface: EGLSurface?) {
        if (surface == null || surface == EGL14.EGL_NO_SURFACE) return
        EGL14.eglDestroySurface(display, surface)
    }

    fun release() {
        if (display != EGL14.EGL_NO_DISPLAY) {
            makeNothingCurrent()
            if (context != EGL14.EGL_NO_CONTEXT) {
                EGL14.eglDestroyContext(display, context)
            }
            EGL14.eglTerminate(display)
        }
        display = EGL14.EGL_NO_DISPLAY
        context = EGL14.EGL_NO_CONTEXT
        config = null
    }

    private fun checkEglError(operation: String) {
        val error = EGL14.eglGetError()
        if (error != EGL14.EGL_SUCCESS) {
            Log.e(TAG, "$operation failed: EGL error 0x${Integer.toHexString(error)}")
        }
    }

    companion object {
        private const val TAG = "EglCore"
    }
}

/** Small OpenGL ES 2.0 helpers shared by the preview renderer. */
internal object GlUtil {

    private const val TAG = "GlUtil"

    fun createProgram(vertexSource: String, fragmentSource: String): Int {
        val vertexShader = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragmentShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)

        val program = GLES20.glCreateProgram()
        check(program != 0) { "glCreateProgram failed." }

        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)

        val linked = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linked, 0)
        if (linked[0] != GLES20.GL_TRUE) {
            val log = GLES20.glGetProgramInfoLog(program)
            GLES20.glDeleteProgram(program)
            throw IllegalStateException("Program link failed: $log")
        }

        // The program keeps its own reference once linked.
        GLES20.glDeleteShader(vertexShader)
        GLES20.glDeleteShader(fragmentShader)
        return program
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        check(shader != 0) { "glCreateShader failed for type $type." }

        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)

        val compiled = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
        if (compiled[0] != GLES20.GL_TRUE) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw IllegalStateException("Shader compile failed: $log\nSource:\n$source")
        }
        return shader
    }

    /**
     * Creates the external texture ExoPlayer decodes into. Mipmapping and
     * repeat wrapping are unsupported on external textures, so clamp/linear are
     * the only valid choices.
     */
    fun createExternalTexture(): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        val textureId = textures[0]

        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, 0)
        return textureId
    }

    fun createTexture2D(width: Int, height: Int): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        val textureId = textures[0]

        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D,
            0,
            GLES20.GL_RGBA,
            width,
            height,
            0,
            GLES20.GL_RGBA,
            GLES20.GL_UNSIGNED_BYTE,
            null,
        )
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
        return textureId
    }

    fun deleteTexture(textureId: Int) {
        if (textureId == 0) return
        GLES20.glDeleteTextures(1, intArrayOf(textureId), 0)
    }

    fun checkGlError(operation: String) {
        val error = GLES20.glGetError()
        if (error != GLES20.GL_NO_ERROR) {
            Log.e(TAG, "$operation: glError 0x${Integer.toHexString(error)}")
        }
    }
}
