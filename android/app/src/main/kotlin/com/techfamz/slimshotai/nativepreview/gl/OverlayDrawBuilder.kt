package com.techfamz.slimshotai.nativepreview.gl

import com.techfamz.slimshotai.export.ExportClipDecoder
import com.techfamz.slimshotai.nativepreview.NativeTimelineOverlay
import com.techfamz.slimshotai.nativepreview.OverlayClock
import com.techfamz.slimshotai.nativepreview.TextAnimationCategory
import com.techfamz.slimshotai.nativepreview.TextAnimationCurves
import com.techfamz.slimshotai.nativepreview.TextGlyphState
import com.techfamz.slimshotai.thumbnails.StillImageDecoder

/**
 * Resolves the overlays that are live at an instant into draw calls, owning
 * the still uploads and per-overlay video decoders.
 *
 * The overlays arrive lane-sorted from the composer, and [drawsFor] keeps
 * that order, so stacking in the file matches stacking in the preview.
 *
 * **Lifted out of `VideoExportEngine`, verbatim.** It was that engine's
 * private inner class, which is the one reason the preview could not draw
 * overlays natively: the renderer, the shader and the wire format were all
 * already shared, and only this — the per-frame decision of what is live and
 * how it is animated — was out of the preview's reach. See
 * `docs/superpowers/specs/2026-09-17-native-preview-overlays-design.md`.
 *
 * What it needs from its caller is deliberately small: the renderer, the
 * overlay list, somewhere to report trouble ([Events]), and how long to wait
 * for a video overlay's frame ([frameWaitMs]). The export waits, because it
 * is not realtime and a missing frame is a wrong frame in the file; a realtime
 * caller must not, and passes zero.
 */
