import 'dart:async';

import 'ad_pacing.dart';

/// What shows a loaded interstitial: the ads plugin in the app
/// (`AdService`), a fake in tests.
abstract class InterstitialPresenter {
  /// Whether an ad is loaded and fresh enough to show now.
  bool get ready;

  /// Shows the loaded ad. Completes when it closes, or at once when it
  /// could not show.
  Future<void> show();
}

/// How an interstitial over a running job is timed.
class WorkAdRule {
  const WorkAdRule({
    required this.leadIn,
    required this.evenIfQuick,
    this.minRemaining,
  });

  /// How long the job's own progress shows before the ad. AdMob recommends
  /// a "please wait" moment between a tap and an interstitial, so a quick
  /// second tap does not land on the ad.
  final Duration leadIn;

  /// Whether a job done inside [leadIn] still gets its ad — shown then,
  /// before whatever follows the job, never on top of it.
  final bool evenIfQuick;

  /// Only when at least this much is estimated still to go: an ad over a
  /// job about to end would make the ad the wait.
  final Duration? minRemaining;
}

/// Video compression (the owner's call, 2026-10-28): two seconds of its own
/// progress first, and only a job with about ten seconds or more to go.
const kVideoCompressionAdRule = WorkAdRule(
  leadIn: Duration(seconds: 2),
  evenIfQuick: false,
  minRemaining: Duration(seconds: 10),
);

/// Privacy Strip (the owner's call): every strip, however small or fast, a
/// second in.
const kPrivacyStripAdRule = WorkAdRule(
  leadIn: Duration(seconds: 1),
  evenIfQuick: true,
);

/// Photo compression: timed as Privacy Strip is. Photos compress in a
/// second or two, so the video rule — only with about ten seconds to go —
/// would almost never show one.
const kPhotoCompressionAdRule = kPrivacyStripAdRule;

/// Shows [placement]'s interstitial after a finished job, before what
/// follows it — the export's, before the finished video: only an ad already
/// loaded, only when [pacing] says one is due, only while [wanted]. Completes
/// once it has closed, or at once when none shows.
Future<void> adAfterWork({
  required AdPlacement placement,
  required AdPacing pacing,
  required InterstitialPresenter presenter,
  required bool Function() wanted,
}) async {
  if (!wanted() || !presenter.ready || !pacing.isDue(placement)) return;
  pacing.shown(placement);
  await presenter.show();
}

/// Shows [placement]'s interstitial over [work], a job already running, by
/// [rule]: never before the lead-in, never holding the job up, only an ad
/// already loaded, and only when [pacing] says one is due.
///
/// Completes once the job has ended **and** any ad has closed, so what
/// follows the job — its result, its report — comes after the ad, never
/// under it; a job that fails fails here too. [progress] is the job's, 0
/// to 1, read when the lead-in ends to judge how much is left. [wanted] is
/// asked right before the ad shows: a job left with Back, cancelled or
/// failed by then gets none, or the ad would land where nobody is waiting.
Future<void> adOverWork({
  required AdPlacement placement,
  required WorkAdRule rule,
  required Future<void> work,
  required double Function() progress,
  required bool Function() wanted,
  required AdPacing pacing,
  required InterstitialPresenter presenter,
  Future<void> Function(Duration)? delay,
  DateTime Function()? clock,
}) async {
  if (!pacing.isDue(placement)) return work;
  final now = clock ?? DateTime.now;
  final started = now();
  final quick = await Future.any([
    work.then((_) => true, onError: (_) => true),
    (delay ?? Future<void>.delayed)(rule.leadIn).then((_) => false),
  ]);

  Future<void> show() async {
    // Asked again at the moment: another ad may have shown meanwhile, and
    // the job may no longer be wanted.
    if (!wanted() || !presenter.ready || !pacing.isDue(placement)) return;
    pacing.shown(placement);
    await presenter.show();
  }

  if (quick) {
    if (rule.evenIfQuick) await show();
    return work;
  }

  final minRemaining = rule.minRemaining;
  if (minRemaining != null) {
    final done = progress();
    // No progress to speak of yet: a long job, as far as anyone can tell.
    if (done > 0.01) {
      final remaining = now().difference(started) * ((1 - done) / done);
      if (remaining < minRemaining) return work;
    }
  }
  await Future.wait([work, show()]);
}
