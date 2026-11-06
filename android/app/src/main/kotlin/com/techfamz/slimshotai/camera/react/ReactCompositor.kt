package com.techfamz.slimshotai.camera.react

import android.graphics.Bitmap
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Draws a [ReactScene]: black, then your camera's quad, then the video's —
 * the same draw for the screen and for the file, which is what makes the file
 * what was seen. GL thread only.
 */
internal class ReactCompositor {

    /** One picture to draw: a decoder's or camera's texture (external), or a photo's. */
    class Picture(
        val textureId: Int,
        val external: Boolean,
        val matrix: FloatArray,
        val quarterTurns: Int = 0,
        val mirrored: Boolean = false,
    )

    private var external = 0
    private var plain = 0
    private val positions: FloatBuffer = buffer()
    private val coords: FloatBuffer = buffer()

    fun setup() {
        external = program(EXTERNAL_FRAGMENT)
        plain = program(PLAIN_FRAGMENT)
    }

    fun draw(scene: ReactScene, width: Int, height: Int, camera: Picture?, video: Picture?) {
        GLES20.glViewport(0, 0, width, height)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        val cameraQuad = scene.camera
        if (cameraQuad != null && camera != null) quad(cameraQuad, camera)
        val videoQuad = scene.video
        if (videoQuad != null && video != null) quad(videoQuad, video)
    }

    private fun quad(quad: ReactQuad, picture: Picture) {
        val program = if (picture.external) external else plain
        GLES20.glUseProgram(program)
        positions.clear()
        positions.put(ReactGeometry.positions(quad.dst)).flip()
        coords.clear()
        coords.put(
            ReactGeometry.texCoords(
                quad.src,
                quarterTurns = picture.quarterTurns,
                mirrored = picture.mirrored,
                yUp = picture.external,
            ),
        ).flip()

        val position = GLES20.glGetAttribLocation(program, "aPosition")
        val coord = GLES20.glGetAttribLocation(program, "aTexCoord")
        GLES20.glEnableVertexAttribArray(position)
        GLES20.glVertexAttribPointer(position, 2, GLES20.GL_FLOAT, false, 0, positions)
        GLES20.glEnableVertexAttribArray(coord)
        GLES20.glVertexAttribPointer(coord, 2, GLES20.GL_FLOAT, false, 0, coords)
        GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(program, "uTexMatrix"), 1, false, picture.matrix, 0)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(if (picture.external) GLES11Ext.GL_TEXTURE_EXTERNAL_OES else GLES20.GL_TEXTURE_2D, picture.textureId)
        GLES20.glUniform1i(GLES20.glGetUniformLocation(program, "uTexture"), 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(position)
        GLES20.glDisableVertexAttribArray(coord)
    }

    fun release() {
        if (external != 0) GLES20.glDeleteProgram(external)
        if (plain != 0) GLES20.glDeleteProgram(plain)
        external = 0
        plain = 0
    }

    companion object {
        val IDENTITY: FloatArray = FloatArray(16).also { Matrix.setIdentityM(it, 0) }

        fun externalTexture(): Int {
            val ids = IntArray(1)
            GLES20.glGenTextures(1, ids, 0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, ids[0])
            parameters(GLES11Ext.GL_TEXTURE_EXTERNAL_OES)
            return ids[0]
        }

        /** A photo, uploaded once; bitmaps are top-left first. */
        fun bitmapTexture(bitmap: Bitmap): Int {
            val ids = IntArray(1)
            GLES20.glGenTextures(1, ids, 0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, ids[0])
            parameters(GLES20.GL_TEXTURE_2D)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
            return ids[0]
        }

        fun deleteTexture(id: Int) {
            if (id != 0) GLES20.glDeleteTextures(1, intArrayOf(id), 0)
        }

        private fun parameters(target: Int) {
            GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        }

        private fun buffer(): FloatBuffer =
            ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()

        private fun program(fragment: String): Int {
            val vertex = shader(GLES20.GL_VERTEX_SHADER, VERTEX)
            val pixel = shader(GLES20.GL_FRAGMENT_SHADER, fragment)
            val program = GLES20.glCreateProgram()
            GLES20.glAttachShader(program, vertex)
            GLES20.glAttachShader(program, pixel)
            GLES20.glLinkProgram(program)
            val linked = IntArray(1)
            GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linked, 0)
            GLES20.glDeleteShader(vertex)
            GLES20.glDeleteShader(pixel)
            check(linked[0] != 0) { "REACT program did not link: ${GLES20.glGetProgramInfoLog(program)}" }
            return program
        }

        private fun shader(type: Int, source: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val compiled = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
            check(compiled[0] != 0) { "REACT shader did not compile: ${GLES20.glGetShaderInfoLog(shader)}" }
            return shader
        }

        private const val VERTEX = """
attribute vec4 aPosition;
attribute vec4 aTexCoord;
uniform mat4 uTexMatrix;
varying vec2 vTexCoord;
void main() {
    gl_Position = aPosition;
    vTexCoord = (uTexMatrix * aTexCoord).xy;
}
"""

        private const val EXTERNAL_FRAGMENT = """
#extension GL_OES_EGL_image_external : require
precision mediump float;
varying vec2 vTexCoord;
uniform samplerExternalOES uTexture;
void main() {
    gl_FragColor = texture2D(uTexture, vTexCoord);
}
"""

        private const val PLAIN_FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
void main() {
    gl_FragColor = texture2D(uTexture, vTexCoord);
}
"""
    }
}
