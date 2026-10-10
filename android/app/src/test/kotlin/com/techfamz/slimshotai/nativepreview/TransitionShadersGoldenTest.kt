package com.techfamz.slimshotai.nativepreview

import com.techfamz.slimshotai.nativepreview.gl.TransitionShaders
import org.junit.Assert.assertEquals
import org.junit.Test
import java.security.MessageDigest

/**
 * The transitions that shipped before layered transitions, pinned byte for byte.
 *
 * Layered transitions (the GL Transitions ports) were added beside these, not
 * in place of them, so the eleven device-verified transitions could not change.
 * This is what holds that promise: every fragment source they compile —
 * each type in each of the four sampler pairings, and both passthroughs — is
 * hashed, and the hash was taken before any layered code existed.
 *
 * A deliberate change to one of them is a change to a device-verified
 * picture: update the hash in the same commit and say why.
 */
class TransitionShadersGoldenTest {

    private val shipped = listOf(
        "dissolve", "fadeToBlack", "fadeToWhite", "slide", "push", "wipe",
        "smoothLeft", "smoothRight", "smoothUp", "smoothDown", "zoomIn",
    )

    private fun allSources(): String = buildString {
        for (type in shipped) {
            for (incoming in listOf(false, true)) {
                for (outgoing in listOf(false, true)) {
                    append(TransitionShaders.fragmentShaderFor(type, incoming, outgoing))
                    append('\u0000')
                }
            }
        }
        append(TransitionShaders.passthroughFragment(false))
        append('\u0000')
        append(TransitionShaders.passthroughFragment(true))
        append('\u0000')
        append(TransitionShaders.VERTEX_SHADER)
    }

    private fun sha256(text: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(text.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    @Test
    fun `the shipped transitions compile exactly the sources they always did`() {
        assertEquals(SHIPPED_SOURCES_SHA256, sha256(allSources()))
    }

    private companion object {
        const val SHIPPED_SOURCES_SHA256 =
            "1a8863c12685f4cc0203572451eea811c8201da70a79184e1ca8781f10a9e4be"
    }
}
