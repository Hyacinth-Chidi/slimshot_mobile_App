import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/services/audio_player_manager.dart';

/// While a voiceover is recorded the imported music is silenced with the
/// rest of the preview — a monitor mute, never the track's own volume.
void main() {
  const track = AudioTrackModel(
    id: 'm',
    filePath: '/m.mp3',
    sourceDuration: 30,
    sourceStart: 0,
    sourceEnd: 30,
    timelineStart: 0,
    volume: 0.8,
  );

  test('monitor mute silences every track and lifting it restores their volumes', () {
    final manager = AudioPlayerManager();
    expect(manager.effectiveVolume(track), 0.8);
    manager.monitorMuted = true;
    expect(manager.effectiveVolume(track), 0.0);
    manager.monitorMuted = false;
    expect(manager.effectiveVolume(track), 0.8);
    expect(track.volume, 0.8, reason: 'the track itself is never touched');
  });
}
