import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

// The transitions page's clip: three photos, each resting and then taken to
// the next by one of the app's own moves — Zoom Blur, then a glitch, then a
// cube, the owner's order. Drawn here in Flutter because the engine's
// renderer belongs to the editor and is not running at onboarding; what it
// draws follows the app's own — CrossZoom's sweep and strength, the Glitch
// effect's torn blocks and pulled-apart channels, the cube's perspective and
// back-off — so the page does not promise a look the editor does not have.

/// The photos, in the order the loop visits them.
const List<String> kShowreelPhotos = [
  'assets/home/new_video_right.webp',
  'assets/home/new_video_middle.webp',
  'assets/home/new_video_left.webp',
];

/// The height the photos decode at: under their own 1672, enough for the
/// frame on a tablet's screen.
const int kShowreelPhotoHeight = 960;

/// Photo [index] as the showreel decodes it — the one provider both the
/// page and its precache use, so the second finds the first in the cache.
ImageProvider showreelPhoto(int index) => ResizeImage(
      AssetImage(kShowreelPhotos[index]),
      height: kShowreelPhotoHeight,
    );

enum ShowreelMove { zoomBlur, glitch, cube }

/// One move of the loop: the photo rests, then [move] takes it to the next.
@immutable
class ShowreelStep {
  const ShowreelStep(
    this.move,
    this.label, {
    required this.rest,
    required this.play,
  });

  final ShowreelMove move;

  /// The chip that lights while the move is next or playing.
  final String label;
  final Duration rest;
  final Duration play;
}

const List<ShowreelStep> kShowreelSteps = [
  ShowreelStep(
    ShowreelMove.zoomBlur,
    'Zoom Blur',
    rest: Duration(milliseconds: 900),
    play: Duration(milliseconds: 800),
  ),
  ShowreelStep(
    ShowreelMove.glitch,
    'Glitch',
    rest: Duration(milliseconds: 900),
    play: Duration(milliseconds: 600),
  ),
  ShowreelStep(
    ShowreelMove.cube,
    'Cube',
    rest: Duration(milliseconds: 900),
    play: Duration(milliseconds: 900),
  ),
];

/// Once round the loop.
final Duration kShowreelLoop = kShowreelSteps.fold(
  Duration.zero,
  (sum, step) => sum + step.rest + step.play,
);

/// The glitch's picture changes this many times while it plays — fifteen a
/// second — and holds between: a corrupt frame is wrong, then wrong
/// differently, never sliding.
const int kGlitchTicks = 9;

/// Where the loop is: [step] is the move resting before it ([progress] 0)
/// or playing (0..1). Equal frames draw the same picture, so the clip
/// repaints only when this changes.
@immutable
class ShowreelFrame {
  const ShowreelFrame(this.step, this.progress);

  final int step;
  final double progress;

  int get from => step;
  int get to => (step + 1) % kShowreelPhotos.length;
  ShowreelMove get move => kShowreelSteps[step].move;

  @override
  bool operator ==(Object other) =>
      other is ShowreelFrame &&
      other.step == step &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(step, progress);

  @override
  String toString() => 'ShowreelFrame($step, $progress)';
}

/// The loop at [elapsed], round and round.
ShowreelFrame showreelFrameAt(Duration elapsed) {
  var t = elapsed.inMicroseconds % kShowreelLoop.inMicroseconds;
  for (var i = 0; i < kShowreelSteps.length; i++) {
    final step = kShowreelSteps[i];
    final rest = step.rest.inMicroseconds;
    final play = step.play.inMicroseconds;
    if (t < rest) return ShowreelFrame(i, 0);
    t -= rest;
    if (t < play) {
      final p = t / play;
      if (step.move != ShowreelMove.glitch) return ShowreelFrame(i, p);
      final tick = math.min(kGlitchTicks - 1, (p * kGlitchTicks).floor());
      return ShowreelFrame(i, (tick + 0.5) / kGlitchTicks);
    }
    t -= play;
  }
  return const ShowreelFrame(0, 0);
}

