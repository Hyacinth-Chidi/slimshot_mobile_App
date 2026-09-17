package com.techfamz.slimshotai.nativepreview

import android.content.Context
import android.net.Uri
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import java.io.File
import kotlin.math.abs

/**
 * The sound of the preview's video overlays.
 *
 * **Device-reported, and the reason this exists:** once the overlay's picture
 * moved into GL the overlay went silent on the canvas while the export kept its
 * sound. The `video_player` controller that was deleted had been the overlay's
 * picture *and* its sound; `OverlayDrawBuilder` replaced only the picture.
 *
 * One `ExoPlayer` per audible overlay near the playhead, **with the video
 * track disabled**. That is the whole reason this is here and not in the
 * Flutter-side `just_audio` manager the imported music uses: `just_audio` is
 * ExoPlayer with no way to turn the video track off, and from API 23 ExoPlayer
 * keeps a video decoder alive on a placeholder surface even when nothing shows
 * it — a hidden hardware codec per overlay, on top of the two clip lanes and
 * the overlay picture decoders, which is the resource low-end devices run out
 * of first. With the track disabled no video codec is ever created; what is
 * left is an audio decoder, which is software and plentiful.
 *
 * Slaved to the clock the overlay's picture is drawn from, so the two cannot
 * part. Speed goes through [PlaybackRate.pitchFor], the rule that makes the
 * preview sound like the export's resampler.
 *
 * Application thread only, like every player in the engine. What to do each
 * tick is decided by [OverlayAudioSync]; this class only carries it out.
 */
