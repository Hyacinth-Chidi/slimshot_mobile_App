package com.techfamz.slimshotai.nativepreview.gl

import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay

/**
 * Which still textures the preview frees, and which texts it loads ahead.
 *
 * Pure decisions, kept apart from the renderer so they can be tested: the
 * renderer itself only runs on a device.
 *
 * The preview used to keep every still it ever uploaded, which was fine while
 * stills were the photo overlays a user added by hand. Text is different:
 * the editor sends only the texts near the playhead, an atlas per look, so
 * the list's paths change as the playhead moves and as a caption is
 * restyled — and a texture kept for every path ever sent is GPU memory that
 * grows with every caption played.
 */
internal object StillResidency {

    /**
     * Photo and text overlays of [previous] whose path [next] no longer
     * names, one per path — the textures to free. Video overlays are not
     * stills: their decoders follow their own list (`updateOverlays`).
     */
    fun released(
        previous: List<NativeTimelineOverlay>,
        next: List<NativeTimelineOverlay>,
    ): List<NativeTimelineOverlay> {
        val kept = next.mapTo(HashSet()) { it.path }
        val seen = HashSet<String>()
        return previous.filter { !it.isVideo && it.path !in kept && seen.add(it.path) }
    }

    /**
     * The text overlays in the order to load them ahead of time: those live
     * at [t] first, then by start.
     *
     * Live first because a text being edited is sent at no opacity: it is on
     * screen, but the draw skips it before it uploads, so only the preload
     * ever loads it — and it is the one the user is looking at.
     */
    fun preloadOrder(overlays: List<NativeTimelineOverlay>, t: Double): List<NativeTimelineOverlay> {
        val texts = overlays.filter { it.isText }
        val (live, rest) = texts.partition { it.contains(t) }
        return live.sortedBy { it.startSeconds } + rest.sortedBy { it.startSeconds }
    }

    /** Every text overlay in [list] — what an export's texture purge takes from the preview. */
    fun textsIn(list: List<NativeTimelineOverlay>): List<NativeTimelineOverlay> =
        list.filter { it.isText }
}
