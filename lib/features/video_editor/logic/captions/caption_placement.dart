import 'package:flutter/material.dart';

import '../../models/text_overlay_model.dart';
import '../text_overlay_geometry.dart';
import '../text_template_catalog.dart';
import 'caption_grouping.dart';

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

/// The look captions wear until the styles stage: bold white type with a
/// black outline and a soft shadow — readable over any footage.
///
/// The font is **bundled**, not fetched: a caption has to look the same
/// offline, and on a phone whose system face is not the one a download would
/// have been. Not part of `kTextTemplates` — its size and wrap width come from
/// the canvas, which a template cannot express.
const TextTemplate captionDefaultTemplate = TextTemplate(
  id: 'caption_default',
  name: 'Caption',
  sampleText: 'Caption',
  fontFamily: 'Montserrat Bold',
  strokeColor: Color(0xFF000000),
  strokeWidth: 4,
  shadowColor: Color(0xFF000000),
  shadowOpacity: 0.6,
  shadowBlur: 6,
  shadowDistance: 2,
  shadowAngle: 90,
  placement: kCaptionPlacement,
);

/// The scale that makes a caption's type [kCaptionFontFraction] of
/// [canvasSize]'s width; a plain 1 while no canvas is known.
double captionScaleFor(Size? canvasSize) {
  if (canvasSize == null || canvasSize.width <= 0) return 1;
  return (canvasSize.width * kCaptionFontFraction / kTextOverlayFontSize)
      .clamp(kMinTextScale, kMaxTextScale)
      .toDouble();
}

/// [drafts] as text overlays of caption set [setId] on [lane].
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
}) {
  final scale = captionScaleFor(canvasSize);
  final boxWidth = canvasSize == null || canvasSize.width <= 0
      ? null
      : canvasSize.width * kCaptionWidthFraction / scale;
  return [
    for (var i = 0; i < drafts.length; i++)
      captionDefaultTemplate
          .apply(
            id: '${setId}_$i',
            startTime: drafts[i].start,
            endTime: drafts[i].end,
            canvasSize: canvasSize,
          )
          .copyWith(
            text: drafts[i].text,
            scale: scale,
            boxWidth: boxWidth,
            laneIndex: lane,
            captionSetId: setId,
            captionWords: drafts[i].words,
          ),
  ];
}
