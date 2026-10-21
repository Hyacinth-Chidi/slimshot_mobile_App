import 'dart:math' as math;

import '../../models/media_asset.dart';
import '../animation/animatable_double.dart';
import 'effect_catalog.dart';

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

/// What a bar wears when [effect] is first put on it: the catalog's strength
/// and envelope, no keyframes. A new bar and an effect tile's sample bar both
/// start here, so the tile shows the strength a tap gives.
AnimatableDouble freshEffectIntensity(VideoEffect effect) => AnimatableDouble(
      baseValue: effect.defaultIntensity,
      envelope: effect.defaultEnvelope,
    );
