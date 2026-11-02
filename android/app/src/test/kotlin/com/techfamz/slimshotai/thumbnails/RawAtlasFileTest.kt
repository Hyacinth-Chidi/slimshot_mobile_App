package com.techfamz.slimshotai.thumbnails

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The engine's half of a text atlas file, held to the fixture
 * `raw_atlas_file_test.dart` writes, so the format cannot mean one thing to
 * Flutter and another here.
 */
class RawAtlasFileTest {

    private fun fixture(): ByteArray =
        javaClass.getResourceAsStream("/raw_atlas_fixture.rgbz")?.use { it.readBytes() }
            ?: error(
                "raw_atlas_fixture.rgbz missing from test resources. Run: " +
                    "UPDATE_RAW_ATLAS_FIXTURE=1 flutter test " +
                    "test/features/video_editor/services/raw_atlas_file_test.dart",
            )

    // Premultiplied RGBA, as the Dart test writes them.
    private val pixels = intArrayOf(
        255, 0, 0, 255,
        0, 128, 0, 128,
        0, 0, 0, 0,
        10, 20, 30, 40,
    ).map { it.toByte() }.toByteArray()

    @Test
    fun `the fixture decodes to the pixels Flutter wrote`() {
        val read = RawAtlasFile.decode(fixture())!!
        assertEquals(2, read.width)
        assertEquals(2, read.height)
        assertArrayEquals(pixels, read.rgba)
    }

    @Test
    fun `an atlas is told apart from a picture by its first bytes`() {
        assertTrue(RawAtlasFile.isRawAtlas(fixture()))
        val png = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        assertFalse(RawAtlasFile.isRawAtlas(png))
        assertNull(RawAtlasFile.decode(png))
    }

    @Test
    fun `the size is read from the header alone`() {
        assertEquals(Pair(2, 2), RawAtlasFile.size(fixture()))
    }

    @Test
    fun `a short or mismatched file reads as none`() {
        assertNull(RawAtlasFile.decode(fixture().copyOf(3)))
        val wrongSize = fixture().copyOf()
        wrongSize[4] = 3 // width 3: pixels short of 3x2
        assertNull(RawAtlasFile.decode(wrongSize))
        assertNull(RawAtlasFile.decode(fixture().copyOf(fixture().size - 4)))
    }
}
