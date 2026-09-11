import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

void main() {
  MediaAsset asset({
    required String id,
    required double width,
    required double height,
    MediaAssetType type = MediaAssetType.video,
  }) {
    return MediaAsset(
      id: id,
      path: '/media/$id',
      type: type,
      durationSeconds: type == MediaAssetType.image ? 0 : 10,
      width: width,
      height: height,
      hasAudio: type == MediaAssetType.video,
    );
  }

  group('canvas', () {
    // The canvas is a fixed 9:16 by default and does NOT follow the imported
    // media. Deriving it meant the frame changed shape as assets were probed
    // and as clips were added, and each change resized the preview texture and
    // rebuilt the EGL surface, which the user saw as a flash.
    test('is 9:16 regardless of what was imported', () {
      final landscapeOnly = VideoEditorState(
        assets: [asset(id: 'landscape', width: 1920, height: 1080)],
      );
      final portraitOnly = VideoEditorState(
        assets: [asset(id: 'portrait', width: 1080, height: 1920)],
      );

      expect(landscapeOnly.projectAspectRatio, closeTo(9 / 16, 1e-9));
      expect(portraitOnly.projectAspectRatio, closeTo(9 / 16, 1e-9));
    });

    test('import order does not change the frame', () {
      final a = VideoEditorState(
        assets: [
          asset(id: 'portrait', width: 1080, height: 1920),
          asset(id: 'landscape', width: 1920, height: 1080),
        ],
      );
      final b = VideoEditorState(
        assets: [
          asset(id: 'landscape', width: 1920, height: 1080),
          asset(id: 'portrait', width: 1080, height: 1920),
        ],
      );

      expect(a.projectAspectRatio, b.projectAspectRatio);
      expect(a.projectCanvasSize, b.projectCanvasSize);
    });

    test('adding a clip never resizes the canvas', () {
      // The texture is sized from this. If it changed here, every import would
      // rebuild the EGL surface mid-session.
      final one = VideoEditorState(
        assets: [asset(id: 'portrait', width: 1080, height: 1920)],
      );
      final three = VideoEditorState(
        assets: [
          asset(id: 'portrait', width: 1080, height: 1920),
          asset(id: 'photo', width: 4032, height: 3024, type: MediaAssetType.image),
          asset(id: '4k', width: 3840, height: 2160),
        ],
      );

      expect(three.projectCanvasSize, one.projectCanvasSize);
    });

    test('an explicit ratio overrides the default', () {
      final state = VideoEditorState(
        assets: [asset(id: 'portrait', width: 1080, height: 1920)],
        selectedRatio: EditorCropRatio.ratio16x9,
      );

      expect(state.projectAspectRatio, closeTo(16 / 9, 1e-9));
    });

    test('is 9:16 with nothing imported', () {
      expect(const VideoEditorState().projectAspectRatio, closeTo(9 / 16, 1e-9));
    });
  });

  group('projectCanvasSize', () {
    // This drives the GL viewport. If it is not the canvas shape, every clip
    // fit is computed against the wrong frame and the picture is squeezed.
    test('matches the canvas aspect', () {
      final state = VideoEditorState(
        assets: [
          asset(id: 'landscape', width: 1920, height: 1080),
          asset(id: 'portrait', width: 1080, height: 1920),
        ],
      );

      final size = state.projectCanvasSize;
      expect(size.width / size.height, closeTo(9 / 16, 0.01));
    });

    test('caps the longest side for preview cost', () {
      final state = VideoEditorState(
        assets: [asset(id: '4k', width: 3840, height: 2160)],
      );

      final size = state.projectCanvasSize;
      expect(size.width, lessThanOrEqualTo(kMaxPreviewCanvasPx));
      expect(size.height, lessThanOrEqualTo(kMaxPreviewCanvasPx));
      expect(size.width / size.height, closeTo(9 / 16, 0.01));
    });

    test('follows an explicit ratio', () {
      final state = VideoEditorState(
        assets: [asset(id: 'portrait', width: 1080, height: 1920)],
        selectedRatio: EditorCropRatio.ratio16x9,
      );

      final size = state.projectCanvasSize;
      expect(size.width / size.height, closeTo(16 / 9, 0.01));
      expect(size.width, lessThanOrEqualTo(kMaxPreviewCanvasPx));
    });

    test('dimensions stay even', () {
      final state = VideoEditorState(
        assets: [asset(id: 'odd', width: 1081, height: 1921)],
      );

      final size = state.projectCanvasSize;
      expect(size.width % 2, 0);
      expect(size.height % 2, 0);
    });

    test('is the 9:16 default with nothing imported', () {
      expect(const VideoEditorState().projectCanvasSize, const Size(720, 1280));
    });
  });

  group('assetFor', () {
    test('resolves a clip to the file it was cut from', () {
      final state = VideoEditorState(
        assets: [
          asset(id: 'a', width: 1920, height: 1080),
          asset(id: 'b', width: 1080, height: 1920),
        ],
        segments: [
          VideoSegment(id: 'clip', assetId: 'b', sourceStart: 0, sourceEnd: 2),
        ],
      );

      expect(state.assetFor(state.segments.first)?.id, 'b');
    });

    test('falls back to the first asset for a pre-migration clip', () {
      final state = VideoEditorState(
        assets: [asset(id: 'a', width: 1920, height: 1080)],
        segments: [VideoSegment(id: 'clip', sourceStart: 0, sourceEnd: 2)],
      );

      expect(state.assetFor(state.segments.first)?.id, 'a');
    });
  });
}
