package com.techfamz.slimshotai.nativepreview

import android.media.MediaCodecList
import android.media.MediaFormat
import android.util.Log

/**
 * What this device's AVC decoder says about itself, read once and logged once.
 *
 * The Android-dependent half of [DecoderBudget]: everything here comes from
 * `MediaCodecList`, and the arithmetic that turns it into a cap lives in the
 * pure object so it can be tested without a device.
 *
 * `getSupportedFrameRatesFor(w, h)` is the portable route to throughput. The
 * platform derives it from the codec's `blocks-per-second`, dividing by the
 * macroblocks in the requested size, and it **throws** for a size the codec
 * cannot decode at all — which is itself a fact worth having (the Infinix
 * reports `size-range 64x64-1920x3840`, so it cannot open 4K).
 *
 * Logged under `SlimshotExport`, the tag CLAUDE.md says to filter on for
 * capability diagnostics, so the next device report arrives with these
 * numbers rather than guesses. The `lazy` is the "once".
 */
internal object DeviceDecoderFacts {

    private const val TAG = "SlimshotExport"
    private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC

    val avc: DecoderBudget.Device by lazy { read() }

    private fun read(): DecoderBudget.Device {
        val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        val info = codecs.codecInfos.firstOrNull { candidate ->
            !candidate.isEncoder &&
                candidate.supportedTypes.any { it.equals(MIME, ignoreCase = true) }
        }
        if (info == null) {
            Log.w(TAG, "decoder facts: no AVC decoder on this device")
            return DecoderBudget.Device(referenceFps = null, maxInstances = null)
        }

        return try {
            val caps = info.getCapabilitiesForType(MIME)
            val video = caps.videoCapabilities
            val instances = caps.maxSupportedInstances.takeIf { it > 0 }

            val fps1080 = fpsAt(video, 1920, 1080)
            val fps720 = fpsAt(video, 1280, 720)
            val widths = video.supportedWidths
            val heights = video.supportedHeights

            val device = DecoderBudget.Device(referenceFps = fps1080, maxInstances = instances)
            Log.i(
                TAG,
                "decoder facts: ${info.name} instances=${instances ?: "?"} " +
                    "fps@1080p=${fps1080?.let { "%.1f".format(it) } ?: "unsupported"} " +
                    "fps@720p=${fps720?.let { "%.1f".format(it) } ?: "unsupported"} " +
                    "size=${widths.lower}x${heights.lower}-${widths.upper}x${heights.upper} " +
                    "-> overlays: ${DecoderBudget.previewOverlayCapacity(device, lanes = 1)} on one lane, " +
                    "${DecoderBudget.previewOverlayCapacity(device, lanes = 2)} through a transition",
            )
            device
        } catch (error: Exception) {
            // A codec that refuses to describe itself is a fact too: the budget
            // falls back to what always shipped rather than guessing.
            Log.w(TAG, "decoder facts: ${info.name} refused to describe itself", error)
            DecoderBudget.Device(referenceFps = null, maxInstances = null)
        }
    }

    /** Upper sustained frame rate at a size, or null where the codec cannot decode it. */
    private fun fpsAt(
        video: android.media.MediaCodecInfo.VideoCapabilities,
        width: Int,
        height: Int,
    ): Double? = try {
        video.getSupportedFrameRatesFor(width, height).upper
    } catch (_: IllegalArgumentException) {
        null
    }
}