/// A band of the picture torn sideways: its rows as fractions of the
/// height, the tear as a fraction of the width.
@immutable
class GlitchTear {
  const GlitchTear({
    required this.top,
    required this.bottom,
    required this.shift,
    required this.split,
    required this.fromOther,
  });

  final double top;
  final double bottom;
  final double shift;

  /// Its own colour channels pulled apart, a fraction of the width.
  final double split;

  /// The band shows the other photo — the two streams crossing.
  final bool fromOther;
}

/// One tick of the glitch: which photo shows, how far the whole frame's
/// channels are pulled apart, the torn bands, and now and then a band whose
/// red and blue swap.
@immutable
class GlitchTick {
  const GlitchTick({
    required this.showsTo,
    required this.split,
    required this.tears,
    this.swapTop,
    this.swapBottom,
  });

  final bool showsTo;
  final double split;
  final List<GlitchTear> tears;
  final double? swapTop;
  final double? swapBottom;
}

/// Which photo each tick shows: the old one, a flicker between the two, then
/// the new one.
const List<bool> _kGlitchShowsTo = [
  false, false, true, false, true, true, false, true, true, //
];

/// The glitch at [tick] — planned, not random, so it plays the same every
/// time, hardest in the middle as the photo changes.
GlitchTick glitchTickAt(int tick) {
  final k = tick.clamp(0, kGlitchTicks - 1);
  final strength = math.sin(math.pi * (k + 0.5) / kGlitchTicks);
  final count = 1 + (_unit(k, 1) * 3.999).floor();
  final tears = <GlitchTear>[];
  for (var j = 0; j < count; j++) {
    final salt = 10 + j * 8;
    final centre = _unit(k, salt);
    final reach = _unit(k, salt + 1);
    final height = 0.03 + 0.14 * reach * reach;
    final sign = _unit(k, salt + 2) < 0.5 ? -1.0 : 1.0;
    tears.add(GlitchTear(
      top: math.max(0, centre - height / 2),
      bottom: math.min(1, centre + height / 2),
      shift: sign * (0.03 + 0.13 * _unit(k, salt + 3)) * (0.4 + 0.6 * strength),
      split: (0.006 + 0.014 * _unit(k, salt + 4)) * strength,
      fromOther: _unit(k, salt + 5) < 0.3,
    ));
  }
  final swaps = _unit(k, 5) < 0.4;
  final swapCentre = _unit(k, 6);
  final swapHeight = 0.04 + 0.14 * _unit(k, 7);
  return GlitchTick(
    showsTo: _kGlitchShowsTo[k],
    split: (0.016 + 0.024 * _unit(k, 2)) * strength,
    tears: tears,
    swapTop: swaps ? math.max(0, swapCentre - swapHeight / 2) : null,
    swapBottom: swaps ? math.min(1, swapCentre + swapHeight / 2) : null,
  );
}

/// A number in 0..1 from a tick and a salt — the same every run.
double _unit(int tick, int salt) {
  var h = (tick * 0x27d4eb2d + salt * 0x165667b1 + 0x9e3779b9) & 0xffffffff;
  h ^= h >> 15;
  h = (h * 0x85ebca6b) & 0xffffffff;
  h ^= h >> 13;
  h = (h * 0xc2b2ae35) & 0xffffffff;
  h ^= h >> 16;
  return h / 0x100000000;
}

/// The cube backs off as it turns, as the app's Cube does (its `UNZOOM`):
/// to 1/1.3 of the frame half-way, so the whole of it stays in view.
const double _kCubeUnzoom = 0.3;

/// How far the eye is from the screen, in frame widths: far enough that the
/// faces read as a box, near enough that the turn reads as depth.
const double _kCubeEyeDistance = 3.0;

/// The cube's size at [q] through its turn: 1 at either end.
double showreelCubeZoom(double q) {
  final uz = _kCubeUnzoom * 2 * (0.5 - (0.5 - q).abs());
  return math.min(1 / (1 + uz), _cubeFit(q));
}

