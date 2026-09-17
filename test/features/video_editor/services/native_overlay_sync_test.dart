import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';

/// How overlay edits reach the native preview.
///
/// Overlays are deliberately **not** in the playback signature — pushing a
/// whole timeline per overlay edit re-prepared the players and flashed the
/// canvas — so once the engine draws them they need a channel of their own:
/// the overlay list alone, pushed when *its* signature changes.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 30,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );
  const canvas = Size(360, 640);

  VideoEditorState stateWith(List<ImageOverlayModel> images,
          {double playhead = 0}) =>
      VideoEditorState(
        assets: const [asset],
        segments: [
          VideoSegment(id: 's', assetId: 'a', sourceStart: 0, sourceEnd: 10),
        ],
        imageOverlays: images,
        currentPlaybackPosition: playhead,
      );

  ImageOverlayModel photo({Offset position = Offset.zero}) =>
      ImageOverlayModel(id: 'i', imagePath: '/p.png', position: position);

  group('composeOverlays', () {
    test('is the same list the full timeline carries — one definition', () {
      const composer = VideoEditorTimelineComposer();
      final state = stateWith([photo(position: const Offset(40, -25))]);

      final alone = composer.composeOverlays(state, previewCanvasSize: canvas);
      final whole =
          composer.compose(state, previewCanvasSize: canvas).overlays;

      expect(alone.map((o) => o.toJson()).toList(),
          whole.map((o) => o.toJson()).toList());
    });

    test('without a canvas size there is nothing to normalise against', () {
      const composer = VideoEditorTimelineComposer();
      expect(composer.composeOverlays(stateWith([photo()])), isEmpty);
    });
  });

  group('overlaySignature', () {
    final service = NativeTimelinePreviewService();

    test('changes when an overlay moves', () {
      final before = service.overlaySignature(
        stateWith([photo()]),
        previewCanvasSize: canvas,
      );
      final after = service.overlaySignature(
        stateWith([photo(position: const Offset(12, 0))]),
        previewCanvasSize: canvas,
      );
      expect(after, isNot(before));
    });

    test('changes when an overlay is masked', () {
      final before = service.overlaySignature(
        stateWith([photo()]),
        previewCanvasSize: canvas,
      );
      final after = service.overlaySignature(
        stateWith([
          photo().copyWith(
            mask: const ClipMask(shape: ClipMaskShape.circle),
          ),
        ]),
        previewCanvasSize: canvas,
      );
      expect(after, isNot(before));
    });

    test('does not change when only the playhead moves', () {
      // The engine has its own clock; a position event must not re-send the
      // overlay list thirty times a second.
      final a = service.overlaySignature(
        stateWith([photo()], playhead: 1.0),
        previewCanvasSize: canvas,
      );
      final b = service.overlaySignature(
        stateWith([photo()], playhead: 4.5),
        previewCanvasSize: canvas,
      );
      expect(b, a);
    });

    test('an overlay added or removed changes it', () {
      final none = service.overlaySignature(
        stateWith(const []),
        previewCanvasSize: canvas,
      );
      final one = service.overlaySignature(
        stateWith([photo()]),
        previewCanvasSize: canvas,
      );
      expect(one, isNot(none));
    });
  });
}
