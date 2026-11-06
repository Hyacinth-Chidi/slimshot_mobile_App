package com.techfamz.slimshotai.camera

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager

/**
 * Whether the phone's sound goes somewhere the microphone cannot hear it.
 *
 * REACT plays the video while the camera records: out of the speaker, the
 * microphone takes the video's sound in along with the voice, so the reaction
 * keeps the video's own sound off rather than hear it twice. Into headphones
 * the microphone hears only the voice, and the video's clean sound is kept.
 *
 * A Bluetooth speaker is reported as A2DP like earbuds are, and nothing here
 * can tell them apart without a Bluetooth permission; it counts as
 * headphones, as most phones' Bluetooth audio is.
 */
internal object Headphones {
    /** Output kinds held to the ear, not the room. */
    private val PRIVATE_OUTPUTS = setOf(
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        // Hearing aids (API 28) and LE audio headsets (API 31): constants, so
        // naming them on an older phone costs nothing; it never reports them.
        23, // AudioDeviceInfo.TYPE_HEARING_AID
        26, // AudioDeviceInfo.TYPE_BLE_HEADSET
    )

    fun isPrivate(type: Int): Boolean = type in PRIVATE_OUTPUTS

    fun connected(context: Context): Boolean {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        return try {
            audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { isPrivate(it.type) }
        } catch (_: Exception) {
            false
        }
    }
}
