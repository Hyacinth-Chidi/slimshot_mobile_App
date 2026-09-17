import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

/// An overlay can be cut to a shape — the same `ClipMask` a clip carries, so
/// there is one definition of what a shape means and one coverage function.
///
/// **The mask is in the overlay's own box**, not in canvas fractions: an
/// overlay is placed and scaled independently, so a mask authored against the
/// canvas would slide off the picture the moment the overlay moved.
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

  const circle = ClipMask(
    shape: ClipMaskShape.circle,
    width: 0.8,
    height: 0.8,
    feather: 0.04,
  );

  VideoEditorState stateWith({
    List<ImageOverlayModel> images = const [],
    List<VideoOverlayModel> videos = const [],
  }) =>
      VideoEditorState(
        assets: const [asset],
        segments: [
          VideoSegment(id: 's', assetId: 'a', sourceStart: 0, sourceEnd: 10),
        ],
        imageOverlays: images,
        videoOverlays: videos,
      );

  group('the model carries it', () {
    test('an image overlay defaults to no mask and keeps one through copyWith',
        () {
      final o = ImageOverlayModel(id: 'i', imagePath: '/p.png');
      expect(o.mask, ClipMask.none);
      expect(o.copyWith(mask: circle).mask, circle);
    });

    test('a video overlay defaults to no mask and keeps one through copyWith',
        () {
      final o = VideoOverlayModel(id: 'v', videoPath: '/v.mp4');
      expect(o.mask, ClipMask.none);
      expect(o.copyWith(mask: circle).mask, circle);
    });

    test('it round-trips through JSON, and is omitted while unset', () {
      final plain = ImageOverlayModel(id: 'i', imagePath: '/p.png');
      expect(plain.toJson().containsKey('mask'), isFalse);

      final masked = plain.copyWith(mask: circle);
      expect(ImageOverlayModel.fromJson(masked.toJson()).mask, circle);

      final vid = VideoOverlayModel(id: 'v', videoPath: '/v.mp4')
          .copyWith(mask: circle);
      expect(VideoOverlayModel.fromJson(vid.toJson()).mask, circle);
    });

    test('junk in the mask field reads as no mask, never a throw', () {
      final o = ImageOverlayModel(id: 'i', imagePath: '/p.png');
      final json = {...o.toJson(), 'mask': 'nonsense'};
      expect(ImageOverlayModel.fromJson(json).mask, ClipMask.none);
    });
  });

  group('the composer puts it on the wire', () {
    test('a masked image overlay sends its mask; an unmasked one sends none',
        () {
      final timeline = const VideoEditorTimelineComposer().compose(
        // Overlays are composed only with a canvas size: their geometry is
        // converted from device pixels to canvas fractions here.
        previewCanvasSize: const Size(360, 640),
        stateWith(images: [
          ImageOverlayModel(id: 'i', imagePath: '/p.png').copyWith(mask: circle),
          ImageOverlayModel(id: 'j', imagePath: '/q.png'),
        ]),
      );
      final masked = timeline.overlays.firstWhere((o) => o.id == 'i');
      final plain = timeline.overlays.firstWhere((o) => o.id == 'j');

      expect(masked.mask, circle);
      expect(masked.toJson()['mask'], circle.toJson());
      expect(plain.mask, ClipMask.none);
      expect(plain.toJson().containsKey('mask'), isFalse);
    });

    test('a masked video overlay sends its mask too', () {
      final timeline = const VideoEditorTimelineComposer().compose(
        previewCanvasSize: const Size(360, 640),
        stateWith(videos: [
          VideoOverlayModel(id: 'v', videoPath: '/v.mp4').copyWith(mask: circle),
        ]),
      );
      expect(timeline.overlays.single.mask, circle);
    });
  });

  group('the overlay box is the mask space', () {
    test('coverage is read in the overlay\'s own 0..1, not the canvas\'s', () {
      // The centre of the overlay is inside its own mask wherever the overlay
      // sits on the canvas — which is the whole point of authoring in its box.
      expect(maskCoverage(circle, 0.5, 0.5), 1.0);
      expect(maskCoverage(circle, 0.02, 0.02), 0.0);
    });

    test('an overlay moved on the canvas does not change its own coverage', () {
      final near = ImageOverlayModel(id: 'i', imagePath: '/p.png')
          .copyWith(mask: circle, position: Offset.zero);
      final far = near.copyWith(position: const Offset(300, -200));
      // The mask travels with the overlay: same shape, same values.
      expect(far.mask, near.mask);
    });
  });
}
