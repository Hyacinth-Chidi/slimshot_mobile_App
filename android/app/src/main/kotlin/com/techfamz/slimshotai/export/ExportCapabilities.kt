package com.techfamz.slimshotai.export

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.util.Log

/**
 * What this device's hardware codecs will actually agree to do.
 *
 * Export composites two decoded streams and encodes the result, so at its peak
 * it holds **two decoders and one encoder at once**. Whether that is allowed
 * varies across a decade of hardware — `minSdk` is 24 — so nothing here is
 * decided in advance from any one device.
 *
 * The rule this file exists to enforce: **never assume a capability, query it;
 * and where the device says no, degrade loudly rather than silently.** An
 * export that quietly drops a transition is worse than one that says it had to,
 * because the file then differs from the preview with nothing explaining why.
 *
 * [probe] is a diagnostic — it reports what a given device does, for logs and
 * bug reports. It is deliberately **not** a gate: the pipeline is built for the
 * two-decoder case everywhere and falls back at runtime if a device refuses,
 * the same way the preview engine already falls back to a hard cut when its
 * second lane will not come up.
 */
internal object ExportCapabilities {

    private const val TAG = "SlimshotExport"
    private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC

    /** Encoder dimensions must usually be multiples of this. */
    private const val FALLBACK_ALIGNMENT = 16

    data class EncoderSupport(
        val codecName: String?,
        val maxInstances: Int,
        val widthAlignment: Int,
        val heightAlignment: Int,
        val supportedWidths: IntRange?,
        val supportedHeights: IntRange?,
    ) {
        val isUsable: Boolean get() = codecName != null
    }

    /**
     * Size the encoder will accept for a canvas of [width] x [height].
     *
     * **The frame's shape is preserved.** Encoder capability ranges are
     * per-axis — a device commonly reports widths up to 1920 and heights up to
     * 1080 — and clamping each axis on its own turned a portrait 1080x1920
     * request into a 1080x1080 square. The shader then letterboxed clips
     * against the 9:16 aspect it had been told about inside a square viewport,
     * so every clip shrank and the exported file was a different shape than the
     * preview. When the requested size does not fit, the whole frame is scaled
     * down uniformly until it does.
     *
     * Always down to a multiple of the encoder's alignment, never up: growing
     * the frame would letterbox differently than the preview did.
     */
    fun alignedEncoderSize(width: Int, height: Int): Pair<Int, Int> {
        val support = describeEncoder()
        val widthStep = support.widthAlignment.coerceAtLeast(2)
        val heightStep = support.heightAlignment.coerceAtLeast(2)

        // One uniform scale that brings both axes inside their ranges.
        var scale = 1.0
        support.supportedWidths?.let {
            if (width > it.last) scale = minOf(scale, it.last.toDouble() / width)
        }
        support.supportedHeights?.let {
            if (height > it.last) scale = minOf(scale, it.last.toDouble() / height)
        }
        if (scale < 1.0) {
            Log.w(
                TAG,
                "Encoder range forces ${width}x$height down by ${"%.3f".format(scale)}",
            )
        }

        var alignedWidth = ((width * scale).toInt() / widthStep) * widthStep
        var alignedHeight = ((height * scale).toInt() / heightStep) * heightStep

        // Range minimums are tiny (usually 2..176) and cannot practically
        // conflict with a canvas; applied last so they never fight the scale.
        support.supportedWidths?.let {
            alignedWidth = alignedWidth.coerceAtLeast(it.first)
        }
        support.supportedHeights?.let {
            alignedHeight = alignedHeight.coerceAtLeast(it.first)
        }

        return Pair(
            alignedWidth.coerceAtLeast(widthStep),
            alignedHeight.coerceAtLeast(heightStep),
        )
    }

