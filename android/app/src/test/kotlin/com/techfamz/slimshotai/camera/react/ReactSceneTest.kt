package com.techfamz.slimshotai.camera.react

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Where the live recorder draws each picture, and which part of it. */
class ReactSceneTest {

    private val whole = ReactRect(0f, 0f, 1f, 1f)

    @Test
    fun `a rect becomes four corners in triangle-strip order, in clip space`() {
        assertArrayEquals(floatArrayOf(-1f, 1f, -1f, -1f, 1f, 1f, 1f, -1f), ReactGeometry.positions(whole), 1e-6f)
        assertArrayEquals(
            floatArrayOf(-1f, 0f, -1f, -1f, 1f, 0f, 1f, -1f),
            ReactGeometry.positions(ReactRect(0f, 0.5f, 1f, 0.5f)),
            1e-6f,
        )
    }

    @Test
    fun `the whole picture, upright, in GL's y-up texture space`() {
        assertArrayEquals(floatArrayOf(0f, 1f, 0f, 0f, 1f, 1f, 1f, 0f), ReactGeometry.texCoords(whole), 1e-6f)
    }

    @Test
    fun `the bottom half of the picture samples the bottom of the texture`() {
        assertArrayEquals(
            floatArrayOf(0f, 0.5f, 0f, 0f, 1f, 0.5f, 1f, 0f),
            ReactGeometry.texCoords(ReactRect(0f, 0.5f, 1f, 0.5f)),
            1e-6f,
        )
    }

    @Test
    fun `a buffer the camera did not turn is turned here - its top left was the buffer's bottom left`() {
        val coords = ReactGeometry.texCoords(whole, quarterTurns = 1, yUp = false)
        assertEquals(0f, coords[0], 1e-6f)
        assertEquals(1f, coords[1], 1e-6f)
    }

    @Test
    fun `a selfie the camera did not mirror is mirrored here`() {
        val coords = ReactGeometry.texCoords(whole, mirrored = true, yUp = false)
        assertEquals(1f, coords[0], 1e-6f)
        assertEquals(0f, coords[1], 1e-6f)
    }

    @Test
    fun `four quarter turns are none`() {
        assertArrayEquals(
            ReactGeometry.texCoords(whole, yUp = false),
            ReactGeometry.texCoords(whole, quarterTurns = 4, yUp = false),
            1e-6f,
        )
    }

    @Test
    fun `a bitmap is top-left first, so y-down passes straight through`() {
        assertArrayEquals(
            floatArrayOf(0f, 0.5f, 0f, 1f, 1f, 0.5f, 1f, 1f),
            ReactGeometry.texCoords(ReactRect(0f, 0.5f, 1f, 0.5f), yUp = false),
            1e-6f,
        )
    }

    @Test
    fun `the scene reads from the channel, and anything unreadable is left out`() {
        val scene = ReactScene.fromMap(
            mapOf(
                "camera" to mapOf("dst" to listOf(0.0, 0.5, 1.0, 0.5), "src" to listOf(0.25, 0.0, 0.5, 1.0)),
                "video" to mapOf("dst" to listOf(0, 0, 1, 0.5), "src" to "junk"),
            ),
        )
        assertEquals(ReactQuad(ReactRect(0f, 0.5f, 1f, 0.5f), ReactRect(0.25f, 0f, 0.5f, 1f)), scene.camera)
        assertNull(scene.video)
        assertEquals(ReactScene.EMPTY, ReactScene.fromMap(null))
        assertNull(ReactScene.fromMap(mapOf("camera" to listOf(1, 2))).camera)
    }
}
