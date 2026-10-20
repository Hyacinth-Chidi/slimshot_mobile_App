import 'dart:math' as math;

import '../../models/media_asset.dart';

/// How long a new effect bar is — the length a new text gets.
const double kDefaultEffectBarSeconds = 3.0;

/// Where a new effect bar lands: at the playhead, [kDefaultEffectBarSeconds]
/// long, **inside the project** — so adding an effect never makes the project
/// longer.
///
/// Where fewer than three seconds remain it ends at the project's end; where
/// less than [kMinClipDurationSeconds] remains it starts earlier so it keeps
/// that minimum, the timeline's own.
({double start, double end}) newEffectBarSpan({
  required double playhead,
  required double projectEnd,
}) {
  final latestStart = math.max(0.0, projectEnd - kMinClipDurationSeconds);
  final start = playhead.clamp(0.0, latestStart).toDouble();
  var end = math.min(start + kDefaultEffectBarSeconds, projectEnd);
  if (end - start < kMinClipDurationSeconds) end = start + kMinClipDurationSeconds;
  return (start: start, end: end);
}
