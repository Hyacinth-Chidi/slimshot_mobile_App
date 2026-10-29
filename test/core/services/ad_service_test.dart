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
  test('every placement is on: the compressions and export',
      () {
    for (final placement in AdPlacement.values) {
      expect(AdService.isOn(placement), isTrue, reason: '$placement');
    }
  });

  test('credit ads play the unit whose verification calls the server', () {
    // "earn credits" — the unit with server-side verification set. The old
    // rewarded unit (Pro unlocks) has none: an ad from it can never pay.
    expect(AdService.creditAdUnitIdAndroid,
        'ca-app-pub-7001751702275942/2451324896');
  });

  // The owner's call: Best quality is unlocked by a rewarded ad, so a
  // compression at Best quality has already had its ad.
  test('a compression gets an interstitial unless it is at Best quality',
      () {
    for (final presets in [
      CompressionPresets.videoPresets,
      CompressionPresets.imagePresets,
    ]) {
      for (final preset in presets) {
        expect(compressionGetsInterstitial(preset), !preset.isPro,
            reason: preset.name);
      }
      expect(presets.where((p) => p.isPro).map((p) => p.name),
          ['Best quality']);
    }
  });

  // Save is the moment the user gets what they came for: an ad in front of
  // it makes them wait for their own file.
  test('saving a result never waits on an ad', () {
    for (final screen in [
      'lib/screens/result_screen.dart',
      // Its ad comes between the export and the finished video
      // (`showExportAd`), never on Save.
      'lib/screens/export_video_screen.dart',
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

  // Device-reported: Best quality tapped a moment after the screen opened
  // said "Check your connection" on a working connection — its ad was still
  // on the way, and the tap gave up on it at once. The tap waits, saying so;
  // here, with no ads plugin behind it, no ad can come, and it says that.
  testWidgets('an unlock waits for its ad, saying it is loading, and with '
      'none to be had says so — never blaming the connection', (tester) async {
    final context = await host(tester);
    var earned = 0;
    final failures = <UnlockFailure>[];
    unawaited(AdService.showRewardedAd(
      context,
      placement: AdPlacement.export,
      onRewardEarned: () => earned++,
      onFailed: failures.add,
    ));
    await tester.pump();
    expect(find.text('Loading ad…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Loading ad…'), findsNothing);
    expect(earned, 0);
    expect(failures, [UnlockFailure.noAd]);
  });

  test('an interstitial after a job, with none loaded, lets what follows go '
      'ahead at once', () async {
    var done = false;
    unawaited(AdService.afterWork(AdPlacement.export).then((_) => done = true));
    await pumpEventQueue();
    expect(done, isTrue);
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

  // Export's ad comes after it, never over it: the export runs on the
  // hardware codecs a video ad would share.
  test('nothing shows over an export while it runs', () async {
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
