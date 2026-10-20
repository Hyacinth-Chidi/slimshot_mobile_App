/// Which effect bars are drawn at an instant — the one rule the preview, the
/// export and the editor's warnings all follow.
///
/// **Written twice, pinned once.** The Kotlin `EffectStack` draws by this rule
/// on the canvas and in the file; `effect_stack_fixture.json` is generated
/// from this file and replayed there, so a bar cannot be drawn on one side and
/// skipped on the other without a test going red. As with every fixture here,
/// it catches divergence tomorrow, never a wrong rule today.
library;

import '../../models/effect_bar_model.dart';
import 'effect_catalog.dart';

/// One bar drawn at an instant.
class ActiveEffectBar {
  const ActiveEffectBar({
    required this.bar,
    required this.intensity,
    required this.progress,
  });

  final EffectBarModel bar;

  /// Resolved at the bar's own progress — the diamonds' clock — and clamped to
  /// the 0..1 every shader expects.
  final double intensity;

  /// The shader's clock: the intro window from the bar's start for a timed
  /// effect, the whole bar otherwise. Rests at 1.
  final double progress;
}

/// Where [seconds] falls in [bar], 0..1 — the clock its intensity keyframes
/// and envelope run on. A bar of no length is already over: 1, not a division
/// by zero.
double effectBarProgressAt(EffectBarModel bar, double seconds) {
  final span = bar.duration;
  if (span <= 0) return 1.0;
  return ((seconds - bar.start) / span).clamp(0.0, 1.0).toDouble();
}

/// The shader's progress for [bar] at [seconds]: across the effect's
/// `introSeconds` from the bar's start when the catalog gives one, resting at
/// 1 after it; across the whole bar otherwise.
double effectBarShaderProgressAt(EffectBarModel bar, double seconds) {
  final window = effectIntroSecondsFor(bar.effectId) ?? bar.duration;
  if (window <= 0) return 1.0;
  return ((seconds - bar.start) / window).clamp(0.0, 1.0).toDouble();
}

/// The bars drawn at [seconds], in the order they apply.
///
/// Bars with `start <= seconds < end` — half-open, so two bars meeting at a
/// seam never both draw there — whose effect the catalog knows, by lane
/// (nearest the clips first). Each costs its `passCount` out of
/// [kMaxEffectPasses]; a bar that does not fit is skipped **whole** — a blur
/// is never cut in half — and the walk goes on, so a later bar that does fit
/// still draws.
List<ActiveEffectBar> effectBarsDrawnAt(
  List<EffectBarModel> bars,
  double seconds,
) {
  final candidates = [
    for (final bar in bars)
      if (bar.start <= seconds &&
          seconds < bar.end &&
          videoEffectById(bar.effectId) != null)
        bar,
  ]..sort((a, b) => a.laneIndex.compareTo(b.laneIndex));

  var budget = kMaxEffectPasses;
  final drawn = <ActiveEffectBar>[];
  for (final bar in candidates) {
    final cost = videoEffectById(bar.effectId)!.passCount;
    if (cost > budget) continue;
    budget -= cost;
    drawn.add(ActiveEffectBar(
      bar: bar,
      intensity: bar.intensity
          .resolveAt(effectBarProgressAt(bar, seconds))
          .clamp(0.0, 1.0)
          .toDouble(),
      progress: effectBarShaderProgressAt(bar, seconds),
    ));
  }
  return drawn;
}

/// Every bar the budget skips at some instant.
///
/// The drawn set only changes at a bar's edge, so it is checked once inside
/// each stretch between consecutive edges, at the midpoint.
Set<String> skippedEffectBarIds(List<EffectBarModel> bars) {
  final edges = <double>{
    for (final bar in bars) ...[bar.start, bar.end],
  }.toList()
    ..sort();
  final skipped = <String>{};
  for (var i = 0; i + 1 < edges.length; i++) {
    final t = (edges[i] + edges[i + 1]) / 2;
    final drawn = {for (final a in effectBarsDrawnAt(bars, t)) a.bar.id};
    for (final bar in bars) {
      if (bar.start <= t &&
          t < bar.end &&
          videoEffectById(bar.effectId) != null &&
          !drawn.contains(bar.id)) {
        skipped.add(bar.id);
      }
    }
  }
  return skipped;
}

/// A bar that [after] skips and [before] did not, or null — what an edit owes
/// the user one toast about. A bar already skipped is not named again on
/// every later edit.
EffectBarModel? newlySkippedEffectBar(
  List<EffectBarModel> before,
  List<EffectBarModel> after,
) {
  if (identical(before, after)) return null;
  final was = skippedEffectBarIds(before);
  final now = skippedEffectBarIds(after);
  for (final bar in after) {
    if (now.contains(bar.id) && !was.contains(bar.id)) return bar;
  }
  return null;
}
