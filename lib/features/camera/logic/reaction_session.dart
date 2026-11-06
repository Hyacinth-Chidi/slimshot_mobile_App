import 'dart:async';

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
  const ReactionRecording({required this.cameraPath, required this.durationMs, required this.pieces});

  final String cameraPath;
  final int durationMs;
  final List<ReactionPiece> pieces;
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
/// Pause stops both; a resume starts both. The video reaching its end ends
/// the take through [onVideoEnded].
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

  bool _started = false;
  bool _finished = false;
  bool _saidEnded = false;

  bool get isRunning => _started && !_finished;

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
    if (_finished || !_awaitingRun || camera.recording != RecordingState.recording) return;
    final recording = camera.recordingNowMs();
    if (recording == null) return;
    _awaitingRun = false;
    _lastRecordingMs = recording;
    _log.beginRun(recordingMs: recording, videoMs: _videoFromMs);
    _runVideoFromMs = _videoFromMs;
    unawaited(player.play());
  }

  Future<void> pauseOrResume() async {
    if (_finished) return;
    switch (camera.recording) {
      case RecordingState.recording:
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

  /// Measures the video against the recording once, both running. The take
  /// does this on its own every quarter of a second.
  @visibleForTesting
  Future<void> sample() async {
    if (_finished || _awaitingRun || camera.recording != RecordingState.recording) return;
    final before = camera.recordingNowMs();
    final video = await player.positionMs();
    final after = camera.recordingNowMs();
    if (before == null || after == null || video == null) return;
    // Paused, stopped or restarted while the player answered.
    if (_finished || _awaitingRun || camera.recording != RecordingState.recording) return;
    _lastRecordingMs = after;
    if (video > _runVideoFromMs + kReactionVideoMovingMs) {
      _log.sample(recordingMs: (before + after) ~/ 2, videoMs: video);
    }
    if (!_saidEnded && (player.completed || video >= player.durationMs - kReactionVideoEndSlackMs)) {
      _saidEnded = true;
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
    if (!_awaitingRun) _log.endRun(recordingMs: atMs ?? _lastRecordingMs);
  }

  ReactionRecording _recording(VideoShot shot) {
    final pieces = _log.pieces();
    return ReactionRecording(
      cameraPath: shot.path,
      durationMs: shot.durationMs,
      pieces: pieces.isEmpty
          ? [ReactionPiece(startMs: 0, endMs: shot.durationMs, offsetMs: _videoFromMs)]
          : pieces,
    );
  }

  /// Lets go of the camera without finishing anything: the screen is going.
  void dispose() {
    _finished = true;
    _sampler?.cancel();
    camera.removeListener(_onCamera);
  }
}
