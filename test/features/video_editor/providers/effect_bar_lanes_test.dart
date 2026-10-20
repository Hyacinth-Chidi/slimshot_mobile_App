import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/lane_layout.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Effect bars share the lanes with text, photos, video overlays and audio,
/// under the same two rules: nothing overlaps on a lane, and no lane is left
/// empty.
void main() {
  Duration sec(num s) => Duration(milliseconds: (s * 1000).round());

  EffectBarModel bar(String id, int lane, double start, double end) =>
      EffectBarModel(
          id: id, effectId: 'blur', start: start, end: end, laneIndex: lane);

  VideoEditorNotifier notifier({
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
            VideoSegment(id: 'c', assetId: 'asset', sourceStart: 0, sourceEnd: 20),
          ],
          effectBars: bars,
          textOverlays: texts,
          selectedEffectBarId: selectedEffectBarId,
        );

  EffectBarModel barIn(VideoEditorNotifier n, String id) =>
      n.state.effectBars.firstWhere((b) => b.id == id);

  test('bars are lane spans, and a new item steps past one', () {
    final spans = laneSpansOf(
      texts: const [],
      images: const [],
      videos: const [],
      audios: const [],
      effects: [bar('e', 0, 2, 5)],
    );
    expect(spans.single.id, 'e');
    expect((spans.single.start, spans.single.end, spans.single.lane), (2.0, 5.0, 0));
    expect(firstFreeLane(spans, 3, 4), 1);
  });

  test('a bar moves under the lane rules', () {
    final n = notifier(
      bars: [bar('e', 0, 2, 5)],
      texts: [
        TextOverlayModel(
            id: 't', text: 't', startTime: sec(2), endTime: sec(5), laneIndex: 1),
      ],
    );
    n.moveLaneItem('e', start: 8, targetLane: 0);
    expect((barIn(n, 'e').start, barIn(n, 'e').end), (8.0, 11.0));
    // Dropped onto the text it overlaps: the two trade lanes.
    n.moveLaneItem('e', start: 2, targetLane: 1);
    expect(barIn(n, 'e').laneIndex, 1);
    expect(n.state.textOverlays.single.laneIndex, 0);
  });

  test('a bar trims, each edge stopping at its lane neighbour', () {
    final n = notifier(bars: [bar('a', 0, 2, 5), bar('b', 0, 6, 9)]);
    n.trimLaneItem('a', start: 2, end: 8);
    expect(barIn(n, 'a').end, 6.0);
    n.trimLaneItem('b', start: 7, end: 9);
    expect((barIn(n, 'b').start, barIn(n, 'b').end), (7.0, 9.0));
  });

  test('selecting anything else clears the bar selection', () {
    final n = notifier(
      bars: [bar('e', 0, 2, 5)],
      texts: [TextOverlayModel(id: 't', text: 't', startTime: sec(0), endTime: sec(1))],
      selectedEffectBarId: 'e',
    );
    n.selectTextOverlay('t');
    expect(n.state.selectedEffectBarId, isNull);
    n.state = n.state.copyWith(selectedEffectBarId: 'e');
    n.deselectAll();
    expect(n.state.selectedEffectBarId, isNull);
  });

  group('the draft', () {
    DraftProject draft({List<Map<String, dynamic>> effectBars = const []}) =>
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
          segments: [
            VideoSegment(id: 'c', assetId: 'asset', sourceStart: 0, sourceEnd: 20)
                .toJson(),
          ],
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

    test('a draft without bars writes no effectBars key', () {
      expect(draft().toJson().containsKey('effectBars'), isFalse);
      expect(DraftProject.fromJson(draft().toJson()).effectBars, isEmpty);
    });

    test('bars survive a save and a load', () async {
      final saved = DraftProject.fromJson(
          draft(effectBars: [bar('e', 0, 2, 5).toJson()]).toJson());
      final n = VideoEditorNotifier(VideoEditorService());
      await n.loadDraft(saved, rerenderMissingProxies: false);
      final loaded = n.state.effectBars.single;
      expect((loaded.id, loaded.effectId, loaded.start, loaded.end), ('e', 'blur', 2.0, 5.0));
    });
  });
}
