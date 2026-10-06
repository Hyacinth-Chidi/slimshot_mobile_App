import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/account/services/account_service.dart';
import 'package:slimshotai/features/account/services/credit_ads.dart';

import '../../../support/account_fakes.dart';
import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  late FakeRewardedAdPlayer player;
  late DateTime now;
  late List<String> statuses; // what each poll answers, in order

  setUp(() {
    server = FakeServer()
      ..on('POST', '/rewards/ads/session', (_) => envelope({
            'nonce': 'n1',
            'ssvUserId': 'u1',
            'rewardCredits': 5,
            'adsRemainingToday': 7,
          }));
    player = FakeRewardedAdPlayer();
    now = DateTime(2026, 10, 6);
    statuses = [];
    server.on('GET', '/rewards/ads/session/n1', (_) {
      final status = statuses.isEmpty ? 'pending' : statuses.removeAt(0);
      return envelope(status == 'granted'
          ? {'status': 'granted', 'credits': 5, 'balance': 99}
          : {'status': status});
    });
  });

  CreditAdService ads() => CreditAdService(
        account: AccountService(fakeApi(server, session: signedInSession())),
        player: player,
        delay: (d) async => now = now.add(d),
        clock: () => now,
      );

  int polls() => server.to('GET', '/rewards/ads/session/n1').length;

  test('the ad carries the session for verification, then the grant is read',
      () async {
    statuses = ['pending', 'pending', 'granted'];
    final reward = await ads().watch();
    expect(player.plays, [('u1', 'n1')]);
    expect((reward.outcome, reward.credits, reward.balance),
        (AdRewardOutcome.granted, 5, 99));
    expect(polls(), 3);
  });

  test('still pending after 30s: on its way', () async {
    final reward = await ads().watch();
    expect(reward.outcome, AdRewardOutcome.pending);
    expect(polls(), 30);
  });

  test('an ad closed early waits briefly, then says to watch to the end',
      () async {
    player.playback = AdPlayback.closed;
    final reward = await ads().watch();
    expect(reward.outcome, AdRewardOutcome.notEarned);
    expect(polls(), 5);
  });

  test('a grant still counts when the ad closed early', () async {
    player.playback = AdPlayback.closed;
    statuses = ['granted'];
    expect((await ads().watch()).outcome, AdRewardOutcome.granted);
  });

  test('capped and rejected end the poll', () async {
    statuses = ['capped'];
    expect((await ads().watch()).outcome, AdRewardOutcome.capped);
    statuses = ['rejected'];
    expect((await ads().watch()).outcome, AdRewardOutcome.rejected);
  });

  test('no ad to show asks nothing more', () async {
    player.playback = AdPlayback.notShown;
    expect((await ads().watch()).outcome, AdRewardOutcome.noAd);
    expect(polls(), 0);
  });

  test('the daily cap plays nothing', () async {
    server.on('POST', '/rewards/ads/session',
        (_) => failure('AD_DAILY_CAP_REACHED', 409));
    expect((await ads().watch()).outcome, AdRewardOutcome.dailyCap);
    expect(player.plays, isEmpty);
  });

  test('a dropped poll is ridden out', () async {
    var calls = 0;
    server.on('GET', '/rewards/ads/session/n1', (_) {
      if (calls++ == 0) throw http.ClientException('connection reset');
      return envelope({'status': 'granted', 'credits': 5, 'balance': 99});
    });
    expect((await ads().watch()).outcome, AdRewardOutcome.granted);
  });

  test('each outcome reads as one line', () {
    expect(adRewardMessage(const AdReward(AdRewardOutcome.granted, credits: 5)),
        '+5 credits');
    expect(adRewardMessage(const AdReward(AdRewardOutcome.capped)),
        "That's today's last reward");
    expect(adRewardMessage(const AdReward(AdRewardOutcome.rejected)),
        'No reward this time');
    expect(adRewardMessage(const AdReward(AdRewardOutcome.notEarned)),
        'Watch to the end to earn credits');
    expect(adRewardMessage(const AdReward(AdRewardOutcome.pending)),
        'Your reward is on its way');
    expect(adRewardMessage(const AdReward(AdRewardOutcome.noAd)),
        'No ad right now. Try again soon.');
    expect(adRewardMessage(const AdReward(AdRewardOutcome.dailyCap)),
        'Back tomorrow');
  });

  test('a session the server refuses for another reason is not swallowed',
      () async {
    server.on('POST', '/rewards/ads/session',
        (_) => failure('ACCOUNT_SUSPENDED', 403));
    await expectLater(
      ads().watch(),
      throwsA(isA<SlimshotApiException>()
          .having((e) => e.code, 'code', 'ACCOUNT_SUSPENDED')),
    );
  });

  test('a poll the server or a proxy fails is ridden out too', () async {
    var calls = 0;
    server.on('GET', '/rewards/ads/session/n1', (_) {
      if (calls++ == 0) return failure('INTERNAL_ERROR', 502);
      return envelope({'status': 'granted', 'credits': 5, 'balance': 99});
    });
    expect((await ads().watch()).outcome, AdRewardOutcome.granted);
  });

  test('a session that has ended is not ridden out', () async {
    server.on('GET', '/rewards/ads/session/n1',
        (_) => failure('NOT_FOUND', 404));
    await expectLater(ads().watch(), throwsA(isA<SlimshotApiException>()));
  });
}
