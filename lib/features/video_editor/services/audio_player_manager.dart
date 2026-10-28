import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/audio_track_model.dart';

/// While playing, only a jump this large is corrected — a scrub, a loop
/// round — never drift.
///
/// Every seek of a playing track is **heard**, as a click. The music player
/// and the engine are two players with no shared clock, and the music always
/// sits a little behind — the time its sound takes to start, steady for the
/// whole track. Correcting from 0.1 s seeked every 1.5 s on that alone, and
/// the music crackled. The overlay sound learned the same lesson
/// (`OverlayAudioSync.JUMP_SECONDS`, the same 0.5).
const double kMusicJumpSeconds = 0.5;

/// Corrections are at least this far apart, the start counting as one: a
/// player that has just been told to play takes a moment to get going, and
/// reading that as a jump would seek again right after every start.
const Duration kMusicCorrectionInterval = Duration(seconds: 2);

/// Before a track starts, a playhead that has moved on by more than this
/// while its seek landed gets a second, short seek. Before only — once the
/// track plays, a second seek is a second click.
const double kMusicSettleToleranceSeconds = 0.02;

/// What the manager needs of a music player: just_audio's, or a test's.
abstract class MusicPlayer {
  bool get playing;
  Duration get position;
  Future<void> setFilePath(String path);
  Future<void> setVolume(double volume);
  Future<void> seek(Duration position);

  /// Starts playing; does not wait for playback to end.
  void play();
  Future<void> pause();
  Future<void> dispose();
}

class _JustAudioMusicPlayer implements MusicPlayer {
  /// The editor's `PlaybackGuard` holds the phone's audio and pauses the
  /// whole editor when a call, another app or unplugged headphones take it.
  /// Left to itself, a player would pause alone — the video playing on — and
  /// resume by itself after a call, over an editor the guard had paused.
  final AudioPlayer _player = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );

  @override
  bool get playing => _player.playing;
  @override
  Duration get position => _player.position;
  @override
  Future<void> setFilePath(String path) => _player.setFilePath(path);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  // just_audio's play() completes when playback ends, not when it starts.
  @override
  void play() => unawaited(_player.play());
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> dispose() => _player.dispose();
}

class AudioPlayerManager {
  AudioPlayerManager({MusicPlayer Function()? createPlayer, Duration Function()? clock})
      : _createPlayer = createPlayer ?? _JustAudioMusicPlayer.new,
        _clock = clock ?? (Stopwatch()..start()).elapsedFunction;

  final MusicPlayer Function() _createPlayer;
  final Duration Function() _clock;

  final Map<String, MusicPlayer> _players = {};
  final Map<String, bool> _isSeeking = {};
  final Map<String, double> _lastSeekTarget = {};

  /// When each track was last started or corrected (see
  /// [kMusicCorrectionInterval]).
  final Map<String, Duration> _lastAlignedAt = {};

  /// The playhead as last reported, and when: a seek takes time, and the
  /// playhead moves on meanwhile.
  double _playhead = 0;
  Duration _playheadAt = Duration.zero;
  bool _advancing = false;

  /// Each player's own volume, so a lifted monitor mute can put it back.
  final Map<String, double> _volumes = {};

  bool _monitorMuted = false;

  /// Silences every track while a voiceover is recorded — the phone's
  /// speaker would otherwise play into the microphone. Only what is heard:
  /// no track's own volume changes.
  set monitorMuted(bool muted) {
    if (_monitorMuted == muted) return;
    _monitorMuted = muted;
    for (final entry in _players.entries) {
      entry.value.setVolume(muted ? 0.0 : (_volumes[entry.key] ?? 1.0));
    }
  }

  bool get monitorMuted => _monitorMuted;

  /// What a track's player plays at: its volume, or nothing while the
  /// monitor is muted.
  double effectiveVolume(AudioTrackModel track) => _monitorMuted ? 0.0 : track.volume;

  Future<void> syncTracks(List<AudioTrackModel> tracks) async {
    final currentIds = tracks.map((t) => t.id).toSet();

    // Remove unused players
    final toRemove = _players.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in toRemove) {
      await _players[id]?.dispose();
      _players.remove(id);
      _isSeeking.remove(id);
      _lastSeekTarget.remove(id);
      _lastAlignedAt.remove(id);
      _volumes.remove(id);
    }

