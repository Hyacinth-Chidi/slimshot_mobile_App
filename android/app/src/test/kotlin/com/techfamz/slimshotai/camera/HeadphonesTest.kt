package com.techfamz.slimshotai.camera

import android.media.AudioDeviceInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HeadphonesTest {
    @Test
    fun theEarIsPrivateTheRoomIsNot() {
        assertTrue(Headphones.isPrivate(AudioDeviceInfo.TYPE_WIRED_HEADPHONES))
        assertTrue(Headphones.isPrivate(AudioDeviceInfo.TYPE_WIRED_HEADSET))
        assertTrue(Headphones.isPrivate(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP))
        assertTrue(Headphones.isPrivate(AudioDeviceInfo.TYPE_USB_HEADSET))
        assertTrue(Headphones.isPrivate(26))
        assertFalse(Headphones.isPrivate(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER))
        assertFalse(Headphones.isPrivate(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE))
        assertFalse(Headphones.isPrivate(AudioDeviceInfo.TYPE_HDMI))
    }
}