internal class OverlayDrawBuilder(
    private val renderer: TransitionRenderer,
    overlays: List<NativeTimelineOverlay>,
    private val events: Events,
    private val frameWaitMs: Long,
    private val stills: StillSource = INLINE_STILLS,
    /**
     * True for the preview, whose clock can stand still, jump, and run
     * backwards; false for the export, whose clock only ever walks forward.
     * It switches on exactly three behaviours, each of which the export must
     * not have: seeking a decoder the playhead has left behind, freeing a
     * decoder when the playhead is *before* its overlay as well as after, and
     * asking for another draw when a frame is still on its way.
     */
    private val realtime: Boolean = false,
) {

    /**
     * Most video-overlay decoders this builder may hold open at once. The
     * export leaves it at [MAX_OVERLAY_DECODERS]; the preview sets it from
     * [com.techfamz.slimshotai.nativepreview.DecoderBudget], which reads what
     * the device's decoder actually commits to. It bounds *opening*: a
     * decoder already live when the cap drops (a transition added while two
     * overlays play) runs on until its overlay expires — evicting one
     * mid-frame would be a picture vanishing for no visible reason.
     * Written by the renderer on the GL thread, read here on the same thread;
     * volatile so a write from a setter elsewhere is never stale.
     */
    @Volatile
    var maxVideoDecoders: Int = MAX_OVERLAY_DECODERS

    /**
     * Where the builder reports what it could not do. Export counts these into
     * its end-of-run warnings; the counters stayed behind because they are the
     * export's bookkeeping, not the builder's.
     */
    interface Events {
        /** An overlay's image, atlas or video could not be opened or decoded. */
        fun onOverlayFailed()

        /** A video overlay was skipped because [maxVideoDecoders] were already live. */
        fun onDecoderSkipped()

        /** A video overlay's frame did not arrive within [frameWaitMs]. */
        fun onLateFrame()

        /**
         * Realtime only: a video overlay's decoder has not reached the frame
         * that is due — it was just seeked, and one draw's worth of decoding
         * did not get there. The preview asks for another draw; the export
         * never sees this, because it waits instead.
         */
        fun onFrameNotReady() {}
    }

    /** What [StillSource] has for a path right now. */
    sealed class Still {
        /** Decoded; the builder uploads it and recycles the bitmap. */
        class Ready(val bitmap: android.graphics.Bitmap) : Still()

        /** Being loaded somewhere else. Skip the draw this frame, quietly. */
        object Pending : Still()

        /** Cannot be loaded. Counted once through [Events.onOverlayFailed]. */
        object Failed : Still()
    }

    /**
     * How a still that is not yet a texture is obtained.
     *
     * **This is the one thing the export and the preview must do differently.**
     * The export decodes inline ([INLINE_STILLS]): it is not realtime, and a
     * frame drawn without its overlay would be a wrong frame in the file. The
     * preview cannot — a decode inside a realtime draw is a visible hitch — so
     * its source answers [Still.Pending], loads off the GL thread, and uploads
     * when the bitmap lands. "Not ready yet" and "failed" are different
     * answers on purpose: only one of them is worth telling the user about.
     */
    fun interface StillSource {
        fun obtain(path: String, maxPx: Int): Still
    }

    private class VideoState {
        var decoder: ExportClipDecoder? = null
        var failed = false
    }

    private val videoStates = mutableMapOf<String, VideoState>()

    /** Realtime only: one decode thread per live video overlay. */
    private val realtimeDecoders = mutableMapOf<String, RealtimeOverlayDecoder>()

    private var overlays: List<NativeTimelineOverlay> = overlays

    /**
     * Adopts an edited list **without** dropping the decoders of overlays that
     * are still in it.
     *
     * The preview used to build a fresh builder for every list, and the list
     * changes on every frame of a drag — so moving a video overlay closed and
     * reopened its codec sixty times a second, which is what made dragging one
     * crawl. Position, scale and mask are read from the list at draw time; a
     * decoder only has to go when its overlay is gone or points at another
     * file.
     */
    fun updateOverlays(list: List<NativeTimelineOverlay>) {
        overlays = list
        val paths = list.associate { it.id to it.path }
        val stale = realtimeDecoders.filter { (id, d) -> paths[id] != d.path }.keys.toList()
        for (id in stale) releaseRealtimeDecoder(id)
    }

    /**
     * Frees the decoder of every video overlay whose window has passed.
     *
     * Called at the **top** of each output frame, before the clip lanes
     * open anything. Codec instances are shared and scarce: releasing
     * expired overlays only when the overlays were drawn — after the lanes
     * had already tried to open — meant that at a clip boundary the next
     * clip's decoder competed with an overlay decoder that was about to be
     * freed anyway, and on devices near their codec limit the open lost.
     */

    /**
     * Tears a realtime overlay decoder down **codec first, surface after**.
     *
     * The two live on different threads, and freeing them in the wrong order
     * is the crash this was reported for: `BufferQueue has been abandoned`,
     * then `IllegalStateException` from a codec still decoding into the
     * surface that just went. [OverlayDecoderTeardown] sequences them without
     * anyone blocking — see it for why waiting was not the answer.
     */
    private fun releaseRealtimeDecoder(id: String) {
        val worker = realtimeDecoders.remove(id) ?: return
        val teardown = OverlayDecoderTeardown()
        teardown.begin { renderer.overlays.releaseVideoLane(id) }
        worker.release(teardown)
    }

    fun releaseExpired(t: Double) {
        for (overlay in overlays) {
            // The export's clock only walks forward, so "expired" means past
            // the end. A preview playhead can also be scrubbed back to before
            // the overlay starts, and a decoder kept open there holds one of
            // the device's few codec instances for a picture nobody can see.
            val gone = t >= overlay.endSeconds || (realtime && t < overlay.startSeconds)
            if (overlay.isVideo && gone && videoStates.containsKey(overlay.id)) {
                videoStates.remove(overlay.id)?.decoder?.release()
                renderer.overlays.releaseVideoLane(overlay.id)
            }
            if (overlay.isVideo && gone && realtimeDecoders.containsKey(overlay.id)) {
                releaseRealtimeDecoder(overlay.id)
            }
        }
    }

    fun drawsFor(t: Double): List<OverlayRenderer.Draw> {
        if (overlays.isEmpty()) return emptyList()

        val draws = mutableListOf<OverlayRenderer.Draw>()
        for (overlay in overlays) {
            if (!overlay.contains(t)) continue

            // Text with live glyph curves is the one overlay whose box-level
            // state is **not** what gets drawn, so it must not be what the
            // early-out consults either. `timing` is resolved here rather
            // than inside `textDraws` precisely so that the gate below and
            // the draw itself read the same value; see `textState`.
            val timing = if (overlay.isText) {
                TextAnimationTiming.of(overlay, overlay.glyphs.size)
            } else {
                null
            }
            val state = textState(overlay, t, timing)

            // The gate now tests the state that will actually be used.
            // For an image overlay, a video overlay, and text with no live
            // glyph curve that is `stateAt(t)` exactly as before; for text
            // whose glyphs animate it is the resting state, whose opacity
            // and scale are the overlay's authored values and so can only be
            // zero if the user authored them zero. A glyph animated to
            // nothing still drops itself inside `textDraws`, one glyph at a
            // time — which is the only place with the information to do it.
            if (state.opacity <= 0.0 || state.scale <= 0.0) continue

            val resolved = if (overlay.isVideo) {
                listOfNotNull(videoDraw(overlay, t, state))
            } else if (overlay.isText) {
                textDraws(overlay, t, state, timing!!)
            } else {
                listOfNotNull(imageDraw(overlay, state))
            }
            draws.addAll(resolved)
        }
        return draws
    }

    /**
     * The box-level state an overlay will actually be drawn with.
     *
     * **Exactly one pass may animate the text.** `stateAt` is the image
     * overlay's whole-box animation and it switches on the *same*
     * `animationIn`/`animationOut` strings the per-glyph catalog reads, so
     * once a glyph resolves a curve, letting the box-level state through as
     * well would fade the text twice (opacity squared) and slide it twice.
     * When the glyph pass owns the animation the box rests; when it owns
     * nothing — no animation, or ids that resolve to no slot — the box-level
     * state is used untouched, which is what keeps an unanimated text
     * overlay producing exactly the draws it does today.
     *
     * This is also why it is a gate as well as a value. A loop animation
     * with no in-animation is the case that makes the difference load
     * bearing: `stateAt` would leave a text overlay's box at whatever the
     * legacy arms compute — potentially zero opacity at an endpoint — while
     * every glyph curve is perfectly alive, and gating on it would drop
     * whole frames of text out of the file.
     */
    private fun textState(
        overlay: NativeTimelineOverlay,
        t: Double,
        timing: TextAnimationTiming?,
    ): NativeTimelineOverlay.FrameState {
        if (timing != null && timing.isActive) return overlay.restingState()
        return overlay.stateAt(t)
    }

    private fun imageDraw(
        overlay: NativeTimelineOverlay,
        state: NativeTimelineOverlay.FrameState,
    ): OverlayRenderer.Draw? {
        val cached = renderer.overlays.cachedImageTexture(overlay.path)
        val (textureId, aspect) = cached ?: run {
            val bitmap = when (val still = stills.obtain(overlay.path, OVERLAY_IMAGE_MAX_PX)) {
                is Still.Ready -> still.bitmap
                Still.Pending -> return null
                Still.Failed -> {
                    events.onOverlayFailed()
                    return null
                }
            }
            val uploaded = renderer.overlays.imageTexture(overlay.path, bitmap)
            // texImage2D copies the pixels; holding the bitmap as well
            // would double every overlay's memory for nothing.
            bitmap.recycle()
            uploaded
        }

        return draw(overlay, state, textureId, isExternal = false, aspect, null)
    }

    /**
     * One draw per glyph, all reading the overlay's atlas.
     *
     * The texture is uploaded once and every glyph samples its own cell, so
     * a 40-character text costs one upload and 40 quads — nothing for a GPU,
     * and what lets a later stage animate each character independently.
     *
     * **The quad is the whole padded cell, positioned so that the cell's
     * `src` sub-rect lands exactly on the glyph's box rect.** The cell is
     * bigger than the placement because its padding carries stroke and
     * shadow bleed; drawing only the placement would clip a shadow at the
     * letter's edge, while *placing* by the padded cell would composite the
     * bleed twice wherever neighbouring cells overlap. Drawing the cell
     * whole, anchored through `src`, gives the shadow its spill and each
     * texel exactly one contribution.
     */
    private fun textDraws(
        overlay: NativeTimelineOverlay,
        t: Double,
        /** Already resolved by [textState]'s rule — never `stateAt` raw. */
        state: NativeTimelineOverlay.FrameState,
        timing: TextAnimationTiming,
    ): List<OverlayRenderer.Draw> {
        val cached = renderer.overlays.cachedImageTexture(overlay.path)
        val (textureId, _) = cached ?: run {
            val bitmap = when (val still = stills.obtain(overlay.path, TEXT_ATLAS_MAX_PX)) {
                is Still.Ready -> still.bitmap
                Still.Pending -> return emptyList()
                Still.Failed -> {
                    events.onOverlayFailed()
                    return emptyList()
                }
            }
            val uploaded = renderer.overlays.imageTexture(overlay.path, bitmap)
            bitmap.recycle()
            uploaded
        }

        val glyphCount = overlay.glyphs.size

        val base = draw(
            overlay,
            state,
            textureId,
            isExternal = false,
            contentAspect = 1.0,
            texMatrix = null,
        )

        return overlay.glyphs.mapIndexedNotNull { index, glyph ->
            val srcW = glyph.srcRight - glyph.srcLeft
            val srcH = glyph.srcBottom - glyph.srcTop
            // A degenerate sub-rect has no scale to solve for; skipping the
            // glyph loses one letter, dividing by it would place every quad
            // at infinity and lose the whole text.
            if (srcW <= 0.0 || srcH <= 0.0) return@mapIndexedNotNull null

            // The cell's `src` sub-rect must cover the box rect, so the full
            // cell is that much larger, and its origin sits back by the
            // bleed that precedes `src`.
            val cellWidth = (glyph.boxRight - glyph.boxLeft) / srcW
            val cellHeight = (glyph.boxBottom - glyph.boxTop) / srcH
            val cellLeft = glyph.boxLeft - glyph.srcLeft * cellWidth
            val cellTop = glyph.boxTop - glyph.srcTop * cellHeight

            val glyphState = timing.stateAt(t, index, glyphCount)
            // A glyph animated to nothing is dropped rather than drawn at
            // zero: a zero-area quad is wasted state changes, and a negative
            // scale would turn the letter inside out.
            if (glyphState.opacity <= 0.0 || glyphState.scale <= 0.0) {
                return@mapIndexedNotNull null
            }

            // The catalog measures displacement in **glyph heights**, on
            // both axes — that is what keeps a diagonal slide diagonal and
            // makes the travel scale with the type size rather than with the
            // box. `Draw` wants box-height fractions, so the conversion is
            // the glyph's own height as a fraction of the box, applied to x
            // and y alike. Using the glyph's *width* for x would make a
            // narrow letter like "i" slide a fraction of the distance a "W"
            // does, and the word would come apart mid-animation.
            val glyphHeightInBox = glyph.boxBottom - glyph.boxTop

            base.copy(
                opacity = base.opacity * glyphState.opacity,
                srcRect = floatArrayOf(
                    glyph.atlasLeft.toFloat(),
                    glyph.atlasTop.toFloat(),
                    glyph.atlasRight.toFloat(),
                    glyph.atlasBottom.toFloat(),
                ),
                boxRect = floatArrayOf(
                    cellLeft.toFloat(),
                    cellTop.toFloat(),
                    (cellLeft + cellWidth).toFloat(),
                    (cellTop + cellHeight).toFloat(),
                ),
                glyphScale = glyphState.scale,
                glyphRotation = glyphState.rotation,
                glyphOffsetX = glyphState.offsetX * glyphHeightInBox,
                glyphOffsetY = glyphState.offsetY * glyphHeightInBox,
            )
            // `fillProgress` is deliberately dropped: the renderer has no
            // colour-fill pass yet, and inventing one here would make
            // `colour_fill` export as something the preview does not play.
        }
    }

    private fun videoDraw(
        overlay: NativeTimelineOverlay,
        t: Double,
        state: NativeTimelineOverlay.FrameState,
    ): OverlayRenderer.Draw? {
        if (realtime) return realtimeVideoDraw(overlay, t, state)
        val videoState = videoStates.getOrPut(overlay.id) { VideoState() }
        if (videoState.failed) return null

        var decoder = videoState.decoder
        if (decoder == null) {
            if (videoStates.count { it.value.decoder != null } >= maxVideoDecoders) {
                videoState.failed = true
                events.onDecoderSkipped()
                return null
            }
            val lane = renderer.overlays.videoLane(overlay.id)
            val surface = lane.surface
            if (surface == null) {
                videoState.failed = true
                events.onOverlayFailed()
                return null
            }
            decoder = ExportClipDecoder(overlay.path, surface)
            if (!decoder.open((overlay.sourceStart * 1_000_000L).toLong())) {
                videoState.failed = true
                events.onOverlayFailed()
                renderer.overlays.releaseVideoLane(overlay.id)
                return null
            }
            videoState.decoder = decoder
        }

        val lane = renderer.overlays.videoLane(overlay.id)
        val since = lane.frameSequence()
        if (decoder.advanceTo((overlay.sourceAt(t) * 1_000_000L).toLong())) {
            if (!lane.awaitFrameAfter(since, frameWaitMs)) {
                events.onLateFrame()
            }
        }
        renderer.overlays.updateVideoLane(overlay.id)

        // Before its first frame lands there is nothing to sample; skipping
        // the draw shows the frame under it rather than undefined texels.
        if (lane.frameSequence() == 0L) return null

        return draw(
            overlay,
            state,
            lane.textureId,
            isExternal = true,
            decoder.displayAspect,
            lane.texMatrix,
        )
    }

    /**
     * The preview's video overlay: ask for the frame, draw whatever has
     * already landed, never wait. See [RealtimeOverlayDecoder] for why the
     * decode is not done here.
     */
    private fun realtimeVideoDraw(
        overlay: NativeTimelineOverlay,
        t: Double,
        state: NativeTimelineOverlay.FrameState,
    ): OverlayRenderer.Draw? {
        var worker = realtimeDecoders[overlay.id]
        if (worker == null) {
            if (realtimeDecoders.size >= maxVideoDecoders) {
                events.onDecoderSkipped()
                return null
            }
            val surface = renderer.overlays.videoLane(overlay.id).surface
            if (surface == null) {
                events.onOverlayFailed()
                return null
            }
            worker = RealtimeOverlayDecoder(
                path = overlay.path,
                surface = surface,
                startUs = (overlay.sourceStart * 1_000_000L).toLong(),
                // A codec reclaimed by the system or failing mid-frame is not
                // ours to prevent; it must be said rather than crashed on.
                onFailed = { events.onOverlayFailed() },
            )
            realtimeDecoders[overlay.id] = worker
        }
        if (worker.failed) {
            events.onOverlayFailed()
            return null
        }

        worker.request((overlay.sourceAt(t) * 1_000_000L).toLong())

        val lane = renderer.overlays.videoLane(overlay.id)
        renderer.overlays.updateVideoLane(overlay.id)
        // Nothing to sample until the first frame lands; its arrival asks for
        // the redraw that shows it.
        if (lane.frameSequence() == 0L) return null

        return draw(
            overlay,
            state,
            lane.textureId,
            isExternal = true,
            worker.displayAspect,
            lane.texMatrix,
        )
    }

    private fun draw(
        overlay: NativeTimelineOverlay,
        state: NativeTimelineOverlay.FrameState,
        textureId: Int,
        isExternal: Boolean,
        contentAspect: Double,
        texMatrix: FloatArray?,
    ): OverlayRenderer.Draw {
        return OverlayRenderer.Draw(
            textureId = textureId,
            isExternal = isExternal,
            contentAspect = if (contentAspect > 0.0) contentAspect else 1.0,
            centerX = overlay.centerX + state.offsetX,
            centerY = overlay.centerY + state.offsetY,
            boxWidth = overlay.boxWidth,
            boxHeight = overlay.boxHeight,
            scale = state.scale,
            rotation = overlay.rotation,
            opacity = state.opacity,
            texMatrix = texMatrix,
            mask = overlay.mask,
            chromaKey = overlay.chromaKey,
        )
    }

    fun release() {
        for ((id, state) in videoStates) {
            state.decoder?.release()
            renderer.overlays.releaseVideoLane(id)
        }
        videoStates.clear()
        for (id in realtimeDecoders.keys.toList()) releaseRealtimeDecoder(id)
        realtimeDecoders.clear()
    }

    companion object {
        /**
         * The export's cap on video-overlay decoders, and the preview's when
         * the device will not describe its decoder
         * ([com.techfamz.slimshotai.nativepreview.DecoderBudget.LEGACY_CAP]).
         * The export keeps a constant on purpose: it is not realtime, so a
         * decoder over the throughput line merely slows the run rather than
         * inviting a reclaim, and its two clip lanes are its own
         * `ExportClipDecoder`s, not ExoPlayer's. An overlay beyond the cap is
         * skipped with a warning rather than risking every codec on the device.
         */
        const val MAX_OVERLAY_DECODERS = 2

        /** Largest side a preview overlay image is decoded at; the export's cap. */
        const val IMAGE_MAX_PX = OVERLAY_IMAGE_MAX_PX

        /** Decode where you stand: what the export has always done. */
        val INLINE_STILLS = StillSource { path, maxPx ->
            StillImageDecoder.decode(path, maxPx, maxPx)?.let { Still.Ready(it) } ?: Still.Failed
        }
    }
}

