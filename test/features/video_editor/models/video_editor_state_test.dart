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


  group('a custom crop shapes the canvas', () {
    // **The canvas takes the crop's shape.** The preview used to keep the
    // texture at 9:16 and reshape only the Flutter *box* around it by the
    // rect's proportions — which un-stretched the picture on screen while the
    // export, which has no box to reshape, kept the stretched texture. One
    // frame shape, read by both, is what makes the file match the canvas.
    test('custom with a real rect reshapes the frame by the rect', () {
      const state = VideoEditorState(
        selectedRatio: EditorCropRatio.custom,
        customCropRect: Rect.fromLTWH(0.25, 0, 0.5, 1),
      );
      expect(state.projectAspectRatio, closeTo(9 / 16 * 0.5, 1e-9));
    });

    test('while the crop tool is open the frame is the whole 9:16', () {
      // The handles are drawn over the whole frame, so the whole frame shows.
      const state = VideoEditorState(
        selectedRatio: EditorCropRatio.custom,
        customCropRect: Rect.fromLTWH(0.25, 0, 0.5, 1),
        activeToolId: 'crop',
      );
      expect(state.projectAspectRatio, closeTo(9 / 16, 1e-9));
    });

    test('a full-frame custom rect is the plain default', () {
      const state = VideoEditorState(
        selectedRatio: EditorCropRatio.custom,
        customCropRect: Rect.fromLTWH(0, 0, 1, 1),
      );
      expect(state.projectAspectRatio, closeTo(9 / 16, 1e-9));
    });

    test('a fixed ratio ignores the rect', () {
      const state = VideoEditorState(
        selectedRatio: EditorCropRatio.ratio1x1,
        customCropRect: Rect.fromLTWH(0.25, 0, 0.5, 1),
      );
      expect(state.projectAspectRatio, closeTo(1.0, 1e-9));
    });

    test('the texture follows the frame shape', () {
      const state = VideoEditorState(
        selectedRatio: EditorCropRatio.custom,
        customCropRect: Rect.fromLTWH(0.25, 0, 0.5, 1),
      );
      final size = state.projectCanvasSize;
      expect(size.width / size.height, closeTo(state.projectAspectRatio, 0.01));
    });
  });

  group('selectedClipProgress', () {
    VideoEditorState twoClips({required double position}) => VideoEditorState(
          segments: [
            VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 5),
            VideoSegment(id: 'b', sourceStart: 5, sourceEnd: 10),
          ],
          selectedSegmentId: 'b',
          isClipSelected: true,
          currentPlaybackPosition: position,
        );

    test('is null while the playhead is on another clip', () {
      // **Null, not clamped to the edge.** Clamping made a plus tapped here
      // place a diamond at the start of a clip the user was not looking at,
      // and lit the curve icon for a segment the playhead was nowhere near.
      expect(twoClips(position: 2.0).selectedClipProgress, isNull);
    });

    test('is null past the clip\'s end', () {
      expect(twoClips(position: 12.0).selectedClipProgress, isNull);
    });

    test('resolves inside the clip', () {
      expect(twoClips(position: 7.0).selectedClipProgress, closeTo(0.4, 1e-9));
    });

    test('the clip\'s own edges count as on it', () {
      // A split parks the playhead exactly on the seam, which is the right
      // half's first instant — and where a Ken Burns start is placed.
      expect(twoClips(position: 5.0).selectedClipProgress, closeTo(0.0, 1e-9));
      expect(twoClips(position: 10.0).selectedClipProgress, closeTo(1.0, 1e-9));
    });
  });
}
