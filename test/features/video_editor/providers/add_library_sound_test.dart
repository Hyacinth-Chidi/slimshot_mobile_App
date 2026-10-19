import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/sound_library/data/sound_library.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A sound from the library goes on the timeline as an ordinary audio track.
void main() {
  final whoosh = LibrarySound(
    id: 'cm2a1',
    title: 'Whoosh',
    filePath: '/docs/sound_library/cm2a1.mp3',
    durationMs: 1500,
    downloadedAt: DateTime(2026, 10, 19),
  );

  VideoEditorNotifier notifierAt(double playhead, {List<AudioTrackModel> audio = const []}) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(currentPlaybackPosition: playhead, audioTracks: audio);

  test('lands at the playhead with its full length', () {
    final notifier = notifierAt(4.2)..addLibrarySound(whoosh);
    final track = notifier.state.audioTracks.single;
    expect(track.filePath, '/docs/sound_library/cm2a1.mp3');
    expect(track.timelineStart, 4.2);
    expect(track.sourceStart, 0);
    expect(track.sourceEnd, 1.5);
    expect(track.sourceDuration, 1.5);
    expect(track.volume, 1.0);
  });

  test('takes a free lane when the playhead\'s lane is busy', () {
    const music = AudioTrackModel(
      id: 'music',
      filePath: '/m.mp3',
      sourceDuration: 30,
      sourceStart: 0,
      sourceEnd: 30,
      timelineStart: 0,
    );
    final notifier = notifierAt(4.2, audio: [music])..addLibrarySound(whoosh);
    final added = notifier.state.audioTracks.firstWhere((t) => t.id != 'music');
    expect(added.laneIndex, isNot(music.laneIndex));
  });

  test('is one undo step and selected', () {
    final notifier = notifierAt(1)..addLibrarySound(whoosh);
    final added = notifier.state.audioTracks.single;
    expect(notifier.state.selectedAudioId, added.id);
    notifier.undo();
    expect(notifier.state.audioTracks, isEmpty);
  });

  test('two adds of one sound are two tracks', () {
    final notifier = notifierAt(1)
      ..addLibrarySound(whoosh)
      ..addLibrarySound(whoosh);
    final ids = notifier.state.audioTracks.map((t) => t.id).toSet();
    expect(ids.length, 2);
  });
}
