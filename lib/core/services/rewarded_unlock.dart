import 'dart:async';

/// Why an unlock got no reward.
enum UnlockFailure {
  /// The ad was closed before its reward.
  closedEarly,

  /// The ad could not load for want of a network (AdMob's network error).
  offline,

  /// No ad to be had: none to fill the request, ads not to be asked for
  /// yet, or none in time.
  noAd,
}

/// The line a failed unlock of [what] ("Best quality", "4K") shows — the
/// cause it actually had. "Check your connection" on a working connection,
/// for an ad that was still loading, was device-reported.
String unlockFailureMessage(UnlockFailure failure, String what) =>
    switch (failure) {
      UnlockFailure.closedEarly => 'Watch the ad to the end to unlock $what.',
      UnlockFailure.offline => 'No internet connection.',
      UnlockFailure.noAd => 'No ad right now. Try again in a moment.',
    };

/// Waits for a rewarded ad an unlock can show: [start] — Google's consent
/// step and the SDK, null once ads may be asked for — then one already
/// [ready], else the [load] on its way (null once it has loaded, otherwise
/// why not), all within [within]. Null when an ad is ready.
///
/// An unlock tapped a moment after its screen opened meets its ad still on
/// the way, and used to give up on it at once.
Future<UnlockFailure?> awaitRewardedAd({
  required Future<String?> Function() start,
  required bool Function() ready,
  required Future<UnlockFailure?> Function() load,
  required Duration within,
}) {
  Future<UnlockFailure?> wait() async {
    if (await start() != null) return UnlockFailure.noAd;
    if (ready()) return null;
    final failure = await load();
    if (failure != null) return failure;
    return ready() ? null : UnlockFailure.noAd;
  }

  return wait().timeout(within, onTimeout: () => UnlockFailure.noAd);
}
