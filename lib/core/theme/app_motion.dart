import 'package:flutter/material.dart';

/// The editor's motion, in one place.
///
/// Sheets and the bottom tool panels are one family — the same surface
/// arriving from the same edge — and they used to move on three different
/// clocks: Flutter's stock sheet (250ms in, 200ms out, its own curve), the
/// panel switcher (300ms `easeOutCubic`, 40% nudge) and the `AnimatedSize`
/// around it (300ms). Three timings for one gesture read as three apps.
/// Everything that opens, closes or resizes in the editor's bottom area takes
/// its duration and curve from here, so a change is one edit and the pieces
/// can never drift apart again.
///
/// The values are Material 3's *emphasized* motion: an arriving surface
/// decelerates into place over [enter] and a leaving one accelerates away over
/// the shorter [exit] — leaving is always quicker than arriving, which is what
/// makes a dismissal feel crisp rather than sluggish. The sheet route fixes its
/// own curve internally, so [sheet] carries only the durations; the panel
/// switcher applies both curves.
abstract final class AppMotion {
  /// How long an arriving surface, or a growing container, takes.
  static const Duration enter = Duration(milliseconds: 380);

  /// How long a leaving surface takes. Shorter than [enter] on purpose.
  static const Duration exit = Duration(milliseconds: 260);

  /// Arrivals: fast off the mark, settling gently.
  static const Curve enterCurve = Easing.emphasizedDecelerate;

  /// Departures: a soft start, then gone.
  static const Curve exitCurve = Easing.emphasizedAccelerate;

  /// For `showModalBottomSheet`'s `sheetAnimationStyle`. Durations only — the
  /// route ignores an `AnimationStyle`'s curves and applies its own.
  static const AnimationStyle sheet = AnimationStyle(
    duration: enter,
    reverseDuration: exit,
  );
}