    // Add new players
    for (final track in tracks) {
      if (!_players.containsKey(track.id)) {
        final player = _createPlayer();
        await player.setFilePath(track.filePath);
        _players[track.id] = player;
      }
      // Update volume
      _volumes[track.id] = track.volume;
      _players[track.id]?.setVolume(effectiveVolume(track));
    }
  }

  void setVolumeSync(String id, double volume) {
    _volumes[id] = volume;
    _players[id]?.setVolume(_monitorMuted ? 0.0 : volume);
  }

  /// The playhead now: as last reported, carried on by the time since while
  /// playing.
  double get _playheadNow {
    if (!_advancing) return _playhead;
    return _playhead + (_clock() - _playheadAt).inMicroseconds / 1e6;
  }

  double _sourceTarget(AudioTrackModel track, double playhead) =>
      track.sourceStart + (playhead - track.timelineStart);

  bool _covers(AudioTrackModel track, double playhead) =>
      playhead >= track.timelineStart && playhead < track.timelineEnd;

  void seekAndPlaySync(double globalPosition, List<AudioTrackModel> tracks, bool isPlaying) {
    _playhead = globalPosition;
    _playheadAt = _clock();
    _advancing = isPlaying;

    for (final track in tracks) {
      final player = _players[track.id];
      if (player == null) continue;

      if (_isSeeking[track.id] == true) continue;

      // Check if global playhead is within this audio track's timeline bounds
      if (_covers(track, globalPosition)) {
        // Calculate where we should be in the audio source
        final targetSourcePosition = _sourceTarget(track, globalPosition);

        if (!player.playing && isPlaying) {
          unawaited(_align(track, player, thenPlay: true));
        } else if (player.playing && !isPlaying) {
          unawaited(player.pause());
        } else if (!isPlaying) {
          // Scrubbing while paused
          final currentPos = player.position.inMilliseconds / 1000.0;
          if ((currentPos - targetSourcePosition).abs() > 0.1) {
            _performSeek(track.id, player, targetSourcePosition);
          }
        } else {
          final last = _lastAlignedAt[track.id];
          final settled = last == null || _clock() - last >= kMusicCorrectionInterval;
          final currentPos = player.position.inMicroseconds / 1e6;
          if (settled && (currentPos - targetSourcePosition).abs() > kMusicJumpSeconds) {
            unawaited(_align(track, player, thenPlay: false));
          }
        }
      } else {
        // Outside the track bounds, pause and seek to start for readiness
        if (player.playing) {
          unawaited(player.pause());
        }

        final currentPos = player.position.inMilliseconds / 1000.0;
        if ((currentPos - track.sourceStart).abs() > 0.1) {
          _performSeek(track.id, player, track.sourceStart);
        }
      }
    }
  }

  /// Puts [track] where the playhead is — and with [thenPlay], plays it from
  /// there — only once its seek has landed.
  ///
  /// `play()` used to go out with the seek still in flight, so the music
  /// started from wherever the player happened to be, and late by however
  /// long the seek took. A seek takes long enough for the playhead to move
  /// on, so before a start a second, short one follows where it has — never
  /// on a playing track, where it would be heard.
  Future<void> _align(AudioTrackModel track, MusicPlayer player, {required bool thenPlay}) async {
    _isSeeking[track.id] = true;
    try {
      await player.seek(_at(_sourceTarget(track, _playheadNow)));
      final target = _sourceTarget(track, _playheadNow);
      if (thenPlay &&
          (player.position.inMicroseconds / 1e6 - target).abs() > kMusicSettleToleranceSeconds) {
        await player.seek(_at(target));
      }
      if (thenPlay && _advancing && _covers(track, _playheadNow)) player.play();
    } finally {
      _lastAlignedAt[track.id] = _clock();
      _isSeeking[track.id] = false;
    }
  }

  static Duration _at(double seconds) => Duration(milliseconds: (seconds * 1000).round());

  Future<void> _performSeek(String id, MusicPlayer player, double targetSeconds) async {
    if (_lastSeekTarget[id] == targetSeconds) return;

    _isSeeking[id] = true;
    _lastSeekTarget[id] = targetSeconds;

    try {
      await player.seek(_at(targetSeconds));
    } finally {
      _isSeeking[id] = false;
      // Also clear target after seek so that if the user manually scrubs back to this exact spot, it still seeks.
      _lastSeekTarget.remove(id);
    }
  }

  void pauseAll() {
    _advancing = false;
    for (final player in _players.values) {
      if (player.playing) {
        unawaited(player.pause());
      }
    }
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
    _isSeeking.clear();
    _lastSeekTarget.clear();
    _lastAlignedAt.clear();
  }
}

extension on Stopwatch {
  Duration elapsedFunction() => elapsed;
}
