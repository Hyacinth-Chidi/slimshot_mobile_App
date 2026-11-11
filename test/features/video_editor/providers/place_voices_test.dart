import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/speech/voice_clip.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// What Generate's voices do to the timeline: each lands at its text's start
/// as a voice clip, the whole generation one undo step.
void main() {
  const music = AudioTrackModel(
    id: 'music',
    filePath: '/m.mp3',
    sourceDuration: 30,
    sourceStart: 0,
    sourceEnd: 30,
    timelineStart: 0,
  );

  AudioTrackModel voiceOf(String textId, {required String id, double start = 0}) =>
      AudioTrackModel(
        id: id,
        filePath: '/d/audio/voice_${textId}_1.mp3',
        sourceDuration: 2,
        sourceStart: 0,
        sourceEnd: 2,
        timelineStart: start,
        laneIndex: 1,
        isVoice: true,
        voiceForTextId: textId,
      );

  VideoEditorNotifier editor({
    List<AudioTrackModel> audio = const [],
    List<TextOverlayModel> texts = const [],
  }) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(audioTracks: audio, textOverlays: texts);

  List<AudioTrackModel> voicesIn(VideoEditorNotifier n) =>
      [for (final t in n.state.audioTracks) if (t.isVoice) t];

  test('places every voice at its captured start on the first free lane, '
      'as one undo step', () {
    final n = editor(audio: [music]);

    n.placeVoices(const [
      VoiceClip(textId: 'a', filePath: '/d/audio/voice_a_1.mp3', durationSeconds: 2.448, startSeconds: 1),
      VoiceClip(textId: 'b', filePath: '/d/audio/voice_b_1.mp3', durationSeconds: 3.072, startSeconds: 6),
    ]);

    final placed = voicesIn(n);
    expect(
      [
        for (final t in placed)
          (t.voiceForTextId, t.filePath, t.timelineStart, t.sourceStart, t.sourceEnd, t.sourceDuration)
      ],
      [
        ('a', '/d/audio/voice_a_1.mp3', 1.0, 0.0, 2.448, 2.448),
        ('b', '/d/audio/voice_b_1.mp3', 6.0, 0.0, 3.072, 3.072),
      ],
    );
    // The music holds lane 0 throughout; the two voices do not overlap, so
    // they share the first lane free of it.
    expect([for (final t in placed) t.laneIndex], [1, 1]);
    expect(placed.map((t) => t.id).toSet(), hasLength(2));

    n.undo();
    expect(n.state.audioTracks, [music]);
  });

  test('places at the start captured with the request, even when the text has gone',
      () {
    // The text moved to 3s while its voice was made, and another was deleted.
    final n = editor(texts: [
      TextOverlayModel(
        id: 'a',
        text: 'Moved',
        startTime: const Duration(seconds: 3),
        endTime: const Duration(seconds: 6),
      ),
    ]);

    n.placeVoices(const [
      VoiceClip(textId: 'a', filePath: '/a.mp3', durationSeconds: 1, startSeconds: 1),
      VoiceClip(textId: 'gone', filePath: '/g.mp3', durationSeconds: 1, startSeconds: 7.5),
    ]);

    expect(
      [for (final t in voicesIn(n)) (t.voiceForTextId, t.timelineStart)],
      [('a', 1.0), ('gone', 7.5)],
    );
  });

  test('re-voicing replaces the old clip, one undo step', () {
    final old = voiceOf('a', id: 'old', start: 1);
    final other = voiceOf('b', id: 'other', start: 5);
    final n = editor(audio: [music, old, other])
      ..state = editor().state.copyWith(
            audioTracks: [music, old, other],
            selectedAudioId: 'old',
          );

    n.placeVoices(const [
      VoiceClip(textId: 'a', filePath: '/d/audio/voice_a_2.mp3', durationSeconds: 1.5, startSeconds: 1),
    ]);

    final ofA = [for (final t in n.state.audioTracks) if (t.voiceForTextId == 'a') t];
    expect(ofA.single.filePath, '/d/audio/voice_a_2.mp3');
    expect(n.state.audioTracks.any((t) => t.id == 'old'), isFalse);
    expect(n.state.audioTracks.any((t) => t.id == 'other'), isTrue);
    expect(n.state.audioTracks.any((t) => t.id == 'music'), isTrue);
    // The replaced clip was selected: nothing points at a clip that is gone.
    expect(n.state.selectedAudioId, isNull);

    n.undo();
    expect(n.state.audioTracks.map((t) => t.id), ['music', 'old', 'other']);
  });

  test('selects the voice of the text the sheet was opened from, else nothing',
      () {
    final n = editor()..state = editor().state.copyWith(selectedTextId: 'b');
    n.placeVoices(
      const [
        VoiceClip(textId: 'a', filePath: '/a.mp3', durationSeconds: 1, startSeconds: 0),
        VoiceClip(textId: 'b', filePath: '/b.mp3', durationSeconds: 1, startSeconds: 2),
      ],
      selectTextId: 'b',
    );
    final ofB = n.state.audioTracks.singleWhere((t) => t.voiceForTextId == 'b');
    expect(n.state.selectedAudioId, ofB.id);
    expect(n.state.selectedTextId, isNull);

    // Apply to all from a caption: the caption has no voice, so the
    // selection is left as it was.
    final m = editor()..state = editor().state.copyWith(selectedTextId: 'cap');
    m.placeVoices(
      const [
        VoiceClip(textId: 'a', filePath: '/a.mp3', durationSeconds: 1, startSeconds: 0),
      ],
      selectTextId: 'cap',
    );
    expect(m.state.selectedAudioId, isNull);
    expect(m.state.selectedTextId, 'cap');
  });

  test('no voices changes nothing and takes no undo step', () {
    final n = editor(audio: [music])..placeVoices(const []);
    expect(n.state.audioTracks, [music]);
    expect(n.state.canUndo, isFalse);
  });

  test('a copy of a voice is the user\'s: kept when its text is voiced again',
      () {
    final n = editor(audio: [voiceOf('a', id: 'v', start: 1)])
      ..duplicateAudioTrack('v');
    final copy = n.state.audioTracks.singleWhere((t) => t.id != 'v');
    expect((copy.isVoice, copy.voiceForTextId), (true, null));

    n.placeVoices(const [
      VoiceClip(textId: 'a', filePath: '/new.mp3', durationSeconds: 1, startSeconds: 1),
    ]);
    expect(n.state.audioTracks.any((t) => t.id == copy.id), isTrue);
    expect(n.state.audioTracks.any((t) => t.id == 'v'), isFalse);
  });
}