/// The largest the cube may be at [q] and stay inside the frame. A face
/// turning about the cube's middle swings its far edge outward before depth
/// draws it in, so early in the turn the back-off alone leaves that edge a
/// few percent past the frame, cut off by its border. Worked in frame
/// widths: the frame's height cancels out.
double _cubeFit(double q) {
  var fit = 1.0;
  for (final angle in [q * math.pi / 2, -(1 - q) * math.pi / 2]) {
    if (math.cos(angle) < 0.001) continue;
    // The face's two upright edges, half a width either side of its middle,
    // turned about the cube's centre half a width behind it.
    for (final x in [-0.5, 0.5]) {
      final turnedX = math.cos(angle) * x - math.sin(angle) * 0.5;
      final turnedZ = -math.sin(angle) * x - math.cos(angle) * 0.5 + 0.5;
      final depth = 1 + turnedZ / _kCubeEyeDistance;
      fit = math.min(fit, depth);
      if (turnedX.abs() > 1e-9) {
        fit = math.min(fit, 0.5 * depth / turnedX.abs());
      }
    }
  }
  return fit;
}

/// Where a cube face is drawn: the face's own rect (0..w, 0..h) onto the
/// frame, for a face turned [angle] radians about the cube's upright axis —
/// 0 facing the viewer, positive turned away to the left, negative waiting
/// on the right — the whole cube at [zoom]. The cube is as deep as the frame
/// is wide, its front face on the screen, so a face at rest is exactly the
/// frame.
Matrix4 showreelCubeFace(Size size, double angle, double zoom) {
  final w = size.width;
  final h = size.height;
  return Matrix4.identity()
    ..translateByDouble(w / 2, h / 2, 0, 1)
    ..scaleByDouble(zoom, zoom, 1, 1)
    ..multiply(Matrix4.identity()..setEntry(3, 2, 1 / (_kCubeEyeDistance * w)))
    ..translateByDouble(0, 0, w / 2, 1)
    ..rotateY(angle)
    ..translateByDouble(-w / 2, -h / 2, -w / 2, 1);
}

/// CrossZoom's strength, the furthest a sample reaches toward the centre.
const double _kZoomStrength = 0.4;

/// Copies of a photo averaged into one zoom-blurred picture.
const int _kZoomCopies = 12;

/// How much of a face's reflection the floor gives back where it meets it
/// (the app's Cube: `REFLECTION`).
const double _kCubeReflection = 0.4;

const List<double> _kRedOnly = [
  1, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, //
  0, 0, 0, 1, 0, //
];
const List<double> _kGreenOnly = [
  0, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 0, 0, 0, //
  0, 0, 0, 1, 0, //
];
const List<double> _kBlueOnly = [
  0, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];
