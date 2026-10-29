import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/rewarded_unlock.dart';

/// An unlock that waits for its rewarded ad. Device-reported: tapping Best
/// quality a moment after the screen opened said "Check your connection"
/// on a working connection — the ad was still on its way (the consent step,
/// the SDK, the load) and the tap gave up on it at once.
void main() {
  late Completer<UnlockFailure?> load;
  late bool ready;
  late int loads;

  setUp(() {
    load = Completer<UnlockFailure?>();
    ready = false;
    loads = 0;
  });

  Future<UnlockFailure?> wait({
    Future<String?> Function()? start,
    Duration within = const Duration(seconds: 5),
  }) =>
      awaitRewardedAd(
        start: start ?? () async => null,
        ready: () => ready,
        load: () {
          loads++;
          return load.future;
        },
        within: within,
      );

  test('an ad already loaded is ready at once', () async {
    ready = true;
    expect(await wait(), isNull);
    expect(loads, 0);
  });

  test('an ad on its way is waited for, not given up on', () async {
    UnlockFailure? failure = UnlockFailure.noAd;
    var done = false;
    unawaited(wait().then((f) {
      failure = f;
      done = true;
    }));
    await pumpEventQueue();
    expect(done, isFalse, reason: 'still loading');
    ready = true;
    load.complete(null);
    await pumpEventQueue();
    expect(done, isTrue);
    expect(failure, isNull);
  });

  test('a load that fails for want of a network says so', () async {
    load.complete(UnlockFailure.offline);
    expect(await wait(), UnlockFailure.offline);
  });

  test('no ad to be had is not called a connection problem', () async {
    load.complete(UnlockFailure.noAd);
    expect(await wait(), UnlockFailure.noAd);
  });

  test('ads that may not be asked for yet are no ad, not no internet',
      () async {
    expect(await wait(start: () async => 'consent not given'),
        UnlockFailure.noAd);
    expect(loads, 0);
  });

  test('a load that does not answer in time is given up as no ad', () async {
    expect(await wait(within: const Duration(milliseconds: 10)),
        UnlockFailure.noAd);
  });

  test('each failure is worded for what it is', () {
    expect(unlockFailureMessage(UnlockFailure.offline, 'Best quality'),
        'No internet connection.');
    expect(unlockFailureMessage(UnlockFailure.noAd, 'Best quality'),
        'No ad right now. Try again in a moment.');
    expect(unlockFailureMessage(UnlockFailure.closedEarly, '4K'),
        'Watch the ad to the end to unlock 4K.');
  });
}
