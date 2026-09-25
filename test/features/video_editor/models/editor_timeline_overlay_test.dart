import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';

void main() {
  EditorTimelineOverlay baseOverlay({
    String kind = 'image',
    List<EditorTimelineGlyph>? glyphs,
  }) {
    return EditorTimelineOverlay(
      id: 'o1',
      kind: kind,
      path: '/tmp/a.png',
      centerX: const AnimatableDouble(baseValue: 0.5),
      centerY: const AnimatableDouble(baseValue: 0.5),
      boxWidth: 0.4,
      boxHeight: 0.4,
      scale: const AnimatableDouble(baseValue: 1),
      rotation: const AnimatableDouble(baseValue: 0),
      opacity: const AnimatableDouble(baseValue: 1),
      startSeconds: 0,
      endSeconds: 2,
      laneIndex: 0,
      slideOffsetX: 0,
      slideOffsetY: 0,
      glyphs: glyphs,
    );
  }

  group('EditorTimelineOverlay glyphs', () {
    test('an image overlay serialises no glyph array', () {
      expect(baseOverlay().toJson()['glyphs'], isNull);
    });

    test('a text overlay serialises its glyphs in order', () {
      final json = baseOverlay(
        kind: 'text',
        glyphs: const [
          EditorTimelineGlyph(
            atlasLeft: 0,
            atlasTop: 0,
            atlasRight: 0.5,
            atlasBottom: 1,
            boxLeft: 0.1,
            boxTop: 0.2,
            boxRight: 0.4,
            boxBottom: 0.8,
            srcLeft: 0.05,
            srcTop: 0.1,
            srcRight: 0.95,
            srcBottom: 0.9,
          ),
          EditorTimelineGlyph(
            atlasLeft: 0.5,
            atlasTop: 0,
            atlasRight: 1,
            atlasBottom: 1,
            boxLeft: 0.5,
            boxTop: 0.2,
            boxRight: 0.9,
            boxBottom: 0.8,
            srcLeft: 0.1,
            srcTop: 0.15,
            srcRight: 0.9,
            srcBottom: 0.85,
          ),
        ],
      ).toJson();

      final glyphs = json['glyphs'] as List;
      expect(glyphs.length, 2);
      expect((glyphs.first as Map)['atlasRight'], 0.5);
      expect((glyphs.last as Map)['boxLeft'], 0.5);
    });

    test('background rect and radius round-trip', () {
      final json = const EditorTimelineOverlay(
        id: 'o1',
        kind: 'text',
        path: '/tmp/a.png',
        centerX: AnimatableDouble(baseValue: 0.5),
        centerY: AnimatableDouble(baseValue: 0.5),
        boxWidth: 0.4,
        boxHeight: 0.4,
        scale: AnimatableDouble(baseValue: 1),
        rotation: AnimatableDouble(baseValue: 0),
        opacity: AnimatableDouble(baseValue: 1),
        startSeconds: 0,
        endSeconds: 2,
        laneIndex: 0,
        slideOffsetX: 0,
        slideOffsetY: 0,
        backgroundLeft: 0.05,
        backgroundTop: 0.1,
        backgroundRight: 0.95,
        backgroundBottom: 0.9,
        backgroundRadius: 0.02,
      ).toJson();

      expect(json['backgroundLeft'], 0.05);
      expect(json['backgroundBottom'], 0.9);
      expect(json['backgroundRadius'], 0.02);
    });

    test('a text overlay serialises all twelve glyph rect keys', () {
      final json = baseOverlay(
        kind: 'text',
        glyphs: const [
          EditorTimelineGlyph(
            atlasLeft: 0,
            atlasTop: 0,
            atlasRight: 0.5,
            atlasBottom: 1,
            boxLeft: 0.1,
            boxTop: 0.2,
            boxRight: 0.4,
            boxBottom: 0.8,
            srcLeft: 0.05,
            srcTop: 0.1,
            srcRight: 0.95,
            srcBottom: 0.9,
          ),
        ],
      ).toJson();

      final glyph = (json['glyphs'] as List).first as Map;
      expect(
        glyph.keys.toSet(),
        {
          'atlasLeft',
          'atlasTop',
          'atlasRight',
          'atlasBottom',
          'boxLeft',
          'boxTop',
          'boxRight',
          'boxBottom',
          'srcLeft',
          'srcTop',
          'srcRight',
          'srcBottom',
        },
      );
    });
  });
}
