package com.techfamz.slimshotai.thumbnails

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.DataFormatException
import java.util.zip.Inflater

/**
 * A text atlas as Flutter writes it (`raw_atlas_file.dart`): `SSRZ`, width and
 * height as little-endian 32-bit integers, then premultiplied RGBA rows
 * deflated as one zlib stream.
 *
 * It replaced a PNG, whose encoding was most of the wait before a captioned
 * export began. The pixels are premultiplied exactly as an ARGB_8888
 * [android.graphics.Bitmap] keeps them, so they are copied in as they are —
 * no round trip through straight alpha, which a PNG makes. Both sides are
 * tested against `raw_atlas_fixture.rgbz`; if one changes the other must.
 */
internal object RawAtlasFile {

    class Pixels(val width: Int, val height: Int, val rgba: ByteArray)

    private val MAGIC = byteArrayOf(0x53, 0x53, 0x52, 0x5A)
    private const val HEADER_BYTES = 12

    /** Whether [bytes] begin as an atlas file does. */
    fun isRawAtlas(bytes: ByteArray): Boolean =
        bytes.size >= MAGIC.size && MAGIC.indices.all { bytes[it] == MAGIC[it] }

    /** Whether the file at [path] is an atlas, from its first bytes alone. */
    fun isRawAtlas(path: String): Boolean = header(path)?.let { isRawAtlas(it) } ?: false

    /** Width and height from an atlas file's header, or null. */
    fun size(bytes: ByteArray): Pair<Int, Int>? {
        if (bytes.size < HEADER_BYTES || !isRawAtlas(bytes)) return null
        val header = ByteBuffer.wrap(bytes, 0, HEADER_BYTES).order(ByteOrder.LITTLE_ENDIAN)
        val width = header.getInt(4)
        val height = header.getInt(8)
        return if (width > 0 && height > 0) Pair(width, height) else null
    }

    fun size(path: String): Pair<Int, Int>? = header(path)?.let { size(it) }

    /**
     * The pixels in [bytes], or null for anything that is not one whole atlas:
     * another format, a short header, a stream that ends short of the size or
     * runs past it, or one zlib refuses.
     */
    fun decode(bytes: ByteArray): Pixels? {
        val (width, height) = size(bytes) ?: return null
        val length = width.toLong() * height * 4
        if (length > Int.MAX_VALUE) return null
        val rgba = ByteArray(length.toInt())
        val inflater = Inflater()
        return try {
            inflater.setInput(bytes, HEADER_BYTES, bytes.size - HEADER_BYTES)
            var filled = 0
            while (!inflater.finished()) {
                val read = inflater.inflate(rgba, filled, rgba.size - filled)
                if (read == 0 &&
                    (inflater.needsInput() || inflater.needsDictionary() || filled == rgba.size)
                ) {
                    break
                }
                filled += read
            }
            if (filled == rgba.size && inflater.finished()) Pixels(width, height, rgba) else null
        } catch (_: DataFormatException) {
            null
        } finally {
            inflater.end()
        }
    }

    fun read(path: String): Pixels? = try {
        decode(File(path).readBytes())
    } catch (_: Exception) {
        null
    }

    private fun header(path: String): ByteArray? = try {
        RandomAccessFile(path, "r").use { file ->
            val head = ByteArray(HEADER_BYTES)
            if (file.read(head) == HEADER_BYTES) head else null
        }
    } catch (_: Exception) {
        null
    }
}
