package com.techfamz.slimshotai.camera.react

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import com.techfamz.slimshotai.export.ExportCapabilities

/**
 * What the phone's video encoder says it can do, for REACT to choose how to
 * record (Dart's `chooseReactCapture`): the frames a second it achieves at
 * 1080x1920 and at 720x1280 — the codec's own measured figure where it
 * publishes one, else what it supports — and 0 where it cannot take the size
 * at all. Asked once; never a test run.
 */
internal object ReactCapabilityProbe {

    fun facts(): Map<String, Any> {
        val capabilities = avcEncoder()
        val (fps1080, size1080) = rate(capabilities, 1080, 1920)
        val (fps720, size720) = rate(capabilities, 720, 1280)
        val facts = mapOf(
            "fps1080" to fps1080,
            "fps720" to fps720,
            "size1080" to size1080,
            "size720" to size720,
        )
        Log.i(TAG, "REACT live facts: $facts")
        return facts
    }

    private fun rate(capabilities: MediaCodecInfo.VideoCapabilities?, width: Int, height: Int): Pair<Double, List<Int>> {
        val (w, h) = ExportCapabilities.alignedEncoderSize(width, height)
        val size = listOf(w, h)
        // A size the encoder only takes shrunk is not that size.
        if (capabilities == null || w < width * 9 / 10 || h < height * 9 / 10) return 0.0 to size
        val achievable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                capabilities.getAchievableFrameRatesFor(w, h)?.upper
            } catch (_: Exception) {
                null
            }
        } else {
            null
        }
        val supported = try {
            capabilities.getSupportedFrameRatesFor(w, h).upper
        } catch (_: Exception) {
            null
        }
        return (achievable ?: supported ?: 0.0) to size
    }

    /** The AVC encoder `MediaCodec.createEncoderByType` would pick: the first listed. */
    private fun avcEncoder(): MediaCodecInfo.VideoCapabilities? = try {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .firstOrNull { info ->
                info.isEncoder && info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_AVC, ignoreCase = true) }
            }
            ?.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
            ?.videoCapabilities
    } catch (error: Exception) {
        Log.w(TAG, "the encoder would not describe itself", error)
        null
    }

    private const val TAG = "SlimshotCamera"
}