    fun describeEncoder(): EncoderSupport {
        val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        for (info in codecs.codecInfos) {
            if (!info.isEncoder) continue
            if (info.supportedTypes.none { it.equals(MIME, ignoreCase = true) }) continue

            return try {
                val video = info.getCapabilitiesForType(MIME).videoCapabilities
                EncoderSupport(
                    codecName = info.name,
                    maxInstances = info.getCapabilitiesForType(MIME)
                        .maxSupportedInstances,
                    widthAlignment = video.widthAlignment,
                    heightAlignment = video.heightAlignment,
                    supportedWidths = video.supportedWidths.lower..video.supportedWidths.upper,
                    supportedHeights =
                        video.supportedHeights.lower..video.supportedHeights.upper,
                )
            } catch (error: Exception) {
                Log.w(TAG, "Encoder ${info.name} refused to describe itself", error)
                EncoderSupport(
                    codecName = info.name,
                    maxInstances = 1,
                    widthAlignment = FALLBACK_ALIGNMENT,
                    heightAlignment = FALLBACK_ALIGNMENT,
                    supportedWidths = null,
                    supportedHeights = null,
                )
            }
        }

        return EncoderSupport(null, 0, FALLBACK_ALIGNMENT, FALLBACK_ALIGNMENT, null, null)
    }

    /**
     * Whether this device can decode [mimeType] at all.
     *
     * Imported media is the one genuinely arbitrary input in the pipeline: a
     * user's file may be HEVC, VP9 or AV1, and support for those varies far
     * more than it does for AVC. Checked before an export starts so an
     * unsupported clip is reported by name rather than exporting as a black
     * stretch nobody can explain.
     */
    fun canDecode(mimeType: String?): Boolean {
        if (mimeType.isNullOrBlank()) return false
        val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        return codecs.codecInfos.any { info ->
            !info.isEncoder &&
                info.supportedTypes.any { it.equals(mimeType, ignoreCase = true) }
        }
    }

    /**
     * How many decoders this device admits to running at once.
     *
     * Advisory only — the vendor's claim, not a guarantee. The pipeline still
     * tries and handles refusal, because these numbers are routinely optimistic
     * and say nothing about what other apps already hold.
     */
    fun maxConcurrentDecoders(): Int = decoderMaxInstances()

    private fun decoderMaxInstances(): Int {
        val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        for (info in codecs.codecInfos) {
            if (info.isEncoder) continue
            if (info.supportedTypes.none { it.equals(MIME, ignoreCase = true) }) continue
            return try {
                info.getCapabilitiesForType(MIME).maxSupportedInstances
            } catch (_: Exception) {
                1
            }
        }
        return 0
    }

    /**
     * Reports what the device will do, and actually starts an encoder to prove
     * it rather than trusting the advertised numbers.
     *
     * Advertised instance counts are a vendor claim; whether an encoder will
     * start *while playback already holds two decoders* is a different
     * question, and it is the one that decides whether export can render
     * straight through or has to bring the second decoder up only across a
     * transition window. Run it with the editor open and the preview loaded.
     */
    fun probe(canvasWidth: Int, canvasHeight: Int): Map<String, Any?> {
        val support = describeEncoder()
        val (width, height) = alignedEncoderSize(canvasWidth, canvasHeight)
        val decoderInstances = decoderMaxInstances()

        var encoderStarted = false
        var failure: String? = null

        if (support.isUsable) {
            var codec: MediaCodec? = null
            try {
                val format = MediaFormat.createVideoFormat(MIME, width, height).apply {
                    setInteger(
                        MediaFormat.KEY_COLOR_FORMAT,
                        MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
                    )
                    setInteger(
                        MediaFormat.KEY_BIT_RATE,
                        VideoFrameEncoder.bitRateFor(width, height, 30),
                    )
                    setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                }
                codec = MediaCodec.createEncoderByType(MIME)
                codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                val surface = codec.createInputSurface()
                codec.start()
                encoderStarted = true
                surface.release()
            } catch (error: Exception) {
                failure = error.message ?: error.javaClass.simpleName
            } finally {
                try {
                    codec?.stop()
                } catch (_: Exception) {
                    // Already failed; nothing useful to do.
                }
                codec?.release()
            }
        }

        val result = mapOf(
            "encoder" to support.codecName,
            "encoderMaxInstances" to support.maxInstances,
            "decoderMaxInstances" to decoderInstances,
            "requestedSize" to "${canvasWidth}x$canvasHeight",
            "encoderSize" to "${width}x$height",
            "alignment" to "${support.widthAlignment}x${support.heightAlignment}",
            "encoderStartedAlongsidePlayback" to encoderStarted,
            "failure" to failure,
        )
        Log.i(TAG, "export capability probe: $result")
        return result
    }
}
