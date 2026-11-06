import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'camera_controller.dart';
import 'reaction.dart';

/// The video REACT plays beside you, as the take needs it. The real one is
/// `video_player`'s; tests drive their own.
abstract class ReactionPlayer {
  int get durationMs;

  /// The player says the video has played to its end.
  bool get completed;

  /// Where the video is now, asked of the player itself — not its last
  /// broadcast, which is up to half a second old. Null when it cannot say.
  Future<int?> positionMs();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(int ms);
}

/// A finished REACT take: the recording of you, and how the video ran
/// against it.
@immutable
class ReactionRecording {
  const ReactionRecording({
    required this.cameraPath,
    required this.durationMs,
    required this.pieces,
    this.removedAtMs,
  });

  final String cameraPath;
  final int durationMs;
  final List<ReactionPiece> pieces;

  /// When the video was taken away and you filled the frame; null if never.
  final int? removedAtMs;
}

/// How far from its end the video counts as over: two frames, so a take
/// does not wait for a last poll to say so.
const int kReactionVideoEndSlackMs = 60;

/// A sample counts once the video has moved this far from where its run
/// started — before that, the player has not got going.
const int kReactionVideoMovingMs = 20;

/// One REACT take: the camera recording you, the video playing with it, and
/// the two measured against each other ([ReactionSyncLog]).
///
/// **The video starts when the recording is seen to run** — its first
/// report — not when recording is asked for: the recorder takes a moment to
/// begin, and a video started early would play its first moment to nobody.
/// Pause stops both; a resume starts both. A tap on the video
/// ([toggleVideo]) stops only the video, its frame held while you go on
/// recording, and plays it on from there. The video reaching its end holds
/// its last frame and says so through [onVideoEnded]; from then it can be
/// taken away ([removeVideo]) and you fill the frame.
class ReactionTakeSession {
  ReactionTakeSession({
    required this.camera,
    required this.player,
    this.onVideoEnded,
    Duration? sampleEvery = const Duration(milliseconds: 250),
  }) : _sampleEvery = sampleEvery;

  final CameraController camera;
  final ReactionPlayer player;
  final VoidCallback? onVideoEnded;
  final Duration? _sampleEvery;

  final ReactionSyncLog _log = ReactionSyncLog();
  Timer? _sampler;

  /// A run is to open as soon as the recording is seen to run.
  bool _awaitingRun = false;

  /// Where the video starts from when the next run opens.
  int _videoFromMs = 0;

  /// Where the open run's video started.
  int _runVideoFromMs = 0;

  /// The recording's time at the last moment it was known.
  int _lastRecordingMs = 0;

  /// The recording's time when the open run began.
  int _runStartMs = 0;

  bool _started = false;
  bool _finished = false;
  bool _ended = false;
  bool _held = false;
  int? _removedAtMs;

  bool get isRunning => _started && !_finished;

  /// The video stopped by a tap, its frame held.
  bool get videoHeld => _held;

  /// The video played to its end and holds its last frame.
  bool get videoEnded => _ended;

  /// The video was taken away; you fill the frame.
  bool get videoRemoved => _removedAtMs != null;

  /// Neither held, ended nor gone: a run opens whenever the camera runs.
  bool get _videoLive => !_held && !_ended && _removedAtMs == null;

  /// Starts recording; the video follows once the recording reports. False
  /// when the camera did not start.
  Future<bool> start() async {
    if (_started) return false;
    _videoFromMs = await player.positionMs() ?? 0;
    _awaitingRun = true;
    await camera.shutter();
    if (!camera.isRecording) {
      _awaitingRun = false;
      return false;
    }
    _started = true;
    camera.addListener(_onCamera);
    final every = _sampleEvery;
    if (every != null) _sampler = Timer.periodic(every, (_) => unawaited(sample()));
    _onCamera();
    return true;
  }

  void _onCamera() {
    if (_finished || !_awaitingRun || !_videoLive || camera.recording != RecordingState.recording) return;
    final recording = camera.recordingNowMs();
    if (recording == null) return;
    _openRun(recording);
  }

  void _openRun(int recordingMs) {
    _awaitingRun = false;
    _lastRecordingMs = recordingMs;
    _runStartMs = recordingMs;
    _log.beginRun(recordingMs: recordingMs, videoMs: _videoFromMs);
    _runVideoFromMs = _videoFromMs;
    unawaited(player.play());
  }

  Future<void> pauseOrResume() async {
    if (_finished) return;
    switch (camera.recording) {
      case RecordingState.recording:
        // A held, ended or removed video is already still: only the camera
        // pauses, and the hold simply goes on when it resumes.
        if (!_videoLive) {
          await camera.pauseOrResume();
          return;
        }
        final at = camera.recordingNowMs();
        await Future.wait([player.pause(), camera.pauseOrResume()]);
        if (!_awaitingRun && at != null) {
          _log.endRun(recordingMs: at);
          _lastRecordingMs = at;
          _awaitingRun = true;
        }
        _videoFromMs = await player.positionMs() ?? _videoFromMs;
      case RecordingState.paused:
        await camera.pauseOrResume();
        _onCamera();
      case RecordingState.idle:
        break;
    }
  }

