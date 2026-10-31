import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';
import 'package:slimshotai/features/video_editor/services/overlay_sync.dart';

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

  group('OverlaySync', () {
    EditorTimelineOverlay entry(String path) => EditorTimelineOverlay(
          id: 'text_t',
          kind: 'text',
          path: path,
          centerX: const AnimatableDouble(baseValue: 0.5),
          centerY: const AnimatableDouble(baseValue: 0.8),
          boxWidth: 0.4,
          boxHeight: 0.1,
          scale: const AnimatableDouble(baseValue: 1),
          rotation: const AnimatableDouble(baseValue: 0),
          opacity: const AnimatableDouble(baseValue: 1),
          startSeconds: 1,
          endSeconds: 2,
          laneIndex: 1000,
          slideOffsetX: 0.4,
          slideOffsetY: 0.1,
        );

    List<Map<String, dynamic>> compose(
      VideoEditorState state,
      Size canvasSize,
      List<EditorTimelineOverlay> texts,
    ) =>
        NativeTimelinePreviewService().overlayPayload(
          state,
          previewCanvasSize: canvasSize,
          textEntries: texts,
        );

    test('text entries are pushed when they change, and only then', () {
      final sync = OverlaySync();
      final state = stateWith([photo()]);
      final first = [entry('/a.png')];

      expect(sync.payloadFor(state, canvas, first, compose), isNotNull);
      // A position event: the same lists, the playhead moved.
      expect(
        sync.payloadFor(stateWith(state.imageOverlays, playhead: 2.5), canvas, first, compose),
        isNull,
      );
      expect(sync.payloadFor(state, canvas, first, compose), isNull);

      final second = [entry('/b.png')];
      final pushed = sync.payloadFor(state, canvas, second, compose);
      expect(pushed, isNotNull);
      expect(pushed!.last['path'], '/b.png');
      expect(sync.payloadFor(state, canvas, second, compose), isNull);
    });

    test('a list rebuilt with the same entries is not pushed again', () {
      final sync = OverlaySync();
      final state = stateWith([photo()]);
      expect(sync.payloadFor(state, canvas, [entry('/a.png')], compose), isNotNull);
      expect(sync.payloadFor(state, canvas, [entry('/a.png')], compose), isNull);
    });

    test('after a reset the same payload goes out again', () {
      final sync = OverlaySync();
      final state = stateWith([photo()]);
      final texts = [entry('/a.png')];
      expect(sync.payloadFor(state, canvas, texts, compose), isNotNull);
      sync.reset();
      expect(sync.payloadFor(state, canvas, texts, compose), isNotNull);
    });
  });

  group('overlayPayload', () {
    test('text entries ride the payload above every other overlay', () {
      // The preview's text is the export's text entry, sent beside the photo
      // and video overlays on the same channel, stacked above them.
      const text = EditorTimelineOverlay(
        id: 'text_t',
        kind: 'text',
        path: '/t.png',
        centerX: AnimatableDouble(baseValue: 0.5),
        centerY: AnimatableDouble(baseValue: 0.8),
        boxWidth: 0.4,
        boxHeight: 0.1,
        scale: AnimatableDouble(baseValue: 1),
        rotation: AnimatableDouble(baseValue: 0),
        opacity: AnimatableDouble(baseValue: 1),
        startSeconds: 1,
        endSeconds: 2,
        laneIndex: 1000,
        slideOffsetX: 0.4,
        slideOffsetY: 0.1,
      );
      final payload = NativeTimelinePreviewService().overlayPayload(
        stateWith([photo()]),
        previewCanvasSize: canvas,
        textEntries: const [text],
      );

      expect(payload, hasLength(2));
      expect(payload.first['id'], 'i');
      expect(payload.last, text.toJson());
    });
  });
}
