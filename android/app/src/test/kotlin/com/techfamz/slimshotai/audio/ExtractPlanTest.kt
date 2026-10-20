package com.techfamz.slimshotai.audio

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which sound is copied as it is and which is converted. */
class ExtractPlanTest {

    @Test
    fun `AAC remuxes`() {
        assertTrue(ExtractPlan.canRemux("audio/mp4a-latm"))
    }

    @Test
    fun `transcodes when the codec cannot be remuxed`() {
        for (mime in listOf("audio/3gpp", "audio/opus", "audio/raw", "audio/mpeg", "audio/amr-wb")) {
            assertFalse(mime, ExtractPlan.canRemux(mime))
        }
    }
}