/**
 * One text overlay's animation windows, resolved once per overlay per frame.
 *
 * Splitting this out of the per-glyph loop is not only a saving: the in/out
 * durations are a property of the *overlay* (they depend on the glyph count, not
 * on which glyph), and computing them per glyph would invite a future edit that
 * made one letter's window differ from its neighbour's.
 */
private class TextAnimationTiming(
    private val inId: String?,
    private val outId: String?,
    private val loopId: String?,
    private val startSeconds: Double,
    private val endSeconds: Double,
    private val inSeconds: Double,
    private val outSeconds: Double,
    private val loopPeriod: Double,
) {

    /**
     * Whether any per-glyph curve will actually run.
     *
     * False means the glyph pass contributes nothing, and the caller keeps the
     * box-level animation — the path an unanimated text overlay takes today.
     */
    val isActive: Boolean
        get() = (inId != null && inSeconds > 0.0) ||
            (outId != null && outSeconds > 0.0) ||
            (loopId != null && loopPeriod > 0.0)

    /**
     * The glyph's state at [t], composed from whichever windows are live.
     *
     * The three windows compose by multiplication rather than by precedence.
     * In and out can both be live on a very short overlay — `resolveDurations`
     * compresses them to fit but does not separate them — and a loop runs
     * underneath both, so an entrance into a continuous wave does not stutter at
     * the handover. Each window that is *not* live contributes its resting
     * state, which is identity for all five channels.
     */
    fun stateAt(t: Double, index: Int, glyphCount: Int): TextGlyphState {
        var opacity = 1.0
        var offsetX = 0.0
        var offsetY = 0.0
        var scale = 1.0
        var rotation = 0.0

        fun apply(state: TextGlyphState) {
            opacity *= state.opacity
            offsetX += state.offsetX
            offsetY += state.offsetY
            scale *= state.scale
            rotation += state.rotation
        }

        val elapsed = t - startSeconds
        val remaining = endSeconds - t

        if (inId != null && inSeconds > 0.0 && elapsed < inSeconds) {
            apply(TextAnimationCurves.stateAt(inId, elapsed / inSeconds, index, glyphCount))
        }
        if (outId != null && outSeconds > 0.0 && remaining < outSeconds) {
            // `p` runs 0 at the window's start to 1 at the overlay's end, which
            // is the sense every out-curve is written in: it rests at `p == 0`.
            apply(
                TextAnimationCurves.stateAt(
                    outId,
                    (1.0 - remaining / outSeconds).coerceIn(0.0, 1.0),
                    index,
                    glyphCount,
                ),
            )
        }
        if (loopId != null && loopPeriod > 0.0) {
            // The loop's phase is its own, measured from the overlay's start and
            // wrapped by one cycle — not by the overlay's span. Every loop curve
            // is a whole number of cycles in `p`, so `p == 0` and `p == 1` are
            // the same instant of the motion and the wrap is invisible; deriving
            // the phase from the span instead would put the seam at an arbitrary
            // point of the wave and make it jump once per loop.
            var phase = (elapsed / loopPeriod) % 1.0
            // `%` keeps the sign of the dividend, and `elapsed` can be a hair
            // negative on the overlay's very first frame from float rounding.
            if (phase < 0.0) phase += 1.0
            apply(TextAnimationCurves.stateAt(loopId, phase, index, glyphCount))
        }

        return TextGlyphState(
            opacity = opacity.coerceIn(0.0, 1.0),
            offsetX = offsetX,
            offsetY = offsetY,
            scale = scale.coerceAtLeast(0.0),
            rotation = rotation,
        )
    }

    companion object {
        fun of(overlay: NativeTimelineOverlay, glyphCount: Int): TextAnimationTiming {
            // Ids resolve **by slot**, never by name alone. A legacy `'fade'`
            // means `fade_in` in the in-slot and `fade_out` in the out-slot, and
            // a bare in-only id sitting in the out-slot resolves to nothing at
            // all — the old widget layer played no out-animation for one, so
            // inventing one here would add an exit to saved drafts that never
            // had one.
            val inId = overlay.animationIn
                ?.let { TextAnimationCurves.resolveAnimationId(it, TextAnimationCategory.IN) }
            val outId = overlay.animationOut
                ?.let { TextAnimationCurves.resolveAnimationId(it, TextAnimationCategory.OUT) }
            val loopId = overlay.animationLoop
                ?.let { TextAnimationCurves.resolveAnimationId(it, TextAnimationCategory.LOOP) }

            val span = overlay.endSeconds - overlay.startSeconds

            // **One speed drives both the in and the out window**, and
            // `resolveDurations` — the port of the Dart's compression rule — is
            // the only thing that resolves them, so a short overlay's windows
            // squeeze identically on both sides of the boundary.
            //
            // `NativeTimelineOverlay` carries `speedIn` and `speedOut`
            // separately because that is the shape of the JSON, but **they are
            // expected to be equal**: the animation tab is a single Speed
            // slider. Honouring a divergence would mean a second copy of the
            // compression rule living here, kept in sync with the Dart across a
            // boundary nothing type-checks — the exact drift this whole file is
            // built to prevent — for a control the UI does not offer. If the two
            // ever genuinely need to differ, widen `resolveDurations` to take
            // both on *both* sides of the port and regenerate the fixture; do
            // not re-add a local re-derivation here.
            val durations = TextAnimationCurves.resolveDurations(
                spanSeconds = span,
                inAnimationId = overlay.animationIn,
                outAnimationId = overlay.animationOut,
                glyphCount = glyphCount,
                speed = overlay.speedIn,
            )

            val inSeconds = durations.inSeconds
            val outSeconds = durations.outSeconds

            val loopPeriod = if (loopId == null) {
                0.0
            } else {
                TextAnimationCurves.naturalDuration(loopId, glyphCount) / overlay.speedLoop
            }

            return TextAnimationTiming(
                inId = inId,
                outId = outId,
                loopId = loopId,
                startSeconds = overlay.startSeconds,
                endSeconds = overlay.endSeconds,
                inSeconds = inSeconds,
                outSeconds = outSeconds,
                loopPeriod = loopPeriod,
            )
        }
    }
}

/** Largest side an overlay image is decoded at; well above any overlay box. */
private const val OVERLAY_IMAGE_MAX_PX = 1024

/**
 * Largest side a text atlas is decoded at.
 *
 * Separate from [OVERLAY_IMAGE_MAX_PX] (1024) deliberately: that cap is generous
 * for a photo drawn into a small overlay box, but an atlas is rasterised at
 * export density — up to 4096 — and decoding it at 1024 would downscale it,
 * making exported text *blurrier* than the flat raster it replaced. The atlas is
 * already capped at the texture limit on the Dart side, so this cap only has to
 * not undercut it.
 */
private const val TEXT_ATLAS_MAX_PX = 4096
