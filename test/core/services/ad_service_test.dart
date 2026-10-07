import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/ad_service.dart';

/// Ads are switched off for now. Every ad in the app goes through
/// [AdService], so with the switch off nothing waits on an ad and nothing an
/// ad used to unlock stays locked.
void main() {
  test('ads are off', () {
    expect(AdService.enabled, isFalse);
  });

  test('credit ads play the unit whose verification calls the server', () {
    // "earn credits" — the unit with server-side verification set. The old
    // rewarded unit (Pro unlocks) has none: an ad from it can never pay.
    expect(AdService.creditAdUnitIdAndroid,
        'ca-app-pub-7001751702275942/2451324896');
  });

  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      }),
    ));
    return captured;
  }

  testWidgets('a save that waited on an interstitial goes ahead at once',
      (tester) async {
    final context = await host(tester);
    var dismissed = 0;
    await AdService.showInterstitialAd(context, onAdDismissed: () => dismissed++);
    await tester.pump();
    expect(dismissed, 1);
    // No "Preparing..." loader waiting on an ad that will never come.
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Preparing...'), findsNothing);
  });

  testWidgets('what a rewarded ad unlocked is unlocked without one',
      (tester) async {
    final context = await host(tester);
    var earned = 0;
    var failed = 0;
    await AdService.showRewardedAd(
      context,
      onRewardEarned: () => earned++,
      onFailed: () => failed++,
    );
    expect((earned, failed), (1, 0));
  });

  test('nothing is loaded in the background', () {
    // Off, these return before reaching the ads plugin, which a test has no
    // platform side for — a call into it would throw here.
    AdService.loadInterstitialAd();
    AdService.loadRewardedAd();
  });
}
