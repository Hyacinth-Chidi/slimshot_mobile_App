import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';

/// Opens a sheet over the editor, and **the canvas stays clear behind it**.
///
/// Every editor sheet — transitions, transform, filters, effects, the curve
/// picker, the cover picker, the text editor — goes through this one call.
/// Flutter's default sheet dims everything behind it with `black54`, which is
/// the wrong instinct here: a sheet in this editor is a set of choices *about*
/// the picture, and the user is looking at the picture to make them. A curve
/// is judged by how the clip moves, a filter by how the frame looks; dimming
/// the frame while the sheet is up muddied exactly the thing being compared.
/// The barrier is still there — a tap outside still closes the sheet — it
/// simply paints nothing.
///
/// Also fixes the settings every editor sheet already shared: the sheet draws
/// its own background (the sheet widget owns its colour, radius and grab
/// handle, so the route paints nothing), it is scroll-controlled so a sheet
/// may take the height it needs on a short screen, and it moves on
/// [AppMotion] — the same timing the bottom tool panels use, so a sheet and a
/// panel arrive and leave as one family. A test scans `lib/` for stray
/// `showModalBottomSheet` calls, because a new sheet opened directly would
/// bring the tint and the stock timing back without anyone having chosen them.
/// The most of the screen a sheet may take when its choices are judged on the
/// picture — Background, Filters, Effects, Transitions, the clip animations.
///
/// Device-reported: a sheet at half the screen hid the very frame the user was
/// choosing for. 45% keeps the canvas comfortably visible above it; a sheet
/// with more to show scrolls inside the cap. Browsers of *libraries* (audio,
/// stickers) are not about the picture and keep their own, taller height.
const double kEditorSheetPreviewFraction = 0.45;

Future<T?> showEditorSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    sheetAnimationStyle: AppMotion.sheet,
    builder: builder,
  );
}
