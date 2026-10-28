import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';

/// The phone's audio, held by the editor while it plays: [AudioSession] in
/// the app, a fake in tests.
abstract class PlaybackAudio {
  /// Takes the audio for the editor's playback — other apps' sound pauses.
  Future<void> take();

  /// Gives it back, so other apps can play again.
  Future<void> release();

  /// Something else has taken the audio — a call, another app's sound,
  /// headphones coming out.
  Stream<void> get interruptions;
}

/// Stops the editor's playback where it must not go on (the owner's report,
/// 2026-10-28: minimised, the video and music played on).
///
/// - **The app leaving the screen** — Home, another app, the screen locking,
///   a call screen taking over — pauses it. Still on screen it plays on: the
///   notifications pulled down or a permission prompt only cover it.
/// - **Something else taking the audio** pauses it too: an incoming call,
///   another app's sound, headphones coming out (the clip sound would carry
///   on from the speaker). The audio is held while the editor plays and
///   given back the moment it stops.
/// - **Coming back, it stays paused** where it stopped; play is the user's.
///
/// It pauses through the editor's own pause ([pause]), the same path as the
/// button, so the picture, the clips' and overlays' sound, the music, the
/// playhead and a voiceover take stop together — nothing new to keep in
/// step. **The guard is the one owner of the editor's sound**: its music
/// players leave interruptions to it, or one paused and resumed around a
/// call would play over an editor the guard had paused.
class PlaybackGuard {
  PlaybackGuard({
    required PlaybackAudio audio,
    required bool Function() isPlaying,
    required VoidCallback pause,
  }) : _audio = audio,
       _isPlaying = isPlaying,
       _pause = pause {
    _lifecycle = AppLifecycleListener(onHide: _stop);
    _interruptions = audio.interruptions.listen((_) => _stop());
  }

  final PlaybackAudio _audio;
  final bool Function() _isPlaying;
  final VoidCallback _pause;
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<void> _interruptions;
  bool _holding = false;
  bool _disposed = false;

  /// Follows the editor's play state: the audio is the editor's while it
  /// plays, and given back the moment it stops.
  void playingChanged(bool playing) {
    if (_disposed || playing == _holding) return;
    _holding = playing;
    unawaited(playing ? _audio.take() : _audio.release());
  }

  void _stop() {
    if (!_disposed && _isPlaying()) _pause();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lifecycle.dispose();
    unawaited(_interruptions.cancel());
    if (_holding) {
      _holding = false;
      unawaited(_audio.release());
    }
  }
}

/// [PlaybackAudio] through `audio_session`, the session the app's `just_audio`
/// players share. On Android it keeps **one** request for the app, so the
/// editor and a player can never take the audio from each other, and it
/// watches for headphones coming out only while it holds the audio.
class SessionPlaybackAudio implements PlaybackAudio {
  SessionPlaybackAudio({Future<AudioSession> Function()? session})
    : _sessionOf = session ?? (() => AudioSession.instance) {
    unawaited(_listen());
  }

  final Future<AudioSession> Function() _sessionOf;
  final StreamController<void> _interruptions =
      StreamController<void>.broadcast();
  final List<StreamSubscription<void>> _subscriptions = [];
  bool _disposed = false;

  /// Takes and releases run one after another, in the order asked: the
  /// first sets the session up, and a release overtaking a slow take would
  /// leave the audio held behind a paused editor.
  Future<void> _queue = Future<void>.value();

  @override
  Stream<void> get interruptions => _interruptions.stream;

  @override
  Future<void> take() => _enqueue(true);

  @override
  Future<void> release() => _enqueue(false);

  Future<void> _enqueue(bool active) {
    return _queue = _queue.then((_) async {
      final session = await _session();
      if (session == null) return;
      try {
        // Granted or refused, playback goes on: a refusal is the phone in a
        // call, and a press of play there is the user's own choice.
        await session.setActive(active);
      } catch (e) {
        debugPrint('Audio session ${active ? 'take' : 'release'} failed: $e');
      }
    });
  }

  /// The session, set up for music once — shared, since listening for
  /// interruptions and the first take both ask for it at once, and each
  /// would otherwise find it not yet set up. Null where it cannot be had
  /// (tests, a platform without it), which only costs the interruptions.
  Future<AudioSession?> _session() => _ready ??= _setUp();
  Future<AudioSession?>? _ready;

  Future<AudioSession?> _setUp() async {
    try {
      final session = await _sessionOf();
      if (!session.isConfigured) {
        await session.configure(const AudioSessionConfiguration.music());
      }
      return session;
    } catch (e) {
      debugPrint('Audio session unavailable: $e');
      return null;
    }
  }

  Future<void> _listen() async {
    final session = await _session();
    if (session == null || _disposed) return;
    // A call or another app taking the audio stops the editor. A duck does
    // not — a notification's ping asks the others to dip, and the phone
    // lowers the editor for a moment while it plays on; stopping there would
    // stop every edit at every incoming message. An interruption ending does
    // not either: coming back, the editor stays paused.
    _subscriptions
      ..add(
        session.interruptionEventStream
            .where(
              (event) =>
                  event.begin && event.type != AudioInterruptionType.duck,
            )
            .listen((_) => _interrupt()),
      )
      ..add(session.becomingNoisyEventStream.listen((_) => _interrupt()));
  }

  void _interrupt() {
    if (!_disposed) _interruptions.add(null);
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _interruptions.close();
  }
}
