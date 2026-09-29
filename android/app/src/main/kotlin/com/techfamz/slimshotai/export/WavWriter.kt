package com.techfamz.slimshotai.export

import java.io.Closeable
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 16-bit PCM in a WAV file: a 44-byte header, then the samples as they are.
 *
 * What the caption audio is written as. There is no codec in it, which is the
 * point: an AAC encoder opens every stream with a run of priming samples, and
 * a transcript made from one places every word that much late. Here the first
 * sample of the file is the first instant of the timeline.
 */
internal class WavWriter(
    file: File,
    private val sampleRate: Int,
    private val channels: Int,
) : Closeable {

    private val out = RandomAccessFile(file, "rw")
    private var dataBytes = 0L
    private var bytes = ByteBuffer.allocate(0).order(ByteOrder.LITTLE_ENDIAN)

    /** Whole frames written so far. */
    val framesWritten: Long get() = dataBytes / (channels * BYTES_PER_SAMPLE)

    init {
        out.setLength(0)
        // The sizes are not known until the last sample; `close` fills them in.
        out.write(header(dataSize = 0))
    }

    /** Appends the first [count] samples of [samples]. */
    fun write(samples: ShortArray, count: Int) {
        val size = count * BYTES_PER_SAMPLE
        if (bytes.capacity() < size) {
            bytes = ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN)
        }
        bytes.clear()
        for (i in 0 until count) bytes.putShort(samples[i])
        out.write(bytes.array(), 0, size)
        dataBytes += size
    }

    override fun close() {
        out.use {
            it.seek(0)
            it.write(header(dataBytes))
        }
    }

    private fun header(dataSize: Long): ByteArray {
        val blockAlign = channels * BYTES_PER_SAMPLE
        return ByteBuffer.allocate(HEADER_BYTES).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray(Charsets.US_ASCII))
            putInt((HEADER_BYTES - 8 + dataSize).toInt())
            put("WAVE".toByteArray(Charsets.US_ASCII))
            put("fmt ".toByteArray(Charsets.US_ASCII))
            putInt(16)
            putShort(PCM_FORMAT)
            putShort(channels.toShort())
            putInt(sampleRate)
            putInt(sampleRate * blockAlign)
            putShort(blockAlign.toShort())
            putShort((BYTES_PER_SAMPLE * 8).toShort())
            put("data".toByteArray(Charsets.US_ASCII))
            putInt(dataSize.toInt())
        }.array()
    }

    private companion object {
        const val HEADER_BYTES = 44
        const val BYTES_PER_SAMPLE = 2
        const val PCM_FORMAT: Short = 1
    }
}
