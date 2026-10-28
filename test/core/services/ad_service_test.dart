import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/ad_service.dart';
import 'package:slimshotai/core/services/ads_sdk.dart';
import 'package:slimshotai/features/compression/logic/compression_ads.dart';
import 'package:slimshotai/features/compression/logic/compression_presets.dart';

/// Ads come back one placement at a time, each on its own switch (the
/// owner's call, 2026-10-28). Every ad in the app goes through
/// [AdService], so where a placement is off nothing waits on an ad and
/// nothing an ad used to unlock stays locked.
void main() {
  test('video compression and Privacy Strip are on; the rest wait their turn',
      () {
    expect(AdService.isOn(AdPlacement.videoCompression), isTrue);
    expect(AdService.isOn(AdPlacement.privacyStrip), isTrue);
    // Next to be talked through: the editor's export.
    expect(AdService.isOn(AdPlacement.export), isFalse);
    expect(AdService.isOn(AdPlacement.photoCompression), isFalse);
  });

  test('credit ads play the unit whose verification calls the server', () {
    // "earn credits" — the unit with server-side verification set. The old
    // rewarded unit (Pro unlocks) has none: an ad from it can never pay.
    expect(AdService.creditAdUnitIdAndroid,
        'ca-app-pub-7001751702275942/2451324896');
  });

  // The owner's call: Best quality is unlocked by a rewarded ad, so a
  // compression at Best quality has already had its ad.
  test('a video compression gets an interstitial unless it is at Best quality',
      () {
    for (final preset in CompressionPresets.videoPresets) {
      expect(compressionGetsInterstitial(preset), !preset.isPro,
          reason: preset.name);
    }
    expect(
      CompressionPresets.videoPresets.where((p) => p.isPro).map((p) => p.name),
      ['Best quality'],
    );
  });

  // Save is the moment the user gets what they came for: an ad in front of
  // it makes them wait for their own file.
  test('saving a result never waits on an ad', () {
    for (final screen in [
      'lib/screens/result_screen.dart',
      'lib/screens/privacy_result_screen.dart',
    ]) {
      expect(File(screen).readAsStringSync(), isNot(contains('AdService')),
          reason: screen);
    }
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

  testWidgets('where ads are off, a step that waited on an interstitial goes '
      'ahead at once', (tester) async {
    final context = await host(tester);
    var dismissed = 0;
    await AdService.showInterstitialAd(
      context,
      placement: AdPlacement.export,
      onAdDismissed: () => dismissed++,
    );
    await tester.pump();
    expect(dismissed, 1);
    // No "Preparing..." loader waiting on an ad that will never come.
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Preparing...'), findsNothing);
  });

  testWidgets('where ads are off, what a rewarded ad unlocked is unlocked '
      'without one', (tester) async {
    final context = await host(tester);
    for (final placement in [AdPlacement.export, AdPlacement.photoCompression]) {
      var earned = 0;
      var failed = 0;
      await AdService.showRewardedAd(
        context,
        placement: placement,
        onRewardEarned: () => earned++,
        onFailed: () => failed++,
      );
      expect((earned, failed), (1, 0), reason: '$placement');
    }
  });

  // In the EEA, the UK and Switzerland an ad may be asked for only once
  // Google's consent step allows it. Asking the plugin here — a test has no
  // platform side — would fail the test with the plugin's error.
  test('no ad is asked for before the consent step has started the SDK',
      () async {
    expect(AdsSdk.started, isFalse);
    AdService.loadInterstitialAd();
    AdService.loadRewardedAd();
    await pumpEventQueue();
  });

  test('a placement that is off loads nothing', () async {
    // Off, these return before reaching the ads plugin, which a test has no
    // platform side for.
    await AdService.prepare(AdPlacement.export);
    await AdService.prepare(AdPlacement.photoCompression);
  });

  test('a job under a placement that is off is the job alone', () async {
    final work = Completer<void>();
    var done = false;
    unawaited(AdService.overWork(
      AdPlacement.export,
      work: work.future,
      progress: () => 0,
    ).then((_) => done = true));
    await pumpEventQueue();
    expect(done, isFalse);
    work.complete();
    await pumpEventQueue();
    expect(done, isTrue);
  });
}
