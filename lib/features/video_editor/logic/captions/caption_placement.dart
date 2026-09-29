import 'dart:ui';

import '../../models/text_overlay_model.dart';
import '../text_template_catalog.dart';
import 'caption_grouping.dart';

/// The look captions wear until the styles stage: the Subtitle template —
/// white, a black outline, a soft shadow, in the lower third.
final TextTemplate captionDefaultTemplate =
    kTextTemplates.firstWhere((t) => t.id == 'subtitle');

/// [drafts] as text overlays of caption set [setId] on [lane].
///
/// **No in/out animation**, whatever the template carries: a half-second fade
/// on a one-second caption is most of its life. `boxWidth` stays unset — every
/// caption shares one reference canvas, so every caption already wraps at the
/// same width, and a boxed style's background still hugs its words.
List<TextOverlayModel> buildCaptionOverlays({
  required List<CaptionDraft> drafts,
  required String setId,
  required int lane,
  Size? canvasSize,
}) {
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
            inAnimation: 'none',
            outAnimation: 'none',
            loopAnimation: 'none',
            laneIndex: lane,
            captionSetId: setId,
            captionWords: drafts[i].words,
          ),
  ];
}