const List<double> _kRedBlueSwapped = [
  0, 0, 1, 0, 0, //
  0, 1, 0, 0, 0, //
  1, 0, 0, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Draws the clip: a photo at rest, or the move from one to the next. A
/// photo still decoding leaves the frame dark rather than empty.
class ShowreelPainter extends CustomPainter {
  ShowreelPainter({required this.frame, required this.photos})
      : super(repaint: frame);

  final ValueListenable<ShowreelFrame> frame;

  /// The decoded photos, in [kShowreelPhotos]' order; null while decoding.
  final List<ui.Image?> photos;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final now = frame.value;
    final from = photos[now.from];
    final to = photos[now.to];
    canvas.save();
    canvas.clipRect(rect);
    if (from == null || (now.progress > 0 && to == null)) {
      canvas.drawRect(rect, Paint()..color = AppColors.background);
    } else if (now.progress <= 0) {
      canvas.drawImageRect(
        from,
        _coverSource(from, size),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      switch (now.move) {
        case ShowreelMove.zoomBlur:
          _paintZoomBlur(canvas, rect, from, to!, now.progress);
        case ShowreelMove.glitch:
          _paintGlitch(canvas, rect, from, to!, now.progress);
        case ShowreelMove.cube:
          _paintCube(canvas, rect, from, to!, now.progress);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ShowreelPainter oldDelegate) =>
      oldDelegate.frame != frame || !listEquals(oldDelegate.photos, photos);
}

/// The part of [image] that covers a [size]-shaped frame, centred.
Rect _coverSource(ui.Image image, Size size) {
  final iw = image.width.toDouble();
  final ih = image.height.toDouble();
  final frameAspect = size.width / size.height;
  if (iw / ih > frameAspect) {
    final w = ih * frameAspect;
    return Rect.fromLTWH((iw - w) / 2, 0, w, ih);
  }
  final h = iw / frameAspect;
  return Rect.fromLTWH(0, (ih - h) / 2, iw, h);
}

/// CrossZoom: each photo smeared toward a centre that sweeps from a quarter
/// to three quarters across, the smear rising to its strength half-way and
/// falling, the photos swapping on an exponential ease about the middle.
void _paintZoomBlur(
  Canvas canvas,
  Rect rect,
  ui.Image from,
  ui.Image to,
  double p,
) {
  final centre = Offset(
    rect.left + rect.width * (0.25 + 0.5 * p),
    rect.center.dy,
  );
  final strength = _kZoomStrength * 0.5 * (1 - math.cos(2 * math.pi * p));
  final dissolve = _exponentialInOut(p);
  if (dissolve < 1) _zoomSmear(canvas, rect, from, centre, strength);
  if (dissolve > 0) {
    canvas.saveLayer(rect, Paint()..color = Color.fromRGBO(0, 0, 0, dissolve));
    _zoomSmear(canvas, rect, to, centre, strength);
    canvas.restore();
  }
}

/// The photo averaged over magnifications about [centre] — each pixel the
/// mean of the picture between it and the centre, CrossZoom's samples —
/// weighted as CrossZoom weights them, heaviest mid-way along.
void _zoomSmear(
  Canvas canvas,
  Rect rect,
  ui.Image image,
  Offset centre,
  double strength,
) {
  final src = _coverSource(image, rect.size);
  if (strength < 0.002) {
    canvas.drawImageRect(
        image, src, rect, Paint()..filterQuality = FilterQuality.medium);
    return;
  }
  var total = 0.0;
  for (var k = 0; k < _kZoomCopies; k++) {
    final t = (k + 0.5) / _kZoomCopies;
    final weight = 4 * (t - t * t);
    total += weight;
    final m = 1 / (1 - t * strength);
    // Drawn over the mean of the copies before it, this one at its share of
    // the weight so far keeps the whole a weighted mean.
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTRB(
        centre.dx + (rect.left - centre.dx) * m,
        centre.dy + (rect.top - centre.dy) * m,
        centre.dx + (rect.right - centre.dx) * m,
        centre.dy + (rect.bottom - centre.dy) * m,
      ),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, weight / total)
        ..filterQuality = FilterQuality.low,
    );
  }
}

double _exponentialInOut(double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  final x = t * 2;
  if (x < 1) return 0.5 * math.pow(2, 10 * (x - 1)).toDouble();
  return 0.5 * (2 - math.pow(2, -10 * (x - 1)).toDouble());
}

/// The glitch: the frame's channels pulled apart, bands torn sideways
/// (wrapping round, some showing the other photo), now and then a band's
/// red and blue swapped — and the photo flickering between the two.
void _paintGlitch(
  Canvas canvas,
  Rect rect,
  ui.Image from,
  ui.Image to,
  double p,
) {
  final tick = glitchTickAt((p * kGlitchTicks).floor());
  final shown = tick.showsTo ? to : from;
  final other = tick.showsTo ? from : to;
  final w = rect.width;
  // A clear layer the channels add up in.
  canvas.saveLayer(rect, Paint());
  _splitChannels(canvas, rect, shown, 0, tick.split * w);
  for (final tear in tick.tears) {
    final band = Rect.fromLTRB(
      rect.left,
      rect.top + tear.top * rect.height,
      rect.right,
      rect.top + tear.bottom * rect.height,
    );
    final image = tear.fromOther ? other : shown;
    final shift = tear.shift * w;
    canvas.save();
    canvas.clipRect(band);
    canvas.drawRect(band, Paint()..blendMode = BlendMode.clear);
    _splitChannels(canvas, rect, image, shift, tear.split * w);
    _splitChannels(canvas, rect, image, shift - w * shift.sign, tear.split * w);
    canvas.restore();
  }
  if (tick.swapTop != null) {
    final band = Rect.fromLTRB(
      rect.left,
      rect.top + tick.swapTop! * rect.height,
      rect.right,
      rect.top + tick.swapBottom! * rect.height,
    );
    canvas.save();
    canvas.clipRect(band);
    canvas.drawImageRect(
      shown,
      _coverSource(shown, rect.size),
      rect,
      Paint()..colorFilter = const ColorFilter.matrix(_kRedBlueSwapped),
    );
    canvas.restore();
  }
  canvas.restore();
}

/// [image] moved [shift] sideways with its red [split] further left and its
/// blue as far right, added channel by channel.
void _splitChannels(
  Canvas canvas,
  Rect rect,
  ui.Image image,
  double shift,
  double split,
) {
  final src = _coverSource(image, rect.size);
  for (final (channel, dx) in [
    (_kRedOnly, -split),
    (_kGreenOnly, 0.0),
    (_kBlueOnly, split),
  ]) {
    canvas.drawImageRect(
      image,
      src,
      rect.shift(Offset(shift + dx, 0)),
      Paint()
        ..colorFilter = ColorFilter.matrix(channel)
        ..blendMode = BlendMode.plus
        ..filterQuality = FilterQuality.low,
    );
  }
}

/// The cube: the old photo turns away to the left as the new one comes round
/// from the right, the cube backing off as it turns, its faces shaded as
/// they turn from the light, over a dark floor that gives back a little of
/// each.
void _paintCube(
  Canvas canvas,
  Rect rect,
  ui.Image from,
  ui.Image to,
  double p,
) {
  final q = Curves.easeInOutCubic.transform(p);
  final zoom = showreelCubeZoom(q);
  final size = rect.size;
  final face = Offset.zero & size;
  canvas.drawRect(rect, Paint()..color = AppColors.background);
  final faces = [
    (from, q * math.pi / 2),
    (to, -(1 - q) * math.pi / 2),
  ];
  // The floor's reflection first, under the faces: each face mirrored below
  // its foot, fading away from it.
  canvas.saveLayer(rect, Paint());
  for (final (image, angle) in faces) {
    if (math.cos(angle) < 0.001) continue;
    canvas.save();
    canvas.transform((showreelCubeFace(size, angle, zoom)
          ..translateByDouble(0, 2 * size.height, 0, 1)
          ..scaleByDouble(1, -1, 1, 1))
        .storage);
    canvas.drawImageRect(
      image,
      _coverSource(image, size),
      face,
      Paint()
        ..color = const Color.fromRGBO(0, 0, 0, _kCubeReflection)
        ..filterQuality = FilterQuality.low,
    );
    canvas.drawRect(
      face,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height),
          Offset(0, size.height * 0.6),
          const [Colors.black, Colors.transparent],
        )
        ..blendMode = BlendMode.dstIn,
    );
    canvas.restore();
  }
  canvas.restore();
  for (final (image, angle) in faces) {
    final facing = math.cos(angle);
    if (facing < 0.001) continue;
    canvas.save();
    canvas.transform(showreelCubeFace(size, angle, zoom).storage);
    canvas.drawImageRect(
      image,
      _coverSource(image, size),
      face,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.drawRect(
      face,
      Paint()..color = Color.fromRGBO(0, 0, 0, (1 - facing) * 0.55),
    );
    canvas.restore();
  }
}
