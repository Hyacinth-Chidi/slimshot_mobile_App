import 'package:just_audio/just_audio.dart';
import '../models/audio_track_model.dart';

class AudioPlayerManager {
  final Map<String, AudioPlayer> _players = {};
  final Map<String, bool> _isSeeking = {};
  final Map<String, double> _lastSeekTarget = {};

  Future<void> syncTracks(List<AudioTrackModel> tracks) async {
    final currentIds = tracks.map((t) => t.id).toSet();
    
    // Remove unused players
    final toRemove = _players.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in toRemove) {
      await _players[id]?.dispose();
      _players.remove(id);
      _isSeeking.remove(id);
      _lastSeekTarget.remove(id);
    }

    // Add new players
    for (final track in tracks) {
      if (!_players.containsKey(track.id)) {
        final player = AudioPlayer();
        await player.setFilePath(track.filePath);
        _players[track.id] = player;
      }
      // Update volume
      _players[track.id]?.setVolume(track.volume);
    }
  }

  void setVolumeSync(String id, double volume) {
    _players[id]?.setVolume(volume);
  }

  void seekAndPlaySync(double globalPosition, List<AudioTrackModel> tracks, bool isPlaying) {
    for (final track in tracks) {
      final player = _players[track.id];
      if (player == null) continue;
      
      if (_isSeeking[track.id] == true) continue;

      // Check if global playhead is within this audio track's timeline bounds
      if (globalPosition >= track.timelineStart && globalPosition < track.timelineEnd) {
        // Calculate where we should be in the audio source
        final offsetInTrack = globalPosition - track.timelineStart;
        final targetSourcePosition = track.sourceStart + offsetInTrack;

        if (!player.playing && isPlaying) {
          // About to start playing, so sync the position exactly
          _performSeek(track.id, player, targetSourcePosition);
          player.play();
        } else if (player.playing && !isPlaying) {
          player.pause();
        } else if (!isPlaying) {
          // Scrubbing while paused
          final currentPos = player.position.inMilliseconds / 1000.0;
          if ((currentPos - targetSourcePosition).abs() > 0.1) {
            _performSeek(track.id, player, targetSourcePosition);
          }
        } else if (isPlaying) {
          // It's playing. Only seek if massively out of sync (e.g. jumped playhead)
          final currentPos = player.position.inMilliseconds / 1000.0;
          if ((currentPos - targetSourcePosition).abs() > 0.5) {
            _performSeek(track.id, player, targetSourcePosition);
          }
        }
      } else {
        // Outside the track bounds, pause and seek to start for readiness
        if (player.playing) {
          player.pause();
        }
        
        final currentPos = player.position.inMilliseconds / 1000.0;
        if ((currentPos - track.sourceStart).abs() > 0.1) {
          _performSeek(track.id, player, track.sourceStart);
        }
      }
    }
  }

  Future<void> _performSeek(String id, AudioPlayer player, double targetSeconds) async {
    if (_lastSeekTarget[id] == targetSeconds) return;
    
    _isSeeking[id] = true;
    _lastSeekTarget[id] = targetSeconds;
    
    try {
      await player.seek(Duration(milliseconds: (targetSeconds * 1000).round()));
    } finally {
      _isSeeking[id] = false;
      // Also clear target after seek so that if the user manually scrubs back to this exact spot, it still seeks.
      _lastSeekTarget.remove(id);
    }
  }

  void pauseAll() {
    for (final player in _players.values) {
      if (player.playing) {
        player.pause();
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
  }
}
