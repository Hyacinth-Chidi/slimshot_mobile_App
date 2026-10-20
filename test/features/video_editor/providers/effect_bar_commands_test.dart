import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Adding, changing, copying and deleting effect bars — each one undo step,
/// and none for an action that changes nothing.
void main() {
  Duration sec(num s) => Duration(milliseconds: (s * 1000).round());

  VideoEditorNotifier notifier({
    double playhead = 2,
    List<EffectBarModel> bars = const [],
    List<TextOverlayModel> texts = const [],
    String? selectedEffectBarId,
  }) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          assets: const [
            MediaAsset(
              id: 'asset',
              path: '/v.mp4',
              type: MediaAssetType.video,
              durationSeconds: 60,
              width: 1920,
              height: 1080,
              hasAudio: true,
            ),
          ],
          segments: [
            VideoSegment(id: 'c1', assetId: 'asset', sourceStart: 0, sourceEnd: 10),
            VideoSegment(id: 'c2', assetId: 'asset', sourceStart: 20, sourceEnd: 30),
          ],
          currentPlaybackPosition: playhead,
          effectBars: bars,
          textOverlays: texts,
          selectedEffectBarId: selectedEffectBarId,
          currentMenuId: selectedEffectBarId == null ? 'root' : 'effect_bar',
        );

  EffectBarModel bar(String id, double start, double end, {int lane = 0}) =>
      EffectBarModel(
          id: id, effectId: 'vignette', start: start, end: end, laneIndex: lane);

  group('adding', () {
    test('lands at the playhead, three seconds, selected, one undo step', () {
      final n = notifier();
      final id = n.addEffectBar('blur');
      final added = n.state.effectBars.single;
      expect(added.id, id);
      expect((added.start, added.end, added.laneIndex), (2.0, 5.0, 0));
      expect(added.intensity.baseValue,
          videoEffectById('blur')!.defaultIntensity);
      expect(added.intensity.envelope, 'ramp_out');
      expect(n.state.selectedEffectBarId, id);
      expect(n.state.currentMenuId, 'effect_bar');
      n.undo();
      expect(n.state.effectBars, isEmpty);
      expect(n.state.canUndo, isFalse);
    });

    test('takes the first free lane at that time', () {
      final n = notifier(bars: [bar('x', 0, 4)]);
      n.addEffectBar('grain');
      expect(n.state.effectBars.last.laneIndex, 1);
    });

    test('an effect the catalog does not know adds nothing', () {
      final n = notifier();
      expect(n.addEffectBar('nope'), isNull);
      expect(n.state.effectBars, isEmpty);
      expect(n.state.canUndo, isFalse);
    });

    test('becomes the only selection', () {
      final n = notifier(texts: [
        TextOverlayModel(id: 't', text: 't', startTime: sec(0), endTime: sec(1)),
      ])
        ..selectTextOverlay('t');
      n.addEffectBar('blur');
      expect(n.state.selectedTextId, isNull);
    });
  });

  group('changing the effect', () {
    test('to the one it wears changes nothing', () {
      final n = notifier(bars: [bar('e', 1, 4)], selectedEffectBarId: 'e');
      n.setEffectBarEffect('vignette');
      expect(n.state.canUndo, isFalse);
    });

    test('to another drops the keyframes and takes the new defaults', () {
      final n = notifier(
        bars: [
          bar('e', 1, 4).copyWith(
            intensity: const AnimatableDouble(baseValue: 0.3, keyframes: [
              Keyframe(progress: 0, value: 0),
              Keyframe(progress: 1, value: 1),
            ]),
          ),
        ],
        selectedEffectBarId: 'e',
      );
      n.setEffectBarEffect('glow');
      final changed = n.state.effectBars.single;
      expect(changed.effectId, 'glow');
      expect(changed.intensity.keyframes, isEmpty);
      expect(changed.intensity.baseValue,
          videoEffectById('glow')!.defaultIntensity);
      expect(changed.intensity.envelope, 'throb');
      n.undo();
      expect(n.state.effectBars.single.effectId, 'vignette');
    });

    test('an unknown id changes nothing', () {
      final n = notifier(bars: [bar('e', 1, 4)], selectedEffectBarId: 'e');
      n.setEffectBarEffect('nope');
      expect(n.state.effectBars.single.effectId, 'vignette');
      expect(n.state.canUndo, isFalse);
    });
  });

  group('copying', () {
    test('goes straight after on its lane when there is room', () {
      final n = notifier(bars: [bar('e', 1, 4)], selectedEffectBarId: 'e');
      n.duplicateEffectBar();
      final copy = n.state.effectBars.last;
      expect(copy.id, isNot('e'));
      expect((copy.start, copy.end, copy.laneIndex), (4.0, 7.0, 0));
      expect(copy.effectId, 'vignette');
      expect(n.state.selectedEffectBarId, copy.id);
      n.undo();
      expect(n.state.effectBars.length, 1);
    });

    test('else on the nearest free lane below, at the same time', () {
      final n = notifier(
        bars: [bar('e', 1, 4), bar('next', 4, 6)],
        selectedEffectBarId: 'e',
      );
      n.duplicateEffectBar();
      final copy = n.state.effectBars.last;
      expect((copy.start, copy.end, copy.laneIndex), (1.0, 4.0, 1));
    });
  });

  test('deleting closes the lane and leaves the bar menu', () {
    final n = notifier(
      bars: [bar('a', 0, 3), bar('e', 0, 3, lane: 1), bar('b', 0, 3, lane: 2)],
      selectedEffectBarId: 'e',
    );
    n.deleteEffectBar();
    expect(n.state.effectBars.map((b) => b.id), ['a', 'b']);
    expect(n.state.effectBars.last.laneIndex, 1,
        reason: 'the empty lane closed');
    expect(n.state.selectedEffectBarId, isNull);
    expect(n.state.currentMenuId, 'root');
    n.undo();
    expect(n.state.effectBars.length, 3);
  });

  test('undo and redo never leave the selection naming a missing bar', () {
    final n = notifier();
    void check() {
      final id = n.state.selectedEffectBarId;
      if (id != null) {
        expect(n.state.effectBars.any((b) => b.id == id), isTrue);
      }
    }

    n.addEffectBar('blur');
    check();
    n.setEffectBarEffect('grain');
    check();
    n.deleteEffectBar();
    check();
    n.undo();
    check();
    n.undo();
    check();
    n.undo();
    check();
    n.redo();
    check();
  });

  test('selecting a bar clears every other selection, and the reverse', () {
    final n = notifier(
      bars: [bar('e', 1, 4)],
      texts: [
        TextOverlayModel(id: 't', text: 't', startTime: sec(0), endTime: sec(1)),
      ],
    )..selectTextOverlay('t');
    n.selectEffectBar('e');
    expect(n.state.selectedTextId, isNull);
    expect(n.state.selectedEffectBarId, 'e');
    expect(n.state.currentMenuId, 'effect_bar');
    n.selectTextOverlay('t');
    expect(n.state.selectedEffectBarId, isNull);
  });

  test('bars live in timeline time: clip edits leave them where they are', () {
    final n = notifier(bars: [bar('e', 12, 15)]);
    n.selectSegment('c1');
    n.deleteSelectedSegment();
    final kept = n.state.effectBars.single;
    expect((kept.start, kept.end), (12.0, 15.0));
  });
}
