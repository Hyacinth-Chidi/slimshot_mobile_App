import 'package:flutter/material.dart';

import '../../models/text_overlay_model.dart';
import '../text_overlay_geometry.dart';
import '../text_look.dart';
import 'caption_grouping.dart';
import 'caption_highlight.dart';
import 'caption_preset_catalog.dart';

/// A caption's type size, as a fraction of the canvas **width**.
///
/// A fraction, not a scale: a text's size is stored in the pixels of the
/// canvas it was made on, and that canvas is whatever the phone left room
/// for — so one fixed scale gave a caption that was large on one phone and
/// small on the next. At a tenth of the width a three-word phrase sits on one
/// line and a full line wraps to two.
const double kCaptionFontFraction = 0.10;

/// How much of the canvas width a caption may take before it wraps.
const double kCaptionWidthFraction = 0.86;

/// Where a caption's centre sits, as a fraction of the canvas from its centre:
/// a little over three quarters of the way down. Lower is where the apps that
/// play short-form video put their own caption and buttons.
const Offset kCaptionPlacement = Offset(0, 0.27);

/// The scale that makes a caption's type [kCaptionFontFraction] of
/// [canvasSize]'s width; a plain 1 while no canvas is known.
double captionScaleFor(Size? canvasSize) {
  if (canvasSize == null || canvasSize.width <= 0) return 1;
  return (canvasSize.width * kCaptionFontFraction / kTextOverlayFontSize)
      .clamp(kMinTextScale, kMaxTextScale)
      .toDouble();
}

/// [drafts] as text overlays of caption set [setId] on [lane], wearing [look]
/// and lighting their words with [highlight].
///
/// **The size and place are the caption rule's, whatever the look**: the type
/// is [kCaptionFontFraction] of the canvas width and the centre sits at
/// [kCaptionPlacement], so choosing a style never moves or resizes a set.
///
/// **The wrap width is divided by the scale.** A text's box is laid out first
/// and scaled after, so a box as wide as the canvas, scaled up, runs off both
/// edges; every caption gets the one `boxWidth` that lands on
/// [kCaptionWidthFraction] of the canvas once scaled, so they all wrap alike.
List<TextOverlayModel> buildCaptionOverlays({
  required List<CaptionDraft> drafts,
  required String setId,
  required int lane,
  Size? canvasSize,
  CaptionHighlight highlight = CaptionHighlight.none,
  TextLook look = kCaptionDefaultLook,
}) {
  final scale = captionScaleFor(canvasSize);
  final known = canvasSize != null && canvasSize.width > 0;
  final boxWidth = known ? canvasSize.width * kCaptionWidthFraction / scale : null;
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
          scale: scale,
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
