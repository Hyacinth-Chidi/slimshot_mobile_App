import 'package:flutter/material.dart';

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
/// Also fixes the two settings every editor sheet already shared: the sheet
/// draws its own background (the sheet widget owns its colour, radius and grab
/// handle, so the route paints nothing), and it is scroll-controlled so a
/// sheet may take the height it needs on a short screen. A test scans `lib/`
/// for stray `showModalBottomSheet` calls, because a new sheet opened directly
/// would bring the tint back without anyone having chosen it.
Future<T?> showEditorSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: builder,
  );
}
