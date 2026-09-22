package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * How many video-overlay decoders the preview may open at once.
 *
 * The cap used to be a constant, 2, chosen for the export and never compared
 * against any device. Measured on the Infinix (Unisoc, Android 12) the AVC
 * decoder reports `blocks-per-second 864000` — about **105 fps of 1080p shared
 * across every decoder instance** — and `max-concurrent-instances 10`. So
 * instances were never the scarce resource; throughput is, and a flat 2 is
 * both too many on that device with a transition open and too few on a phone
 * that could run six.
 *
 * The arithmetic is deliberately the cheap version: every stream — a clip lane
 * or an overlay — is costed as a **reference 1080p30**, rather than probing
 * each file's real size and rate. A 720p overlay therefore counts as more than
 * it is, which errs toward fewer overlays on strong devices and never toward a
 * reclaim. Per-stream accounting is the expensive half and is not here.
 *
 * The device numbers are the Infinix's own where a test says so, because that
 * is the one device with a measured result to agree with: one lane plus two
 * overlays plays for minutes without a reclaim.
 */
class DecoderBudgetTest {

    /** `864000 / 8160` — the Infinix's declared throughput at 1080p. */
    private val infinix = DecoderBudget.Device(referenceFps = 864000.0 / 8160.0, maxInstances = 10)

    @Test
    fun `the Infinix with no transition gets the two overlays it is known to play`() {
        // One lane decoding (no transition, so lane 1 does not exist) costs 30
        // of ~105; two overlays cost 60 more; 90 fits. The device *does* play
        // this — it is the project the crash was reproduced on and then
        // verified fixed on — so anything less would be a regression dressed
        // as caution.
        assertEquals(2, DecoderBudget.previewOverlayCapacity(infinix, lanes = 1))
    }

    @Test
    fun `the Infinix with a transition open gets one`() {
        // Two lanes decode through a transition window, 60 of ~105. A second
        // overlay would take the total to 120 — past what the decoder commits
        // to, which is the state that invites the system to reclaim a codec.
        // A reclaim can take a *lane's* codec, not just an overlay's, so
        // declining the overlay up front protects the main video.
        assertEquals(1, DecoderBudget.previewOverlayCapacity(infinix, lanes = 2))
    }

    @Test
    fun `a strong device gets more than the old constant allowed`() {
        // The point of deriving it: the flat 2 was every device limited to what
        // the weakest could do.
        val strong = DecoderBudget.Device(referenceFps = 400.0, maxInstances = 16)
        val cap = DecoderBudget.previewOverlayCapacity(strong, lanes = 2)
        assert(cap > 2) { "expected more than the legacy 2, got $cap" }
    }

    @Test
    fun `the ceiling is memory, not throughput`() {
        // A device declaring absurd throughput still holds a decoder's output
        // buffers per overlay — five to eight 1080p frames each. Six live
        // overlay decoders is already ~200MB of that; the cap stops there
        // however fast the chip says it is.
        val absurd = DecoderBudget.Device(referenceFps = 10_000.0, maxInstances = 64)
        assertEquals(DecoderBudget.PREVIEW_CEILING, DecoderBudget.previewOverlayCapacity(absurd, lanes = 1))
    }

    @Test
    fun `instances bind when they are the tighter limit`() {
        // Plenty of throughput, but the decoder admits only three instances and
        // two lanes hold two of them.
        val fewInstances = DecoderBudget.Device(referenceFps = 400.0, maxInstances = 3)
        assertEquals(1, DecoderBudget.previewOverlayCapacity(fewInstances, lanes = 2))
    }

    @Test
    fun `the floor is one, never zero`() {
        // A device too slow for even one overlay on paper still gets one: zero
        // would silently remove video overlays as a feature, where one lets the
        // existing path try and warn if the codec is taken away.
        val slow = DecoderBudget.Device(referenceFps = 40.0, maxInstances = 4)
        assertEquals(1, DecoderBudget.previewOverlayCapacity(slow, lanes = 2))
    }

    @Test
    fun `a device that will not say gets what always shipped`() {
        // Probe at runtime and degrade loudly — but where the device reports
        // nothing usable, the honest fallback is the constant that has shipped
        // on every device so far, not a guess dressed as a measurement.
        val unknown = DecoderBudget.Device(referenceFps = null, maxInstances = null)
        assertEquals(DecoderBudget.LEGACY_CAP, DecoderBudget.previewOverlayCapacity(unknown, lanes = 2))

        val junk = DecoderBudget.Device(referenceFps = Double.NaN, maxInstances = 0)
        assertEquals(DecoderBudget.LEGACY_CAP, DecoderBudget.previewOverlayCapacity(junk, lanes = 1))
    }

    @Test
    fun `a partial report still uses the half it has`() {
        // Throughput known, instances not: throughput alone decides.
        val fpsOnly = DecoderBudget.Device(referenceFps = 864000.0 / 8160.0, maxInstances = null)
        assertEquals(2, DecoderBudget.previewOverlayCapacity(fpsOnly, lanes = 1))

        // Instances known, throughput not: instances alone decide.
        val instancesOnly = DecoderBudget.Device(referenceFps = null, maxInstances = 3)
        assertEquals(1, DecoderBudget.previewOverlayCapacity(instancesOnly, lanes = 2))
    }

    @Test
    fun `lanes are counted from whether a transition exists`() {
        // Lane 1 is only created when the timeline has a transition, so a
        // project of plain cuts decodes on one lane and has that budget back.
        assertEquals(1, DecoderBudget.lanesFor(hasTransitions = false))
        assertEquals(2, DecoderBudget.lanesFor(hasTransitions = true))
    }
}
