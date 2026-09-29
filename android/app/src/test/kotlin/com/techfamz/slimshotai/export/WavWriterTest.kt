package com.techfamz.slimshotai.export

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The caption audio is plain PCM in a WAV, so that a word's time in the file
 * is its time on the timeline: an AAC encoder opens every stream with a run of
 * priming samples, and heard through one every word arrived late.
 */
class WavWriterTest {

    private fun written(sampleRate: Int, channels: Int, vararg blocks: ShortArray): ByteArray {
        val file = File.createTempFile("wav", ".wav")
        try {
            WavWriter(file, sampleRate, channels).use { wav ->
                for (block in blocks) wav.write(block, block.size)
            }
            return file.readBytes()
        } finally {
            file.delete()
        }
    }

    private fun ByteArray.text(at: Int) = String(this, at, 4, Charsets.US_ASCII)
    private fun ByteArray.int(at: Int) =
        ByteBuffer.wrap(this, at, 4).order(ByteOrder.LITTLE_ENDIAN).int
    private fun ByteArray.short(at: Int) =
        ByteBuffer.wrap(this, at, 2).order(ByteOrder.LITTLE_ENDIAN).short.toInt()

    @Test
    fun `the header describes 16-bit PCM at the given rate and layout`() {
        val bytes = written(16_000, 1, shortArrayOf(1, 2, 3))
        assertEquals("RIFF", bytes.text(0))
        assertEquals("WAVE", bytes.text(8))
        assertEquals("fmt ", bytes.text(12))
        assertEquals(16, bytes.int(16))
        assertEquals(1, bytes.short(20))
        assertEquals(1, bytes.short(22))
        assertEquals(16_000, bytes.int(24))
        assertEquals(32_000, bytes.int(28))
        assertEquals(2, bytes.short(32))
        assertEquals(16, bytes.short(34))
        assertEquals("data", bytes.text(36))
    }

    @Test
    fun `the sizes are those of what was written`() {
        val bytes = written(16_000, 1, shortArrayOf(1, 2, 3), shortArrayOf(4, 5))
        assertEquals(44 + 10, bytes.size)
        assertEquals(36 + 10, bytes.int(4))
        assertEquals(10, bytes.int(40))
    }

    @Test
    fun `samples are little-endian, in order, from the first byte of data`() {
        val bytes = written(16_000, 1, shortArrayOf(1, -2, 0x1234))
        assertArrayEquals(
            byteArrayOf(0x01, 0x00, 0xFE.toByte(), 0xFF.toByte(), 0x34, 0x12),
            bytes.copyOfRange(44, 50),
        )
    }

    @Test
    fun `only the counted samples of a block are written`() {
        val file = File.createTempFile("wav", ".wav")
        try {
            val frames = WavWriter(file, 16_000, 1).use { wav ->
                wav.write(shortArrayOf(7, 8, 9, 10), 2)
                wav.framesWritten
            }
            assertEquals(2L, frames)
            assertEquals(44 + 4, file.readBytes().size)
        } finally {
            file.delete()
        }
    }

    @Test
    fun `stereo counts a frame as two samples`() {
        val file = File.createTempFile("wav", ".wav")
        try {
            val frames = WavWriter(file, 44_100, 2).use { wav ->
                wav.write(shortArrayOf(1, 2, 3, 4), 4)
                wav.framesWritten
            }
            assertEquals(2L, frames)
            val bytes = file.readBytes()
            assertEquals(2, bytes.short(22))
            assertEquals(44_100 * 4, bytes.int(28))
            assertEquals(4, bytes.short(32))
        } finally {
            file.delete()
        }
    }

    @Test
    fun `an empty file is still a valid one`() {
        val bytes = written(16_000, 1)
        assertEquals(44, bytes.size)
        assertEquals(0, bytes.int(40))
    }
}
