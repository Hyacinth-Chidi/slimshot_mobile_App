import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Plays a voice's sample in the Text to speech sheet: one at a time, free,
/// straight from its address.
abstract class VoiceSamplePlayer {
  /// The address of the sample playing now, or null.
  ValueListenable<String?> get playing;

  /// Plays [url], stopping whatever was playing.
  Future<void> play(String url);

  Future<void> stop();

  Future<void> dispose();
}

/// The editor's kind of `just_audio` player: it neither takes the phone's
/// audio nor answers interruptions, so `PlaybackGuard` stays the one owner of
/// the editor's sound (`playback_guard_test.dart` reads every player made
/// under `lib/features/video_editor/` for both flags).
class JustAudioSamplePlayer implements VoiceSamplePlayer {
  JustAudioSamplePlayer()
      : _player = AudioPlayer(
          handleInterruptions: false,
          handleAudioSessionActivation: false,
        ) {
    _states = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _playing.value = null;
      }
    });
  }

  final AudioPlayer _player;
  late final StreamSubscription<PlayerState> _states;
  final ValueNotifier<String?> _playing = ValueNotifier(null);

  /// Which play is current: a sample that loads after another was chosen
  /// does not start over it.
  int _turn = 0;

  /// The editor lets the player go as soon as the sheet's route pops, and
  /// the sheet's own teardown — which stops the sample — comes after it has
  /// slid away: a stop or play after dispose does nothing.
  bool _disposed = false;

  @override
  ValueListenable<String?> get playing => _playing;

  @override
  Future<void> play(String url) async {
    if (_disposed) return;
    final turn = ++_turn;
    _playing.value = url;
    try {
      await _player.stop();
      await _player.setUrl(url);
      if (turn != _turn) return;
      // `play` completes only when playback stops; nothing waits on it.
      unawaited(_player.play());
    } catch (e) {
      debugPrint('Voice sample would not play: $e');
      if (turn == _turn) _playing.value = null;
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _turn++;
    _playing.value = null;
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _turn++;
    await _states.cancel();
    _playing.dispose();
    await _player.dispose();
  }
}
