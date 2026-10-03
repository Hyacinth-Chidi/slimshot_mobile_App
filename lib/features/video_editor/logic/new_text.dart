import 'package:flutter/widgets.dart';

import '../models/text_overlay_model.dart';
import 'text_template_catalog.dart';

/// The face a new plain text starts in.
///
/// **Bundled**, so a first text looks the same offline and on a phone whose
/// system face is not the one a download would have been. Only *new* text
/// starts here: the model's own default, and a draft that names no face, stay
/// Roboto — what every text made before this was made in.
const String kNewTextFontFamily = 'Montserrat Bold';

/// A new, **empty** text from [start] to [end] — plain, or wearing [template].
///
/// Empty whatever made it: the editor deletes a text still empty when it
/// closes, so nothing the user did not type can reach an export.
TextOverlayModel newText({
  required String id,
  required Duration start,
  required Duration end,
  Size? canvasSize,
  TextTemplate? template,
}) =>
    template?.apply(
      id: id,
      startTime: start,
      endTime: end,
      canvasSize: canvasSize,
    ) ??
    TextOverlayModel(
      id: id,
      text: '',
      fontFamily: kNewTextFontFamily,
      // The same Size on every phone — see [TextOverlayModel.fontSize].
      fontSize: kDefaultTextSize,
      startTime: start,
      endTime: end,
      referenceCanvasSize: canvasSize,
    );
