import 'package:flutter/material.dart';

import '../../models/text_overlay_model.dart';
import '../animation/overlay_keyframes.dart';
import '../text_overlay_geometry.dart';
import '../text_look.dart';
import 'caption_grouping.dart';
import 'caption_highlight.dart';
import 'caption_preset_catalog.dart';

/// How much of the canvas width a caption may take before it wraps.
const double kCaptionWidthFraction = 0.86;

/// Where a caption's centre sits, as a fraction of the canvas from its centre:
/// a little over three quarters of the way down. Lower is where the apps that
/// play short-form video put their own caption and buttons.
const Offset kCaptionPlacement = Offset(0, 0.27);

/// [drafts] as text overlays of caption set [setId] on [lane], wearing [look]
/// and lighting their words with [highlight] at Size [fontSize] — the default
/// style unless told otherwise ([captionStyleForNewSet] decides it for a real
/// set).
///
/// **The size is a Size and the place the caption rule's, whatever the look**:
/// scale 1, the letters [fontSize] thousandths of the frame, the centre at
/// [kCaptionPlacement], so choosing a style never moves or resizes a set.
///
/// **The wrap width is [kCaptionWidthFraction] of the canvas**, the same for
/// every caption so they all wrap alike. A Size is the letters inside that
/// width, so a bigger Size re-wraps rather than run off the frame — the
/// reason a caption's size stopped being its scale.
List<TextOverlayModel> buildCaptionOverlays({
  required List<CaptionDraft> drafts,
  required String setId,
  required int lane,
  Size? canvasSize,
  CaptionHighlight highlight = kDefaultCaptionHighlight,
  TextLook look = kDefaultCaptionLook,
  double fontSize = kCaptionTextSize,
}) {
  final known = canvasSize != null && canvasSize.width > 0;
  final boxWidth = known ? canvasSize.width * kCaptionWidthFraction : null;
  final position = known
      ? Offset(
          kCaptionPlacement.dx * canvasSize.width,
          kCaptionPlacement.dy * canvasSize.height,
        )
      : Offset.zero;
  return [
    for (var i = 0; i < drafts.length; i++)
      look.applyTo(
        TextOverlayModel(
          id: '${setId}_$i',
          text: drafts[i].text,
          position: position,
          fontSize: fontSize,
          boxWidth: boxWidth,
          startTime: drafts[i].start,
          endTime: drafts[i].end,
          laneIndex: lane,
          referenceCanvasSize: canvasSize,
          captionSetId: setId,
          captionWords: drafts[i].words,
          highlight: highlight,
        ),
      ),
  ];
}

/// A caption saved before Sizes existed, converted to one — **exactly**.
///
/// Its size was in its scale then (a tenth of the canvas width over the old
/// 32 px letters) and its wrap width divided by that scale. Folding the scale
/// into a Size and multiplying the width back gives the same letters, insets
/// and line breaks at scale 1, so the set reads Size 100 like a new one and
/// nothing on the canvas moves. Left alone where that cannot be exact: a text
/// that is not a caption, one with a Size already, one with no reference
/// canvas to measure the frame by, one whose scale is keyframed (a zoom cannot
/// be one Size), or one whose Size would fall outside the ruler.
TextOverlayModel migrateLegacyCaptionSize(TextOverlayModel caption) {
  final frame = caption.referenceCanvasSize;
  if (!caption.isCaption || caption.fontSize != null || frame == null) {
    return caption;
  }
  if (caption.keyframes.of(OverlayProperty.scale).isNotEmpty) return caption;
  final scale = caption.scale;
  final size = textSizeOf(caption, frame) * scale;
  if (size < kMinTextSize || size > kMaxTextSize) return caption;
  final width = caption.boxWidth;
  return caption.copyWith(
    fontSize: size,
    scale: 1,
    boxWidth: width == null ? null : width * scale,
  );
}
