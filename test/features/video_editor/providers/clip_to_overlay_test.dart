import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/logic/canvas_geometry.dart';
import 'package:slimshotai/features/video_editor/logic/chroma/chroma_key.dart';
import 'package:slimshotai/features/video_editor/logic/clip_to_overlay.dart';
import 'package:slimshotai/features/video_editor/logic/color/color_adjustments.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';
import 'package:slimshotai/features/video_editor/logic/overlay_box_fit.dart';
import 'package:slimshotai/features/video_editor/logic/speed/speed_curve.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Moving a clip onto the overlay track — CapCut's "Overlay" on a clip, the
/// car-crash edit's first step: the clip lifts one lane down at the same
/// time, **looks exactly where it was**, and the main track closes the gap.
void main() {
  const canvas = Size(360, 640);
  const video = MediaAsset(
    id: 'v',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 60,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );
  const photo = MediaAsset(
    id: 'p',
    path: '/p.jpg',
    type: MediaAssetType.image,
    durationSeconds: 0,
    width: 1080,
    height: 1920,
    hasAudio: false,
  );

  VideoSegment clip(String id, {String asset = 'v', double start = 0, double end = 4}) =>
      VideoSegment(id: id, assetId: asset, sourceStart: start, sourceEnd: end);

  VideoEditorNotifier notifierWith(List<VideoSegment> segments, {required String selected}) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        assets: const [video, photo],
        segments: segments,
        selectedSegmentId: selected,
        isClipSelected: true,
      );
  }

  group('what does not carry over', () {
    test('a plain clip loses nothing, so it moves without asking', () {
      expect(clipToOverlayLosses(clip('a')), isEmpty);
    });

    test('each thing an overlay cannot hold yet is named', () {
      final everything = clip('a').copyWith(
        filterId: 'warm',
        adjustments: const ColorAdjustments(brightness: 0.2),
        effectId: 'vhs',
        cropRect: const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8),
        flipHorizontal: true,
        speedCurve: kSpeedCurvePresets.first.curve,
        isReversed: true,
        volume: const AnimatableDouble(
          baseValue: 1,
          keyframes: [Keyframe(progress: 0, value: 0), Keyframe(progress: 1, value: 1)],
        ),
      );
      expect(clipToOverlayLosses(everything), [
        'Filter',
        'Adjust',
        'Effect',
        'Crop',
        'Flip',
        'Speed curve',
        'Reverse',
        'Volume keyframes',
      ]);
    });

    test('the sheet says it in one line', () {
      expect(clipToOverlayLossLine(['Filter']), "Filter won't carry over.");
      expect(clipToOverlayLossLine(['Filter', 'Speed curve']),
          "Filter and speed curve won't carry over.");
      expect(clipToOverlayLossLine(['Filter', 'Effect', 'Crop']),
          "Filter, effect and crop won't carry over.");
    });
  });

  group('the move', () {
    test('lifts the clip to an overlay at the same time, and the track closes up', () {
      final n = notifierWith(
        [clip('a'), clip('b', start: 10, end: 16), clip('c')],
        selected: 'b',
      );
      expect(n.moveSelectedClipToOverlay(canvas: canvas, overlayId: 'o'), isTrue);

      expect(n.state.segments.map((s) => s.id), ['a', 'c']);
      final o = n.state.videoOverlays.single;
      expect(o.id, 'o');
      expect(o.videoPath, '/v.mp4');
      expect(o.timelineStart, const Duration(seconds: 4), reason: 'where b began');
      expect(o.timelineEnd, const Duration(seconds: 10));
      expect(o.sourceStart, 10);
      expect(o.sourceEnd, 16);
      // The overlay is what is selected now, with its own menu.
      expect(n.state.selectedVideoOverlayId, 'o');
      expect(n.state.selectedSegmentId, isNull);
      expect(n.state.currentMenuId, 'video_overlay');
    });

    test('is one undo step', () {
      final n = notifierWith([clip('a'), clip('b')], selected: 'b');
      n.moveSelectedClipToOverlay(canvas: canvas, overlayId: 'o');
      n.undo();
      expect(n.state.segments.map((s) => s.id), ['a', 'b']);
      expect(n.state.videoOverlays, isEmpty);
    });

    test('keeps speed, volume, opacity, mask and chroma key', () {
      const mask = ClipMask(shape: ClipMaskShape.linear, centerX: 0.3, angle: 20);
      const key = ChromaKey(enabled: true);
      final n = notifierWith([
        clip('a'),
        clip('b', start: 0, end: 8).copyWith(
          speed: 2,
          volume: const AnimatableDouble(baseValue: 0.4),
          opacity: const AnimatableDouble(baseValue: 0.7),
          mask: mask,
          chromaKey: key,
        ),
      ], selected: 'b');
      n.moveSelectedClipToOverlay(canvas: canvas, overlayId: 'o');
      final o = n.state.videoOverlays.single;
      expect(o.speed, 2);
      expect(o.timelineEnd - o.timelineStart, const Duration(seconds: 4), reason: '8s at 2x');
      expect(o.volume, 0.4);
      expect(o.opacity, 0.7);
      expect(o.mask, mask);
      expect(o.chromaKey, key);
    });

    test('lands exactly where the clip was drawn', () {
      // A 16:9 clip contain-fitted into a 9:16 canvas is the canvas's width
      // wide. The overlay fits the same picture into its 240px box, so its
      // scale is whatever makes the two the same size on screen.
      final n = notifierWith([
        clip('a'),
        clip('b').copyWith(
          canvasScale: const AnimatableDouble(baseValue: 0.8),
          canvasOffsetX: const AnimatableDouble(baseValue: 0.1),
          canvasOffsetY: const AnimatableDouble(baseValue: -0.2),
          canvasRotation: const AnimatableDouble(baseValue: 30),
        ),
      ], selected: 'b');
      n.moveSelectedClipToOverlay(canvas: canvas, overlayId: 'o');
      final o = n.state.videoOverlays.single;

      final clipWidth = fittedFrameRect(contentAspect: 1920 / 1080, canvasSize: canvas).width * 0.8;
      final overlayWidth = fittedOverlayBox(contentAspect: 1920 / 1080, box: kVideoOverlayBoxPx).width * o.scale;
      expect(overlayWidth, closeTo(clipWidth, 1e-9));
      expect(o.position.dx, closeTo(0.1 * canvas.width, 1e-9));
      expect(o.position.dy, closeTo(-0.2 * canvas.height, 1e-9));
      // Both turn clockwise: the clip in degrees, the overlay in radians.
      expect(o.rotation, closeTo(30 * math.pi / 180, 1e-12));
    });

    test('its keyframes travel with it, curves and all', () {
      final n = notifierWith([
        clip('a'),
        clip('b').copyWith(
          canvasScale: const AnimatableDouble(baseValue: 1, keyframes: [
            Keyframe(progress: 0, value: 1, interpolation: KeyframeInterpolation.cubicInOut),
            Keyframe(progress: 1, value: 2),
          ]),
          canvasOffsetX: const AnimatableDouble(baseValue: 0, keyframes: [
            Keyframe(progress: 0, value: 0),
            Keyframe(progress: 1, value: 0.25),
          ]),
        ),
      ], selected: 'b');
      n.moveSelectedClipToOverlay(canvas: canvas, overlayId: 'o');
      final o = n.state.videoOverlays.single;
      final k = fittedFrameRect(contentAspect: 1920 / 1080, canvasSize: canvas).width /
          fittedOverlayBox(contentAspect: 1920 / 1080, box: kVideoOverlayBoxPx).width;

      final scale = o.keyframes.of(OverlayProperty.scale);
      expect(scale.map((kf) => kf.progress), [0, 1]);
      expect(scale.first.value, closeTo(1 * k, 1e-9));
      expect(scale.last.value, closeTo(2 * k, 1e-9));
      expect(scale.first.interpolation, KeyframeInterpolation.cubicInOut);
      final x = o.keyframes.of(OverlayProperty.x);
      expect(x.last.value, closeTo(0.25 * canvas.width, 1e-9));
    });

    test('a photo becomes a photo overlay, in its own 200px box', () {
      final n = notifierWith([clip('a'), clip('b', asset: 'p', start: 0, end: 3)], selected: 'b');
      n.moveSelectedClipToOverlay(canvas: canvas, overlayId: 'o');
      final o = n.state.imageOverlays.single;
      expect(o.imagePath, '/p.jpg');
      expect(o.endTime - o.startTime, const Duration(seconds: 3));
      final clipWidth = fittedFrameRect(contentAspect: 1080 / 1920, canvasSize: canvas).width;
      final overlayWidth = fittedOverlayBox(contentAspect: 1080 / 1920, box: kImageOverlayBoxPx).width * o.scale;
      expect(overlayWidth, closeTo(clipWidth, 1e-9));
      expect(n.state.currentMenuId, 'image_overlay');
    });

    test('a clip on a speed curve plays its footage at its flat speed', () {
      // The curve is one of the things that does not carry over: the overlay
      // runs the clip's source at its own (flat) speed, 1x under a curve.
      final n = notifierWith([
        clip('a'),
        clip('b', start: 0, end: 6).copyWith(speedCurve: kSpeedCurvePresets.first.curve),
      ], selected: 'b');
      n.moveSelectedClipToOverlay(canvas: canvas, overlayId: 'o');
      final o = n.state.videoOverlays.single;
      expect(o.timelineEnd - o.timelineStart, const Duration(seconds: 6));
    });

    test('the last clip on the main track stays there', () {
      final n = notifierWith([clip('a')], selected: 'a');
      expect(n.moveSelectedClipToOverlay(canvas: canvas, overlayId: 'o'), isFalse);
      expect(n.state.segments, hasLength(1));
      expect(n.state.videoOverlays, isEmpty);
      expect(n.state.canUndo, isFalse);
    });
  });
}
