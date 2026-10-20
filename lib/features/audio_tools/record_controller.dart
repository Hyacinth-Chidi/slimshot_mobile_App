import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_recorder_service.dart';

enum RecordPhase { idle, countdown, recording, paused }

enum MicPermission { granted, denied, permanentlyDenied }

const String kRecordAtEndMessage = 'Move the playhead back to record over your video';
const String kMicDeniedMessage = 'Allow microphone access to record a voiceover';
const String kMicBlockedMessage = 'Microphone access is off. Turn it on in Settings';

/// A take Done hands back: the file, and where on the timeline it began.
typedef FinishedTake = ({String path, double durationSeconds, double timelineStart});

/// Recording mode's rules, apart from any widget or plugin.
///
/// One round button: record (after a 3-2-1 countdown), pause, record again —
/// one take across every pause, starting where capture first began. The
/// microphone is opened once and kept warm; [VoiceRecorder.setCapturing]
/// decides what is kept, and capture always starts **before** playback and
/// stops **after** it, so the take holds the picture's whole span.
///
/// While the mode is on the preview is muted by default — the phone's speaker
/// would otherwise play into the microphone, under the voice, for good — with
/// a toggle to hear it (headphones). That is a monitor mute only: it never
/// touches the project's own mute or any clip's volume, and is lifted when
/// the mode ends.
class RecordController extends ChangeNotifier {
  RecordController({
    required this.recorder,
    required this.requestMic,
    required this.newTakePath,
    required this.play,
    required this.pause,
    required this.setMonitorMuted,
    required this.playhead,
    required this.projectEnd,
    Future<void> Function(Duration step)? wait,
  }) : _wait = wait ?? ((step) => Future<void>.delayed(step));

  final VoiceRecorder recorder;
  final Future<MicPermission> Function() requestMic;
  final Future<String> Function() newTakePath;
  final void Function() play;
  final void Function() pause;
  final void Function(bool muted) setMonitorMuted;
  final double Function() playhead;
  final double Function() projectEnd;
  final Future<void> Function(Duration step) _wait;

  static const Duration _countdownStep = Duration(seconds: 1);

  /// Closer to the end than this, there is nothing left to speak over.
  static const double _endSlackSeconds = 0.05;

  RecordPhase _phase = RecordPhase.idle;
  RecordPhase get phase => _phase;

  int _countdown = 0;
  int get countdown => _countdown;

  double? _takeStart;
  double? get takeStart => _takeStart;

  double _takeLength = 0;
  double get takeLength => _takeLength;

  bool _monitorMuted = true;
  bool get monitorMuted => _monitorMuted;

  bool _needsSettings = false;

  /// The microphone was refused for good: the panel offers a way to Settings.
  bool get needsSettings => _needsSettings;

  String? _message;

  /// The one-line notice waiting to be shown, read once.
  String? takeMessage() {
    final message = _message;
    _message = null;
    return message;
  }

  bool _opened = false;
  bool _disposed = false;

  /// Bumped to cancel a countdown in flight.
  int _attempt = 0;

  Future<void> enter() async {
    _monitorMuted = true;
    setMonitorMuted(true);
    _notify();
  }

  void toggleMonitor() {
    _monitorMuted = !_monitorMuted;
    setMonitorMuted(_monitorMuted);
    _notify();
  }

  /// The round button.
  Future<void> toggle() async {
    switch (_phase) {
      case RecordPhase.countdown:
        return;
      case RecordPhase.recording:
        await _pauseTake();
        return;
      case RecordPhase.idle:
      case RecordPhase.paused:
        await _startTake();
    }
  }

  Future<void> _startTake() async {
    if (playhead() >= projectEnd() - _endSlackSeconds) {
      _say(kRecordAtEndMessage);
      return;
    }
    final attempt = ++_attempt;
    if (!_opened) {
      final permission = await requestMic();
      if (permission != MicPermission.granted) {
        _needsSettings = permission == MicPermission.permanentlyDenied;
        _say(_needsSettings ? kMicBlockedMessage : kMicDeniedMessage);
        return;
      }
      try {
        await recorder.open(await newTakePath());
      } on VoiceRecorderException catch (e) {
        _say(e.message);
        return;
      }
      _opened = true;
    }
    if (attempt != _attempt || _disposed) return;

    _phase = RecordPhase.countdown;
    for (var n = 3; n >= 1; n--) {
      _countdown = n;
      _notify();
      await _wait(_countdownStep);
      if (attempt != _attempt || _disposed) return;
    }
    _countdown = 0;
    _takeStart ??= playhead();
    await recorder.setCapturing(true);
    if (attempt != _attempt || _disposed) return;
    play();
    _phase = RecordPhase.recording;
    _notify();
  }

  Future<void> _pauseTake() async {
    if (_phase != RecordPhase.recording) return;
    _phase = RecordPhase.paused;
    pause();
    _notify();
    await recorder.setCapturing(false);
  }

  /// The video stopped without the button — the project's end, or anything
  /// else that paused it. The take stops with it, or it would run on over a
  /// still picture and no longer line up with what was on screen.
  void onPlaybackStopped() {
    if (_phase != RecordPhase.recording) return;
    _phase = RecordPhase.paused;
    _notify();
    unawaited(recorder.setCapturing(false));
  }

  /// Fed from the editor's playhead while the mode is on.
  void onPlayhead(double seconds) {
    if (_phase != RecordPhase.recording) return;
    final start = _takeStart;
    if (start != null && seconds > start) _takeLength = seconds - start;
    if (seconds >= projectEnd() - _endSlackSeconds) {
      unawaited(_pauseTake());
      return;
    }
    _notify();
  }

  /// Done: the take, or null when nothing was recorded. Ends the mode.
  Future<FinishedTake?> finish() async {
    _attempt++;
    await _pauseTake();
    final start = _takeStart;
    RecordedTake? take;
    if (_opened) {
      try {
        take = await recorder.close(keep: true);
      } on VoiceRecorderException catch (e) {
        _say(e.message);
      }
    }
    _leave();
    if (take == null || start == null) return null;
    return (path: take.path, durationSeconds: take.durationSeconds, timelineStart: start);
  }

  /// ✕: the take is thrown away. Ends the mode.
  Future<void> discard() async {
    _attempt++;
    await _pauseTake();
    if (_opened) {
      try {
        await recorder.close(keep: false);
      } on VoiceRecorderException {
        // Nothing was going to be kept.
      }
    }
    _leave();
  }

  void _leave() {
    _opened = false;
    _phase = RecordPhase.idle;
    _countdown = 0;
    _takeStart = null;
    _takeLength = 0;
    _monitorMuted = true;
    setMonitorMuted(false);
    _notify();
  }

  void _say(String message) {
    _message = message;
    _phase = _opened && _takeStart != null ? RecordPhase.paused : RecordPhase.idle;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _attempt++;
    super.dispose();
  }
}