  /// A tap on the video while recording: it stops on its frame while you go
  /// on, or plays on from there. Nothing once it has ended or gone, or while
  /// the take itself is paused.
  Future<void> toggleVideo() async {
    if (!_started || _finished || _ended || _removedAtMs != null) return;
    if (camera.recording != RecordingState.recording) return;
    final at = camera.recordingNowMs();
    if (at == null) return;
    if (_held) {
      _held = false;
      _log.endHold(recordingMs: at);
      _openRun(at);
      return;
    }
    if (_awaitingRun) return;
    await player.pause();
    final frame = await player.positionMs() ?? _videoFromMs;
    _log.endRun(recordingMs: at);
    _log.beginHold(recordingMs: at, videoMs: frame);
    _lastRecordingMs = at;
    _videoFromMs = frame;
    _held = true;
  }

  /// Takes the video away once it has ended: you fill the frame from now on.
  void removeVideo() {
    if (!_started || _finished || !_ended || _removedAtMs != null) return;
    final at = camera.recordingNowMs() ?? _lastRecordingMs;
    _log.endHold(recordingMs: at);
    _removedAtMs = at;
  }

  /// Measures the video against the recording once, both running. The take
  /// does this on its own every quarter of a second.
  @visibleForTesting
  Future<void> sample() async {
    if (_finished || _awaitingRun || !_videoLive || camera.recording != RecordingState.recording) return;
    final before = camera.recordingNowMs();
    final video = await player.positionMs();
    final after = camera.recordingNowMs();
    if (before == null || after == null || video == null) return;
    // Paused, held, stopped or restarted while the player answered.
    if (_finished || _awaitingRun || !_videoLive || camera.recording != RecordingState.recording) return;
    _lastRecordingMs = after;
    final moving = video > _runVideoFromMs + kReactionVideoMovingMs;
    if (moving) {
      _log.sample(recordingMs: (before + after) ~/ 2, videoMs: video);
    }
    // The end is believed only once the video has been seen playing in this
    // run, and the length only when the player knows one: a player that
    // reports 0, or "completed" before it has started, would otherwise call
    // the video over a quarter of a second in.
    final duration = player.durationMs;
    final atEnd = duration > 0 && (player.completed || video >= duration - kReactionVideoEndSlackMs);
    if (!_ended && moving && atEnd) {
      _ended = true;
      // The hold starts exactly where the video runs out on the recording's
      // clock — the run's own offset says when — so no instant is left
      // between the last frame playing and its still.
      final offset = _log.runningOffsetMs ?? video - after;
      final runsOutAt = math.max(_runStartMs + 1, duration - offset);
      _log.endRun(recordingMs: runsOutAt);
      _log.beginHold(recordingMs: runsOutAt, videoMs: duration);
      unawaited(player.pause());
      debugPrint('REACT: the video ended at ${video}ms of ${duration}ms '
          '(completed: ${player.completed}); its last frame holds');
      onVideoEnded?.call();
    }
  }

  /// Ends the take: the video stops and the camera finishes the file. Null
  /// when nothing was recorded.
  Future<ReactionRecording?> stop() async {
    if (!_started || _finished) return null;
    final at = camera.recordingNowMs();
    _close(at);
    await player.pause();
    if (!camera.isRecording) return null;
    final shot = await camera.shutter();
    return shot is VideoShot ? _recording(shot) : null;
  }

  /// The camera ended the recording by itself — the app left mid-take — with
  /// [shot]: what was recorded is kept.
  Future<ReactionRecording?> endedBy(CameraShot shot) async {
    if (!_started || _finished) return null;
    _close(shot is VideoShot && shot.durationMs > 0 ? shot.durationMs : _lastRecordingMs);
    await player.pause();
    return shot is VideoShot ? _recording(shot) : null;
  }

  void _close(int? atMs) {
    _finished = true;
    _sampler?.cancel();
    camera.removeListener(_onCamera);
    final at = atMs ?? _lastRecordingMs;
    if (_log.isRunning) _log.endRun(recordingMs: at);
    if (_log.isHolding) _log.endHold(recordingMs: at);
  }

  ReactionRecording _recording(VideoShot shot) {
    final pieces = _log.pieces();
    return ReactionRecording(
      cameraPath: shot.path,
      durationMs: shot.durationMs,
      pieces: pieces.isEmpty
          ? [ReactionPiece(startMs: 0, endMs: shot.durationMs, offsetMs: _videoFromMs)]
          : pieces,
      removedAtMs: _removedAtMs,
    );
  }

  /// Lets go of the camera without finishing anything: the screen is going.
  void dispose() {
    _finished = true;
    _sampler?.cancel();
    camera.removeListener(_onCamera);
  }
}
