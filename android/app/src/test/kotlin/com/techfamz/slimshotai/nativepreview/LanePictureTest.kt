package com.techfamz.slimshotai.nativepreview

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Whether a lane keeps its picture when its media is replaced.
 *
 * Device-reported: tapping a speed curve preset (Montage, Hero, Bullet) flashed
 * the canvas to the background. A curve changes the clip's length, so the
 * engine rebuilds its lanes, and loading the new media dropped the lane's
 * picture before the re-prepared decoder had a frame to replace it with.
 */
class LanePictureTest {

    private val none = LanePicture.NONE

    @Test
    fun `the lane on screen keeps its picture through a rebuild`() {
        assertTrue(LanePicture.keepsPicture(lane = 0, shownBeforeRebuild = 0, shownAfter = 0))
        assertTrue(LanePicture.keepsPicture(lane = 1, shownBeforeRebuild = 1, shownAfter = 1))
    }

    @Test
    fun `outside a rebuild every load drops the picture`() {
        // A lane crossing a gap or prerolling for a transition: its texture
        // holds another clip's last frame, which must never be blended in.
        assertFalse(LanePicture.keepsPicture(lane = 0, shownBeforeRebuild = none, shownAfter = 0))
        assertFalse(LanePicture.keepsPicture(lane = 1, shownBeforeRebuild = none, shownAfter = 0))
    }

    @Test
    fun `a lane prepared off screen drops its picture`() {
        // The incoming lane of a transition, or the prewarmed second lane.
        assertFalse(LanePicture.keepsPicture(lane = 1, shownBeforeRebuild = 0, shownAfter = 0))
    }

    @Test
    fun `a lane the edit takes off screen drops its picture`() {
        // It was showing, but after the edit it is a transition's incoming lane:
        // its old picture is another clip's, and holding it would blend it in.
        assertFalse(LanePicture.keepsPicture(lane = 0, shownBeforeRebuild = 0, shownAfter = 1))
    }

    @Test
    fun `a lane newly on screen drops its picture`() {
        // Its texture holds whatever it last decoded, not what the user saw.
        assertFalse(LanePicture.keepsPicture(lane = 1, shownBeforeRebuild = 0, shownAfter = 1))
    }

    @Test
    fun `nothing on screen keeps nothing`() {
        // The tail, or the first timeline: no lane was showing.
        assertFalse(LanePicture.keepsPicture(lane = none, shownBeforeRebuild = none, shownAfter = none))
    }
}
