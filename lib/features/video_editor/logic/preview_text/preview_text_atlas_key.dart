import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Size;

import '../../models/text_overlay_model.dart';
import '../text_overlay_geometry.dart';

/// The serialised fields of a text that change what its atlas looks like.
///
/// Everything else a text carries — where it is, when, how it moves, which
/// lane it is on — is drawn by *placing* the atlas, so changing it must not
/// make a new one. `preview_text_atlas_key_test.dart` holds every serialised
/// field to one side or the other.
const List<String> _drawnFields = [
  'text',
  'color',
  'fontFamily',
  'backgroundColor',
  'strokeColor',
  'strokeWidth',
  'shadowColor',
  'shadowBlurRadius',
  'shadowOpacity',
  'shadowDistance',
  'shadowAngle',
  'borderRadius',
  'backgroundPadding',
  'textAlign',
  'fontSize',
  'boxWidth',
  'refWidth',
  'refHeight',
  'highlight',
];

/// The scale a preview atlas is drawn at: the largest the text reaches,
/// rounded **up** to a quarter octave.
///
/// The export draws a text at its peak scale so a keyframed zoom ends sharp
/// (`textOverlayPeakScale`). The preview does the same, in steps, so that a
/// small pinch on a caption — which moves the whole set — makes no atlas
/// again unless it crosses a step. Rounding up keeps an atlas never softer
/// than the text on screen. The epsilon stops an exact step from being taken
/// for the one above it.
double previewAtlasScale(TextOverlayModel text) {
  final peak = textOverlayPeakScale(text);
  if (peak <= 0) return peak;
  final step = (4 * math.log(peak) / math.ln2 - 1e-9).ceil();
  return math.pow(2, step / 4).toDouble();
}

/// What a text's preview atlas depends on, and nothing else.
///
/// **Not the canvas's size on screen.** The atlas is drawn at canvas × the
/// texture's pixels per canvas pixel — the texture's own pixels — and text
/// is laid out relative to the canvas, so the same text on a resized canvas
/// is the same atlas. The keyboard and the tool panels resize the canvas all
/// the time; keyed on it, every atlas would be made again at each.
String previewTextAtlasKey(
  TextOverlayModel text, {
  required Size textureSize,
  required bool fontReady,
}) {
  final json = text.toJson();
  final words = text.captionWords;
  return jsonEncode([
    for (final field in _drawnFields) json[field],
    // Only where each word sits in the text is drawn — a highlight cell per
    // word. When it is spoken is timing, read by the engine every frame.
    if (words != null) [for (final w in words) [w.textStart, w.textEnd]],
    previewAtlasScale(text),
    textureSize.width,
    textureSize.height,
    fontReady,
  ]);
}
