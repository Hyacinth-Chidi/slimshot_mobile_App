import 'dart:math' as math;
import 'dart:ui';

/// The camera preview's size as it is shown, from the buffer CameraX fills
/// and how far that buffer is turned to stand upright on the screen.
///
/// A phone's sensor is mounted on its side: the back camera hands over
/// 1920x1080 landscape buffers that show as a 1080x1920 portrait picture.
Size displayedPreviewSize(int bufferWidth, int bufferHeight, int rotationDegrees) {
  final quarterTurned = (rotationDegrees ~/ 90).isOdd;
  return quarterTurned
      ? Size(bufferHeight.toDouble(), bufferWidth.toDouble())
      : Size(bufferWidth.toDouble(), bufferHeight.toDouble());
}

/// How the preview texture is turned (clockwise quarter turns) and mirrored
/// to stand upright on the screen.
///
/// Straight from the camera ([cameraTransform]), the texture's own transform
/// already turns the sensor's picture upright for the phone's natural
/// orientation and mirrors a selfie — Flutter applies it when it draws the
/// texture — so only a screen turned from its natural way is left to undo.
/// Through a processor (an effect, stream sharing) the buffer arrives as
/// the sensor wrote it: turned by [rotation], then mirrored where [mirrored].
///
/// **The screen-turn case is unverified on a device**: the camera screen is
/// held upright, which on a phone is its natural orientation (0); only a
/// tablet whose natural orientation is landscape takes that branch.
({int quarterTurns, bool mirror}) previewTurns({
  required bool cameraTransform,
  required int rotation,
  required bool mirrored,
  required int displayRotation,
}) {
  if (cameraTransform) return (quarterTurns: (displayRotation ~/ 90) % 4, mirror: false);
  return (quarterTurns: (rotation ~/ 90) % 4, mirror: mirrored);
}

/// Where [picture] is drawn so that it covers [screen], centred, its shape
/// kept — the overflow is cropped, as every camera app's full-screen preview
/// is. An unknown picture size fills the screen as it is.
Rect previewCoverRect(Size picture, Size screen) {
  if (picture.width <= 0 || picture.height <= 0) {
    return Offset.zero & screen;
  }
  final scale = math.max(screen.width / picture.width, screen.height / picture.height);
  final drawn = Size(picture.width * scale, picture.height * scale);
  return Rect.fromCenter(
    center: screen.center(Offset.zero),
    width: drawn.width,
    height: drawn.height,
  );
}

/// The point to focus on for a tap at [tap] on [screen], as a fraction of the
/// **whole** picture — crop included — in the picture's upright orientation,
/// which is what CameraX's display-oriented metering expects. Null for a tap
/// outside the picture.
Offset? focusPointFor(Offset tap, Size screen, Size picture) {
  if (tap.dx < 0 || tap.dy < 0 || tap.dx > screen.width || tap.dy > screen.height) {
    return null;
  }
  final drawn = previewCoverRect(picture, screen);
  final x = (tap.dx - drawn.left) / drawn.width;
  final y = (tap.dy - drawn.top) / drawn.height;
  if (x < 0 || x > 1 || y < 0 || y > 1) return null;
  return Offset(x, y);
}

/// The zoom after a pinch that began at [start] has grown by [scale], held
/// within the camera's own range.
double zoomAfterPinch({
  required double start,
  required double scale,
  required double min,
  required double max,
}) =>
    (start * scale).clamp(min, max).toDouble();
