import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_bar_placement.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';

/// Where a new effect bar lands: at the playhead, 3 seconds, inside the project.
void main() {
  ({double start, double end}) span(double playhead, double end) =>
      newEffectBarSpan(playhead: playhead, projectEnd: end);

  test('at the playhead, three seconds long', () {
    expect(kDefaultEffectBarSeconds, 3.0);
    expect(span(2, 20), (start: 2.0, end: 5.0));
  });

  test('ends at the project\'s end when three seconds do not fit', () {
    expect(span(18.5, 20), (start: 18.5, end: 20.0));
  });

  test('starts earlier rather than fall below the minimum', () {
    expect(span(19.99, 20).start, closeTo(20 - kMinClipDurationSeconds, 1e-9));
    expect(span(19.99, 20).end, 20.0);
    expect(span(25, 20).start, closeTo(20 - kMinClipDurationSeconds, 1e-9));
  });

  test('a project shorter than the minimum still gets a bar of the minimum', () {
    final s = span(0, 0.1);
    expect(s.start, 0.0);
    expect(s.end - s.start, closeTo(kMinClipDurationSeconds, 1e-9));
  });
}
