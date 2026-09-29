package com.techfamz.slimshotai.nativepreview.gl

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Which uploaded stills an export may free. A caption set is a hundred text
 * atlases; kept to the end of the export they were all on the GPU at once.
 */
class ExpiredStillsTest {

    private val caption1 = ExpiredStills.Span("/atlas1.png", endSeconds = 2.0)
    private val caption2 = ExpiredStills.Span("/atlas2.png", endSeconds = 4.0)

    @Test
    fun `nothing is freed while its overlay still shows`() {
        assertEquals(emptySet<String>(), ExpiredStills.releasable(listOf(caption1, caption2), 1.9))
    }

    @Test
    fun `a still is freed from its overlay's end`() {
        assertEquals(setOf("/atlas1.png"), ExpiredStills.releasable(listOf(caption1, caption2), 2.0))
        assertEquals(
            setOf("/atlas1.png", "/atlas2.png"),
            ExpiredStills.releasable(listOf(caption1, caption2), 9.0),
        )
    }

    @Test
    fun `a photo placed twice is kept until its last use ends`() {
        val early = ExpiredStills.Span("/photo.jpg", endSeconds = 2.0)
        val late = ExpiredStills.Span("/photo.jpg", endSeconds = 6.0)
        assertEquals(emptySet<String>(), ExpiredStills.releasable(listOf(early, late), 3.0))
        assertEquals(setOf("/photo.jpg"), ExpiredStills.releasable(listOf(early, late), 6.0))
    }
}
