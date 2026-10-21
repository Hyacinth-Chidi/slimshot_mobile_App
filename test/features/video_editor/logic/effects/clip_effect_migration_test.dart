import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/effects/clip_effect_migration.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/lane_layout.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A draft saved before the effects track carries each effect on its clip.
/// On load each becomes a bar covering exactly where it showed.
void main() {
  VideoSegment clip(
    String id,
    double length, {
    String? transition,
    double? transitionDuration,
  }) =>
      VideoSegment(
        id: id,
        assetId: 'asset',
        sourceStart: 0,
        sourceEnd: length,
        transitionType: transition,
        transitionDuration: transitionDuration,
      );

  /// A clip as an old draft held it: the clip's JSON plus its effect.
  Map<String, dynamic> raw(VideoSegment s, String? effectId,
          {Object? intensity = 0.6}) =>
      {
        ...s.toJson(),
        if (effectId != null) 'effectId': effectId,
        if (effectId != null) 'effectIntensity': intensity,
      };

  List<EffectBarModel> migrate(
    List<VideoSegment> segments,
    List<String?> effects, {
    List<LaneSpan> occupied = const [],
    List<Object?>? intensities,
  }) =>
      migrateClipEffects(
        rawSegments: [
          for (var i = 0; i < segments.length; i++)
            raw(segments[i], effects[i],
                intensity: intensities == null ? 0.6 : intensities[i]),
        ],
        segments: segments,
        occupied: occupied,
      );

  test('a lone clip with an effect becomes a bar over the clip', () {
    final bars = migrate([clip('a', 5)], ['glow']);
    final b = bars.single;
    expect((b.effectId, b.start, b.end, b.laneIndex), ('glow', 0.0, 5.0, 0));
    expect(b.intensity.baseValue, 0.6);
  });

  test('a clip entered through a transition starts its bar at the window end',
      () {
    // Inside the window the outgoing clip's effect showed, not this one's.
    final bars = migrate(
      [clip('a', 5, transition: 'dissolve', transitionDuration: 1), clip('b', 5)],
      [null, 'vignette'],
    );
    final b = bars.single;
    expect(b.start, closeTo(5.0, 1e-9));
    expect(b.end, closeTo(9.0, 1e-9));
  });

  test('keyframes land on the same instants of the timeline', () {
    // Clip b runs 8..18 (entered through a 2s window), so its bar is 10..18.
    // A keyframe at clip progress 0 (instant 8) falls before the bar and is
    // dropped; one is pinned at the bar's start with the value there.
    const shaped = AnimatableDouble(baseValue: 0.5, keyframes: [
      Keyframe(progress: 0, value: 0),
      Keyframe(progress: 1, value: 1),
    ]);
    final bars = migrate(
      [clip('a', 10, transition: 'dissolve', transitionDuration: 2), clip('b', 10)],
      [null, 'blur'],
      intensities: [null, shaped.toJson()],
    );
    final b = bars.single;
    expect((b.start, b.end), (10.0, 18.0));
    final kfs = b.intensity.keyframes;
    expect(kfs.length, 2);
    expect(kfs.first.progress, closeTo(0, 1e-9));
    expect(kfs.first.value, closeTo(0.2, 1e-9));
    expect(kfs.last.progress, closeTo(1, 1e-9));
    expect(kfs.last.value, closeTo(1, 1e-9));
  });

  test('a keyframe inside the bar keeps its instant', () {
    const shaped = AnimatableDouble(baseValue: 0.5, keyframes: [
      Keyframe(progress: 0.5, value: 0.9),
    ]);
    final bars = migrate([clip('a', 4)], ['blur'],
        intensities: [shaped.toJson()]);
    expect(bars.single.intensity.keyframes.single.progress, closeTo(0.5, 1e-9));
  });

  test('two effected clips side by side become two bars on one lane', () {
    final bars = migrate([clip('a', 5), clip('b', 3)], ['blur', 'grain']);
    expect(bars.map((b) => (b.start, b.end, b.laneIndex)),
        [(0.0, 5.0, 0), (5.0, 8.0, 0)]);
  });

  test('a bar steps past what is already on the lanes', () {
    final bars = migrate(
      [clip('a', 5)],
      ['blur'],
      occupied: const [LaneSpan(id: 't', lane: 0, start: 1, end: 2)],
    );
    expect(bars.single.laneIndex, 1);
  });

  test('a clip without an effect makes no bar', () {
    expect(migrate([clip('a', 5)], [null]), isEmpty);
  });

  test('an effect this build does not know is carried as written', () {
    expect(migrate([clip('a', 5)], ['from_the_future']).single.effectId,
        'from_the_future');
  });

  test('a clip no longer writes or reads an effect', () {
    final json = raw(clip('a', 5), 'glow');
    final written = VideoSegment.fromJson(json).toJson();
    expect(written.containsKey('effectId'), isFalse);
    expect(written.containsKey('effectIntensity'), isFalse);
  });

  group('loading a draft', () {
    DraftProject draft({
      required List<Map<String, dynamic>> segments,
      List<Map<String, dynamic>> effectBars = const [],
    }) =>
        DraftProject(
          id: 'd',
          sourceVideoPath: '/v.mp4',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          durationSeconds: 20,
          assets: const [
            {
              'id': 'asset',
              'path': '/v.mp4',
              'type': 'video',
              'durationSeconds': 60.0,
              'width': 1920,
              'height': 1080,
              'hasAudio': true,
            },
          ],
          segments: segments,
          textOverlays: const [],
          imageOverlays: const [],
          videoOverlays: const [],
          audioTracks: const [],
          effectBars: effectBars,
          selectedRatioName: 'ratio9x16',
          customCropRect: const [0, 0, 1, 1],
          videoScale: 1,
          videoPanX: 0,
          videoPanY: 0,
          filterIntensity: 1,
          backgroundType: 'black',
          backgroundColorValue: 0xFF000000,
          backgroundBlurIntensity: 20,
          isMuted: false,
        );

    test('converts clip effects and keeps the bars it already has', () async {
      final n = VideoEditorNotifier(VideoEditorService());
      await n.loadDraft(
        draft(
          segments: [raw(clip('a', 5), 'glow')],
          effectBars: [
            const EffectBarModel(
                    id: 'kept', effectId: 'grain', start: 1, end: 3)
                .toJson(),
          ],
        ),
        rerenderMissingProxies: false,
      );
      final bars = n.state.effectBars;
      expect(bars.map((b) => b.effectId).toSet(), {'grain', 'glow'});
      final converted = bars.firstWhere((b) => b.effectId == 'glow');
      expect(converted.laneIndex, isNot(bars.firstWhere((b) => b.id == 'kept').laneIndex),
          reason: 'never on top of a bar that was already there');
    });

    test('a draft saved after the conversion converts nothing more', () async {
      final n = VideoEditorNotifier(VideoEditorService());
      await n.loadDraft(draft(segments: [raw(clip('a', 5), 'glow')]),
          rerenderMissingProxies: false);
      final resaved = draft(
        segments: [for (final s in n.state.segments) s.toJson()],
        effectBars: [for (final b in n.state.effectBars) b.toJson()],
      );
      final again = VideoEditorNotifier(VideoEditorService());
      await again.loadDraft(resaved, rerenderMissingProxies: false);
      expect(again.state.effectBars.length, 1);
    });
  });
}
