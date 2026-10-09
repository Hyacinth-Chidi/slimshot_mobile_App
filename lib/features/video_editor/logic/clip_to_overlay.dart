/// Moving a clip onto the overlay track — CapCut's "Overlay" on a clip.
///
/// The car-crash edit starts here: the clip lifts one lane down at the same
/// time, looks exactly where it was, and the main track closes the gap. These
/// are the pure halves of it — what cannot come along, and the overlay the
/// clip becomes — so the notifier only has to put them in the project.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../models/image_overlay_model.dart';
import '../models/media_asset.dart';
import '../models/video_overlay_model.dart';
import '../models/video_segment.dart';
import 'animation/animatable_double.dart';
import 'animation/overlay_keyframes.dart';
import 'canvas_geometry.dart';
import 'overlay_box_fit.dart';

/// What [s] carries that an overlay cannot hold yet, by the names the editor
/// uses for them — what the confirm sheet names before the move. Empty means
/// the clip moves straight away, with nothing to ask.
///
/// Its transitions are not here: moving a clip off the track closes the gap
/// exactly as deleting it does, and that has never asked.
List<String> clipToOverlayLosses(VideoSegment s) => [
      if (s.filterId != null) 'Filter',
      if (!s.adjustments.isIdentity) 'Adjust',
      if (s.effectId != null) 'Effect',
      if (s.cropRect != kFullFrameRect) 'Crop',
      if (s.flipHorizontal || s.flipVertical) 'Flip',
      if (s.speedCurve != null) 'Speed curve',
      if (s.isReversed) 'Reverse',
      if (s.volume.isAnimated) 'Volume keyframes',
    ];

/// The sheet's one line: "Filter and speed curve won't carry over."
String clipToOverlayLossLine(List<String> losses) {
  if (losses.isEmpty) return '';
  final names = [
    losses.first,
    for (final name in losses.skip(1)) name.toLowerCase(),
  ];
  final list = names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  return "$list won't carry over.";
}

/// [s] as an overlay: a photo overlay for a photo, a video overlay for a
/// video. Exactly one of the two is set.
///
/// **It looks exactly where the clip was.** A clip is its picture
/// contain-fitted into the canvas, scaled, moved and turned about its centre;
/// an overlay is the same picture contain-fitted into its own square box (in
/// the [canvas]'s pixels), scaled, moved and turned. So the overlay's scale is
/// the clip's times the ratio of the two fits, its position the clip's offset
/// in pixels, and its turn the clip's in radians — both clockwise. Each is a
/// fixed change of units, so it is applied to the base value and to every
/// keyframe alike ([mapAnimatable]): a keyframed move keeps moving, curves
/// and all, on the same clip-relative progress the overlay counts in.
///
/// It spans what the clip's own source plays for at its flat speed, from
/// [startSeconds] — where the clip began on the timeline. Under a speed curve,
/// which does not carry over, the flat speed is 1x.
({ImageOverlayModel? image, VideoOverlayModel? video}) clipAsOverlay(
  VideoSegment s,
  MediaAsset asset, {
  required String id,
  required double startSeconds,
  required Size canvas,
}) {
  final aspect = asset.width > 0 && asset.height > 0 ? asset.width / asset.height : null;
  final frame = fittedFrameRect(contentAspect: aspect, canvasSize: canvas);
  final box = fittedOverlayBox(
    contentAspect: aspect,
    box: asset.isImage ? kImageOverlayBoxPx : kVideoOverlayBoxPx,
  );
  final fitRatio = box.width > 0 ? frame.width / box.width : 1.0;

  final motion = OverlayMotion.fromParams({
    OverlayProperty.x: mapAnimatable(s.canvasOffsetX, (v) => v * canvas.width),
    OverlayProperty.y: mapAnimatable(s.canvasOffsetY, (v) => v * canvas.height),
    OverlayProperty.scale: mapAnimatable(s.canvasScale, (v) => v * fitRatio),
    OverlayProperty.rotation:
        mapAnimatable(s.canvasRotation, (v) => v * math.pi / 180.0),
    OverlayProperty.opacity: s.opacity,
  });

  Duration at(double seconds) => Duration(milliseconds: (seconds * 1000).round());
  final start = at(startSeconds);

  if (asset.isImage) {
    final image = ImageOverlayModel(
      id: id,
      imagePath: asset.path,
      startTime: start,
      endTime: at(startSeconds + s.duration),
      mask: s.mask,
      chromaKey: s.chromaKey,
    ).withMotion(motion);
    return (image: image, video: null);
  }

  final speed = s.speed > 0 ? s.speed : 1.0;
  final video = VideoOverlayModel(
    id: id,
    videoPath: asset.path,
    timelineStart: start,
    timelineEnd: at(startSeconds + (s.sourceEnd - s.sourceStart) / speed),
    sourceStart: s.sourceStart,
    sourceEnd: s.sourceEnd,
    speed: speed,
    volume: s.volume.baseValue.clamp(0.0, 1.0).toDouble(),
    mask: s.mask,
    chromaKey: s.chromaKey,
  ).withMotion(motion);
  return (image: null, video: video);
}
