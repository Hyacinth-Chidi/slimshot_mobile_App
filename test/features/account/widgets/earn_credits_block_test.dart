import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/account/services/credit_ads.dart';
import 'package:slimshotai/features/account/widgets/earn_credits_block.dart';

import '../../../support/account_fakes.dart';
import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  late FakeRewardedAdPlayer ads;
  late List<String> shared;
  late List<int> earned;

  setUp(() {
    // The server's own balance: the grant moves it, and the /me read after
    // every ad must agree with what the grant answered.
    var balance = 0;
    server = FakeServer()
      ..on('GET', '/me', (_) => envelope(userJson(balance: balance)))
      ..on('POST', '/rewards/ads/session', (_) => envelope({
            'nonce': 'n1',
            'ssvUserId': 'u1',
            'rewardCredits': 5,
            'adsRemainingToday': 9,
          }))
      ..on('GET', '/rewards/ads/session/n1', (_) {
        balance = 5;
        return envelope({'status': 'granted', 'credits': 5, 'balance': 5});
      });
    ads = FakeRewardedAdPlayer();
    shared = [];
    earned = [];
  });

  Future<ProviderContainer> pumpBlock(
    WidgetTester tester, {
    Map<String, Object?>? profile,
    bool adsOn = true,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...accountOverrides(
          server,
          session: signedInSession(profile: profile ?? userJson(balance: 0)),
          ads: ads,
          shared: shared,
        ),
        creditAdsEnabledProvider.overrideWithValue(adsOn),
      ],
      child: MaterialApp(
        home: Scaffold(body: EarnCreditsBlock(onEarned: earned.add)),
      ),
    ));
    await settle(tester);
    return containerOf(tester);
  }

  testWidgets('offers the ad with its reward and what is left today',
      (tester) async {
    await pumpBlock(tester);
    expect(find.text('Watch an ad · +5'), findsOneWidget);
    expect(find.text('10 left today'), findsOneWidget);
    expect(find.text('Invite a friend'), findsOneWidget);
  });

  testWidgets("a watched ad shows the server's balance and says so",
      (tester) async {
    final c = await pumpBlock(tester);
    await tester.tap(find.byKey(const Key('earn_watch_ad')));
    await settle(tester);

    expect(ads.plays, [('u1', 'n1')]);
    expect(c.read(accountProvider).user!.creditBalance, 5);
    expect(earned, [5]);
    expect(find.text('+5 credits'), findsOneWidget);
  });

  testWidgets('at the cap the button is Back tomorrow and plays nothing',
      (tester) async {
    final capped = userJson(balance: 0)
      ..['ads'] = {'rewardCredits': 5, 'dailyCap': 10, 'remainingToday': 0};
    server.on('GET', '/me', (_) => envelope(capped));
    await pumpBlock(tester, profile: capped);
    expect(find.text('Back tomorrow'), findsOneWidget);
    await tester.tap(find.byKey(const Key('earn_watch_ad')));
    await settle(tester);
    expect(ads.plays, isEmpty);
  });

  testWidgets('with credit ads switched off, only the invite is offered',
      (tester) async {
    await pumpBlock(tester, adsOn: false);
    expect(find.byKey(const Key('earn_watch_ad')), findsNothing);
    expect(find.byKey(const Key('earn_invite')), findsOneWidget);
  });

  testWidgets("Invite a friend shares the user's own code", (tester) async {
    await pumpBlock(tester);
    await tester.tap(find.byKey(const Key('earn_invite')));
    await settle(tester);
    expect(shared.single, contains('AB3DEF7K'));
  });

  testWidgets('no ad to show says so and changes nothing', (tester) async {
    ads.playback = AdPlayback.notShown;
    final c = await pumpBlock(tester);
    await tester.tap(find.byKey(const Key('earn_watch_ad')));
    await settle(tester);
    expect(find.text('No ad right now. Try again soon.'), findsOneWidget);
    expect(c.read(accountProvider).user!.creditBalance, 0);
    expect(earned, isEmpty);
  });
}
