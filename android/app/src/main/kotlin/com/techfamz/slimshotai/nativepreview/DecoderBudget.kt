package com.techfamz.slimshotai.nativepreview

import kotlin.math.floor

/**
 * How many video-overlay decoders the preview may hold open at once, derived
 * from what the device's AVC decoder reports rather than from a constant.
 *
 * **Why a constant was wrong.** The cap was 2, chosen for the export and never
 * compared against any device. Measured on the Infinix (Unisoc, Android 12):
 * `max-concurrent-instances 10` and `blocks-per-second 864000`, which is about
 * **105 fps of 1080p shared across every decoder instance**. So instances were
 * never the scarce resource — throughput is — and a flat 2 is both too many on
 * that device with a transition open (two lanes at 30 plus two overlays at 30
 * is 120) and too few on a phone that could run six. A device declaring
 * more than the decoder commits to is what invites the system's resource
 * manager to reclaim a codec, and it may take a **lane's**, not an overlay's:
 * declining an overlay up front is what protects the main video.
 *
 * **The arithmetic is the cheap version on purpose.** Every stream — a clip
 * lane or an overlay — is costed as a reference 1080p at [REFERENCE_FPS],
 * rather than probing each file's real size and rate. A 720p overlay therefore
 * counts as more than it is, which errs toward fewer overlays on strong devices
 * and never toward a reclaim. Per-stream accounting is the expensive half and
 * is deliberately not here.
 *
 * **No headroom is held back, and that is a measured choice, not an oversight.**
 * The Infinix plays one lane plus two overlays — 90 of its ~105 — for minutes
 * without a reclaim, and a 15% margin would have cut that to one overlay: a
 * regression dressed as caution. The vendor's figure is treated as what it
 * commits to. Revisit with evidence, not instinct.
 *
 * Pure, so it can be pinned by [DecoderBudgetTest]; the device facts arrive
 * from [DeviceDecoderFacts], which is the only Android-dependent part.
 */
internal object DecoderBudget {

    /**
     * What the AVC decoder reports. Null where it would not say — the API
     * throws for an unsupported size, and a codec can refuse to describe
     * itself — and each half is used independently, so a partial report still
     * narrows the answer.
     */
    data class Device(
        /**
         * Frames per second sustained at the reference size, **all instances
         * combined**: `VideoCapabilities.getSupportedFrameRatesFor(1920,
         * 1080).upper`, which the platform derives from the codec's
         * blocks-per-second.
         */
        val referenceFps: Double?,
        /** `CodecCapabilities.maxSupportedInstances`. */
        val maxInstances: Int?,
    )

    /**
     * Overlay decoders the preview may open with [lanes] clip lanes already
     * decoding.
     *
     * The tighter of the throughput and instance limits, floored at
     * [FLOOR] and capped at [PREVIEW_CEILING]. With nothing usable reported
     * it returns [LEGACY_CAP], the constant that has shipped on every device
     * so far — a fallback that is honest about being one.
     */
    fun previewOverlayCapacity(device: Device, lanes: Int): Int {
        val laneCount = lanes.coerceAtLeast(1)

        val byThroughput = device.referenceFps
            ?.takeIf { it.isFinite() && it > 0.0 }
            ?.let { fps -> floor((fps - laneCount * REFERENCE_FPS) / REFERENCE_FPS).toInt() }

        val byInstances = device.maxInstances
            ?.takeIf { it > 0 }
            ?.let { it - laneCount }

        val limits = listOfNotNull(byThroughput, byInstances)
        if (limits.isEmpty()) return LEGACY_CAP

        return limits.min().coerceIn(FLOOR, PREVIEW_CEILING)
    }

    /**
     * How many clip lanes decode at once. Lane 1 exists only when the timeline
     * has a transition, so a project of plain cuts decodes on one lane and has
     * that budget back for overlays.
     */
    fun lanesFor(hasTransitions: Boolean): Int = if (hasTransitions) 2 else 1

    /** The cost of one stream: a reference 1080p clip at this rate. */
    const val REFERENCE_FPS = 30.0

    /**
     * Never zero. Zero would silently remove video overlays as a feature on a
     * device; one lets the existing path try, and warn if the codec is taken.
     */
    const val FLOOR = 1

    /**
     * A memory bound, not a throughput one. Each overlay decoder holds five to
     * eight 1080p output buffers — six of them is already around 200MB — so a
     * device declaring absurd throughput stops here however fast it says it is.
     */
    const val PREVIEW_CEILING = 6

    /** What shipped before the budget existed; the answer when nothing is known. */
    const val LEGACY_CAP = 2
}
