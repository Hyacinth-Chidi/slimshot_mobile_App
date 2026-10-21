import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_bar_placement.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_preview_layout.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// An effect tile's atlas: where each frame sits, which frame a loop phase
/// shows, and the bar it is drawn from — the one a tap would add.
void main() {
  group('which frame the loop shows', () {
    test('the plain beat', () {
      expect(effectPreviewFrameAt(0.0), 0);
      expect(effectPreviewFrameAt(0.19), 0);
    });

    test('frames advance at 15 fps after the beat', () {
      expect(effectPreviewFrameAt(0.2), 1);
      expect(effectPreviewFrameAt((0.4 + 1 / 15 + 0.001) / 2.0), 2);
    });

    test('the loop ends on the last frame', () {
      expect(effectPreviewFrameAt(0.999), 24);
      expect(effectPreviewFrameAt(1.0), 24);
    });
  });

  group('where each frame sits', () {
    test('cells are row-major and inset by a pixel', () {
      expect(effectPreviewCellRect(0), const Rect.fromLTRB(1, 1, 159, 143));
      expect(effectPreviewCellRect(6), const Rect.fromLTRB(161, 145, 319, 287));
      expect(effectPreviewCellRect(24).right, 799);
      expect(effectPreviewCellRect(24).bottom, 719);
    });

    test('cells sit on JPEG block boundaries and fill the grid', () {
      expect(kEffectPreviewCellWidth % 16, 0);
      expect(kEffectPreviewCellHeight % 16, 0);
      expect(kEffectPreviewFrames, lessThanOrEqualTo(kEffectPreviewColumns * 5));
    });
  });

  test('the sample bar is the bar a tap adds', () {
    const composer = VideoEditorTimelineComposer();
    for (final effect in kVideoEffects) {
      final notifier = VideoEditorNotifier(VideoEditorService())
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
          ],
        );
      notifier.addEffectBar(effect.id);
      final added = composer.composeEffects(notifier.state).single.toJson();
      final expected = {
        ...added,
        'id': 'preview_${effect.id}',
        'start': 0.0,
        'end': kDefaultEffectBarSeconds,
        'lane': 0,
      };
      expect(effectPreviewSampleBar(effect).toJson(), expected,
          reason: effect.id);
    }
  });

  test('a fresh intensity is the catalog strength and envelope', () {
    final blur = videoEffectById('blur')!;
    final fresh = freshEffectIntensity(blur);
    expect(fresh.baseValue, blur.defaultIntensity);
    expect(fresh.envelope, 'ramp_out');
    expect(fresh.keyframes, isEmpty);
  });
}