@UnstableApi
internal class OverlayAudioPlayers(
    private val context: Context,
    private val onWarning: (String) -> Unit,
) {
    private class Entry(val player: ExoPlayer, val path: String) {
        var speed = Double.NaN
        var volume = Float.NaN
        var lastSeekMs = 0L
        /** When the gain ramp last moved, so a dropped tick is not a jump. */
        var lastGainTickMs = 0L
        var failed = false
    }

    private val entries = LinkedHashMap<String, Entry>()
    private val warnedIds = HashSet<String>()
    private var warnedCap = false

    /**
     * Brings every overlay's sound to [clock].
     *
     * [advancing] is whether that clock is running right now — the engine
     * genuinely playing, or the editor walking the tail. Cheap when nothing
     * changes: every setter below is change-guarded, because handing ExoPlayer
     * an unchanged volume or rate each tick rebuilds its audio pipeline
     * (fault 10 in the lanes' history).
     */
    fun sync(
        overlays: List<NativeTimelineOverlay>,
        clock: Double,
        advancing: Boolean,
        masterVolume: Float,
    ) {
        if (overlays.isEmpty() && entries.isEmpty()) return

        val wanted = overlays.filter { OverlayAudioSync.wantsPlayer(it, clock) }
        val wantedById = wanted.associateBy { it.id }

        // Gone, out of range, muted, or pointing at another file now.
        val stale = entries.filter { (id, entry) -> wantedById[id]?.path != entry.path }.keys.toList()
        for (id in stale) entries.remove(id)?.player?.release()

        for (overlay in wanted) {
            val entry = entries[overlay.id] ?: open(overlay) ?: continue
            if (entry.failed) continue
            drive(entry, overlay, clock, advancing, masterVolume)
        }
    }

    private fun open(overlay: NativeTimelineOverlay): Entry? {
        if (entries.size >= MAX_PLAYERS) {
            if (!warnedCap) {
                warnedCap = true
                onWarning("Too many overlays with sound at once; some are silent in the preview.")
            }
            return null
        }
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(MIN_BUFFER_MS, MAX_BUFFER_MS, BUFFER_FOR_PLAYBACK_MS, BUFFER_AFTER_REBUFFER_MS)
            .build()
        val player = ExoPlayer.Builder(context).setLoadControl(loadControl).build()
        // See the class comment: without this the player holds a video codec.
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, true)
            .build()
        player.volume = 0f
        player.playWhenReady = false

        val entry = Entry(player, overlay.path)
        entry.volume = 0f
        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                // A file with no audio track is not an error and never lands
                // here; this is a file the device cannot read or decode.
                Log.w(TAG, "overlay ${overlay.id} sound failed: ${error.errorCodeName}", error)
                entry.failed = true
                // The entry stays, so the overlay is not reopened every tick;
                // the player does not, since it can do nothing more.
                player.release()
                if (warnedIds.add(overlay.id)) {
                    onWarning("An overlay's sound could not be played in the preview.")
                }
            }
        })
        player.setMediaItem(MediaItem.fromUri(Uri.fromFile(File(overlay.path))))
        player.prepare()
        entries[overlay.id] = entry
        return entry
    }

    private fun drive(
        entry: Entry,
        overlay: NativeTimelineOverlay,
        clock: Double,
        advancing: Boolean,
        masterVolume: Float,
    ) {
        val player = entry.player

        if (entry.speed != overlay.speed) {
            entry.speed = overlay.speed
            val speed = overlay.speed.takeIf { it.isFinite() && it > 0.0 } ?: 1.0
            player.playbackParameters = PlaybackParameters(
                speed.toFloat(),
                PlaybackRate.pitchFor(speed, curved = false),
            )
        }

        val now = SystemClock.elapsedRealtime()
        val command = OverlayAudioSync.decide(
            advancing = advancing,
            inWindow = overlay.contains(clock),
            playWhenReady = player.playWhenReady,
            playerIsPlaying = player.isPlaying,
            playerPositionSeconds = player.currentPosition / 1000.0,
            // Ahead of its window `sourceAt` clamps to the overlay's first
            // sample, which is exactly where it should wait.
            targetSeconds = overlay.sourceAt(clock),
            msSinceLastSeek = now - entry.lastSeekMs,
        )

        // **The gain is ramped, and every audible edge is behind it.** A jump
        // from silence to full between two buffers is a click, so the target
        // is approached over a few ticks — and a seek is *taken at silence*,
        // which is what makes an unavoidable flush inaudible rather than a
        // crackle. Device-reported.
        val wantSound = command.playWhenReady && command.seekToSeconds == null
        val target = if (wantSound) OverlayAudioSync.gain(masterVolume, overlay) else 0f
        val ticks = if (entry.lastGainTickMs == 0L) {
            1
        } else {
            (((now - entry.lastGainTickMs) / TICK_MS).toInt()).coerceIn(1, OverlayAudioSync.RAMP_TICKS)
        }
        entry.lastGainTickMs = now
        val ramped = OverlayAudioSync.rampedGain(entry.volume, target, ticks)
        if (entry.volume.isNaN() || abs(entry.volume - ramped) > VOLUME_EPSILON || ramped != entry.volume) {
            entry.volume = ramped
            player.volume = ramped
        }

        // Silence first, then the flush. The next tick has no seek to make and
        // ramps back up.
        if (command.seekToSeconds != null) {
            if (!OverlayAudioSync.mayStop(entry.volume)) return
            entry.lastSeekMs = now
            player.seekTo((command.seekToSeconds * 1000.0).toLong())
            return
        }

        if (!command.playWhenReady) {
            // Stopping waits for the ramp too, or the pause is the click the
            // ramp exists to remove.
            if (player.playWhenReady && OverlayAudioSync.mayStop(entry.volume)) {
                player.playWhenReady = false
            }
            return
        }
        if (!player.playWhenReady) player.playWhenReady = true
    }

    /**
     * Silence, now. The next [sync] decides whether anything resumes.
     *
     * This one *is* abrupt, and deliberately: it answers an explicit pause, so
     * stopping some 80ms later would leave sound running past the button. The
     * gain is zeroed with it so the resume ramps up from silence rather than
     * snapping back to full.
     */
    fun pauseAll() {
        for (entry in entries.values) {
            entry.player.playWhenReady = false
            entry.player.volume = 0f
            entry.volume = 0f
            entry.lastGainTickMs = 0L
        }
    }

    fun release() {
        for (entry in entries.values) entry.player.release()
        entries.clear()
    }

    private companion object {
        const val TAG = "SlimshotOverlayAudio"

        /**
         * Players alive at once — overlays *near the playhead*, not overlays
         * in the project. Past it the rest are silent **and the user is
         * told**; the export mixes every one regardless.
         */
        const val MAX_PLAYERS = 4

        const val VOLUME_EPSILON = 0.001f

        /** The engine's tick, for converting elapsed time into ramp steps. */
        const val TICK_MS = 16L

        // A local file needs almost no pre-buffer; the lanes' numbers.
        const val MIN_BUFFER_MS = 2_000
        const val MAX_BUFFER_MS = 15_000
        const val BUFFER_FOR_PLAYBACK_MS = 200
        const val BUFFER_AFTER_REBUFFER_MS = 400
    }
}
