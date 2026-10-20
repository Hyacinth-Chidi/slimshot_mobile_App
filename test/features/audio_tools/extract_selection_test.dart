import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/audio_tools/audio_tools_service.dart';
import 'package:slimshotai/features/audio_tools/extract_selection.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';

/// The Extract sheet's two handles, and the track Done makes from them.
void main() {
  test('starts as the whole sound', () {
    final s = ExtractSelection.whole(12);
    expect((s.start, s.end, s.durationSeconds), (0.0, 12.0, 12.0));
  });

  test('the start never passes the end less the minimum', () {
    final s = ExtractSelection.whole(12).withEnd(5).withStart(4.99);
    expect(s.start, closeTo(5 - kMinClipDurationSeconds, 1e-9));
  });

  test('the end never passes the duration', () {
    expect(ExtractSelection.whole(12).withEnd(20).end, 12.0);
    expect(ExtractSelection.whole(12).withStart(-3).start, 0.0);
  });

  test('handles never cross', () {
    final s = ExtractSelection.whole(12).withStart(6).withEnd(2);
    expect(s.end, closeTo(6 + kMinClipDurationSeconds, 1e-9));
    expect(s.start, 6.0);
  });

  test('a sound shorter than the minimum stays whole', () {
    final s = ExtractSelection.whole(0.1).withStart(0.05).withEnd(0.06);
    expect((s.start, s.end), (0.0, 0.1));
  });

  test('lands at the playhead with the selection as its trim', () {
    final track = extractedTrack(
      id: 't1',
      sound: const ExtractedSound(path: '/d/a.m4a', durationSeconds: 12),
      selection: ExtractSelection.whole(12).withStart(2).withEnd(5),
      playhead: 7.5,
    );
    expect(track.id, 't1');
    expect(track.filePath, '/d/a.m4a');
    expect(track.sourceDuration, 12);
    expect(track.sourceStart, 2);
    expect(track.sourceEnd, 5);
    expect(track.timelineStart, 7.5);
    expect(track.isSoundEffect, isFalse);
  });
}
