package com.techfamz.slimshotai.homewidget

import org.junit.Assert.assertArrayEquals
import org.junit.Test

/**
 * The widget's cover is the draft's, cut to 9:16 about its middle and kept
 * small: a large bitmap breaks a widget's memory limit.
 */
class CoverCropTest {

    @Test
    fun `a cover is cut to 9 by 16 about its middle`() {
        assertArrayEquals(intArrayOf(0, 0, 1080, 1920), CoverCrop.centre(1080, 1920))
        assertArrayEquals(intArrayOf(656, 0, 608, 1080), CoverCrop.centre(1920, 1080))
        assertArrayEquals(intArrayOf(218, 0, 563, 1000), CoverCrop.centre(1000, 1000))
        assertArrayEquals(intArrayOf(0, 555, 500, 889), CoverCrop.centre(500, 2000))
    }

    @Test
    fun `it is scaled down to the widget's size and never up`() {
        assertArrayEquals(intArrayOf(180, 320), CoverCrop.output(1080, 1920))
        assertArrayEquals(intArrayOf(90, 160), CoverCrop.output(90, 160))
    }
}
