import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/features/video_editor/logic/color/color_adjustments.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/logic/filter_presets.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Adjust at both levels, riding the grade pipeline that already exists.
///
/// A clip's adjustments compose **into its own colour matrix**, after its
/// filter, and travel as the one `colorMatrix` the clip already sends — so the
/// engine grades per lane before a transition blends, exactly as a clip filter
/// does, and no Kotlin changed. The project's compose into the canvas look the
/// same way. Unlike filters the two levels may coexist: an adjustment applied
/// twice is the user's intent; a filter applied twice is not.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 60,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );

  VideoSegment clip(String id, {double start = 0, double end = 10}) =>
      VideoSegment(id: id, assetId: 'a', sourceStart: start, sourceEnd: end);

  VideoEditorNotifier notifierWith(List<VideoSegment> segments,
      {String? selected, double position = 0}) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        assets: const [asset],
        segments: segments,
        selectedSegmentId: selected,
        isClipSelected: selected != null,
        currentPlaybackPosition: position,
      );
  }

  const warm = ColorAdjustments(temperature: 0.6, brightness: 0.2);

  void expectMatrix(List<double>? actual, List<double> expected) {
    expect(actual, isNotNull);
    for (var i = 0; i < 20; i++) {
      expect(actual![i], closeTo(expected[i], 1e-9), reason: 'index $i');
    }
  }

  group('the clip model', () {
    test('defaults to none and writes nothing for it', () {
      final s = clip('a');
      expect(s.adjustments, ColorAdjustments.none);
      expect(s.toJson().containsKey('adjustments'), isFalse);
      expect(s.colorMatrix, isNull);
    });

    test('round-trips through json', () {
      final s = clip('a').copyWith(adjustments: warm);
      final restored = VideoSegment.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(restored.adjustments, warm);
    });

    test('adjustments alone are the clip\'s matrix', () {
      final s = clip('a').copyWith(adjustments: warm);
      expectMatrix(s.colorMatrix, warm.matrix);
    });

    test('with a filter, the adjustments apply after the filter', () {
      final preset = FilterPresets.allPresets.first;
      final s = clip('a').copyWith(filterId: preset.id, adjustments: warm);
      expectMatrix(
        s.colorMatrix,
        composeColorMatrices(warm.matrix, preset.getInterpolatedMatrix(1.0)),
      );
    });
  });

  group('the notifier', () {
    test('writes the selected clip, one undo step', () {
      final n = notifierWith([clip('a')], selected: 'a');
      n.setClipAdjustments(warm);
      expect(n.state.segments.single.adjustments, warm);
      n.undo();
      expect(n.state.segments.single.adjustments, ColorAdjustments.none);
    });

    test('a live write can skip the snapshot, for one step per drag', () {
      final n = notifierWith([clip('a')], selected: 'a');
      n.saveStateForUndo();
      n.setClipAdjustments(const ColorAdjustments(brightness: 0.1),
          takeUndoSnapshot: false);
      n.setClipAdjustments(warm, takeUndoSnapshot: false);
      n.undo();
      expect(n.state.segments.single.adjustments, ColorAdjustments.none);
    });

    test('writes the project, one undo step', () {
      final n = notifierWith([clip('a')]);
      n.setProjectAdjustments(warm);
      expect(n.state.adjustments, warm);
      n.undo();
      expect(n.state.adjustments, ColorAdjustments.none);
    });

    test('a split carries the clip\'s adjustments to both halves', () {
      final n = notifierWith([clip('a')], selected: 'a', position: 5.0);
      n.setClipAdjustments(warm);
      n.splitAtPosition(5.0);
      for (final s in n.state.segments) {
        expect(s.adjustments, warm, reason: s.id);
      }
    });
  });

  group('the timeline contract', () {
    const composer = VideoEditorTimelineComposer();

    test('a clip\'s adjustments reach the engine as its colour matrix', () {
      final timeline = composer.compose(
        notifierWith([clip('a').copyWith(adjustments: warm)]).state,
      );
      expectMatrix(timeline.videoClips.single.colorMatrix, warm.matrix);
    });

    test('the project\'s adjustments reach the canvas look, filter or not', () {
      final state = notifierWith([clip('a')]).state.copyWith(adjustments: warm);
      final timeline = composer.compose(state);
      expectMatrix(timeline.canvas.colorMatrix, warm.matrix);
    });

    test('with a project filter, adjustments apply after it', () {
      final preset = FilterPresets.allPresets.first;
      final state = notifierWith([clip('a')]).state.copyWith(
            selectedFilter: preset,
            filterIntensity: 0.5,
            adjustments: warm,
          );
      final timeline = composer.compose(state);
      expectMatrix(
        timeline.canvas.colorMatrix,
        composeColorMatrices(warm.matrix, preset.getInterpolatedMatrix(0.5)),
      );
    });

    test('differently adjusted neighbours are not merged for playback', () {
      final timeline = composer.compose(notifierWith([
        clip('a', start: 0, end: 4).copyWith(adjustments: warm),
        clip('b', start: 4, end: 8),
      ]).state);
      expect(timeline.playbackClips, hasLength(2));
    });
  });

  group('the draft', () {
    test('persists the project\'s adjustments, and omits none', () {
      DraftProject draft({ColorAdjustments adjustments = ColorAdjustments.none}) =>
          DraftProject(
            id: 'd',
            sourceVideoPath: '/v.mp4',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            durationSeconds: 1,
            segments: const [],
            textOverlays: const [],
            imageOverlays: const [],
            videoOverlays: const [],
            audioTracks: const [],
            selectedRatioName: 'ratio9x16',
            customCropRect: const [0, 0, 1, 1],
            videoScale: 1,
            videoPanX: 0,
            videoPanY: 0,
            filterIntensity: 1,
            backgroundType: 'black',
            backgroundColorValue: 0xFF000000,
            backgroundBlurIntensity: 20,
            adjustments: adjustments,
            isMuted: false,
          );

      final json = draft(adjustments: warm).toJson();
      expect(DraftProject.fromJson(json).adjustments, warm);
      expect(draft().toJson().containsKey('adjustments'), isFalse);
      expect(DraftProject.fromJson(draft().toJson()).adjustments,
          ColorAdjustments.none);
    });
  });
}
