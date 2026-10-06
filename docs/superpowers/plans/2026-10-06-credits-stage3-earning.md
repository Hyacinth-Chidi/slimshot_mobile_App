# Credits Stage 3 — Earning — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A signed-in user can earn credits by watching a rewarded ad (verified on the server, SSV) or inviting a friend — from the caption shortfall ("Needs 30 credits · You have 0") and from a new Credits screen that also shows the balance and the history.

**Architecture:** `AccountService` gains the ad-session, ad-poll and history endpoints. `CreditAdService` runs one rewarded ad end to end — session, a `RewardedAdPlayer` (the `google_mobile_ads` plugin behind an interface, faked in tests) shown with the session's SSV options, then a poll of the session — and returns an `AdReward` outcome; **the app never adds credits itself**, it shows the balance the server answers. `EarnCreditsBlock` is the one UI for earning (Watch an ad, Invite a friend), used by the caption sheet's shortfall and by `CreditsScreen`. Credit ads get their own switch, on; `AdService.enabled` (interstitials, Pro-unlock ads) stays off.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, Riverpod, `google_mobile_ads` 8.0.0, `share_plus` 10.1.4 (`Share.share`), `timeago`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-05-app-accounts-credits-design.md` — §3 D and E (ad unit, switch), §4.1 (pill opens Credits), §4.4 (shortfall: Watch an ad · +5, Invite a friend; revised 2026-10-06: a covered shortfall goes straight on), §4.5 (Credits screen), §4.6 (Settings Credits row), §4.7 (ad flow), §8 stage 3. Server contract: `slimshot_server/docs/app-credits-api.md` §6 (`/me.ads`), §8 (referral codes), §10 (history), §13 (rewarded ads), §14 (`AD_DAILY_CAP_REACHED`).

## Global Constraints

- Work on the branch `feat/credits-stage3` (cut from `main`, carrying this plan). Never push or merge.
- Test-first; watch each test fail. `flutter analyze --no-pub` stays at exactly **48**. Full `flutter test` at the end of every task.
- **The app never grants credits.** A balance only ever comes from the server (`granted.balance`, `/me`).
- **A new ad session for every ad**; SSV options (`userId = ssvUserId`, `customData = nonce`) set **before** `show`.
- `AdService.enabled` stays **false**. Credit ads use the new `AdService.creditAdsEnabled` (**true**). The ads SDK starts when either is on.
- Copy, exactly: `"Watch an ad · +5"`, `"7 left today"`, `"Back tomorrow"`, `"Invite a friend"`, `"+5 credits"`, `"That's today's last reward"`, `"No reward this time"`, `"Your reward is on its way"`, `"Watch to the end to earn credits"`, `"No ad right now. Try again soon."`, screen title `"Credits"`. One line each, no titles on toasts.
- Colours from `AppColors`; the Credits screen wears the home look (`ColourFieldBackdrop`, `FrostedGlass`); inside the editor the block stays plain (CLAUDE.md: the editor stays dark).
- Screens and sheets reachable from a tab open on the **root** navigator (the floating nav).
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **An ad closed early** (no `onUserEarnedReward`) must not leave the user staring at a 30-second wait that ends "on its way" → Task 2, "an ad closed early waits briefly, then says to watch to the end".
2. **A late ad load** (after the load timeout) must not leak a loaded ad or show it later → Task 2 plugin player: a load landing after the timeout is disposed (code, reviewed; the plugin cannot run in tests).
3. **The daily cap** reached at session time hides the button as "Back tomorrow" and plays nothing → Task 2 "the daily cap plays nothing", Task 3 "at the cap the button is Back tomorrow".
4. **An ad that covers the shortfall** must carry the run on (upload), one that does not must update the line, never upload → Task 4.
5. **A dropped poll** on a mobile connection is ridden out, not reported as a failure → Task 2 "a dropped poll is ridden out".

---

## File Structure

| File | Responsibility |
| :--- | :--- |
| `lib/features/account/models/account_models.dart` (modify) | `AdAllowance` (+ `AccountUser.ads`), `AdSession`, `AdSessionStatus`, `CreditEntry`, `CreditHistoryPage`. |
| `lib/features/account/services/account_service.dart` (modify) | `startAdSession`, `adSession(nonce)`, `history({cursor})`. |
| `lib/features/account/logic/account_copy.dart` (modify) | History labels, amounts, ad messages, the invite text. |
| `lib/features/account/services/credit_ads.dart` (create) | `RewardedAdPlayer`, `AdPlayback`, `PluginRewardedAdPlayer`, `AdReward`, `AdRewardOutcome`, `CreditAdService`. |
| `lib/core/services/ad_service.dart` (modify) | `creditAdsEnabled`; `rewardedAdUnitId` made public. |
| `lib/main.dart` (modify) | SDK starts when either switch is on; interstitial/rewarded preloads stay behind `enabled`. |
| `lib/features/account/providers/account_providers.dart` (modify) | `creditAdsEnabledProvider`, `rewardedAdPlayerProvider`, `creditAdServiceProvider`, `shareTextProvider`. |
| `lib/features/account/widgets/earn_credits_block.dart` (create) | Watch an ad · +N / N left today / Back tomorrow; Invite a friend. |
| `lib/features/video_editor/widgets/panels/caption_progress_sheet.dart` (modify) | `earnCredits` builder under the shortfall line; covered → the run goes on. |
| `lib/screens/video_editor_screen.dart` (modify) | Passes `EarnCreditsBlock` to the sheet. |
| `lib/features/account/screens/credits_screen.dart` (create) | Balance, the block, history (paged). |
| `lib/features/account/widgets/credits_pill.dart` (modify) | Signed in and claimed: tap opens Credits. |
| `lib/features/account/widgets/settings_account_section.dart` (modify) | A Credits row. |
| `test/support/account_harness.dart` (modify) | `FakeRewardedAdPlayer`; `accountOverrides(ads:, shared:)`. |
| `CLAUDE.md` (modify) | Stage 3 section. |

---

### Task 1: The earning endpoints, models and wording

**Files:**
- Modify: `lib/features/account/models/account_models.dart`
- Modify: `lib/features/account/services/account_service.dart`
- Modify: `lib/features/account/logic/account_copy.dart`
- Test: `test/features/account/services/account_service_test.dart`
- Test: `test/features/account/logic/account_copy_test.dart`

**Interfaces:**
- Produces:
  - `class AdAllowance { const AdAllowance({required int rewardCredits, required int dailyCap, required int remainingToday}); const AdAllowance.none(); factory AdAllowance.fromJson(Object? json); Map<String, Object?> toJson(); }`
  - `AccountUser.ads` (`AdAllowance`, default `AdAllowance.none()`), parsed from `/me.ads`, written by `toJson`, carried by `withBalance`.
  - `class AdSession { nonce, ssvUserId (String); rewardCredits, adsRemainingToday (int); factory fromJson }`
  - `class AdSessionStatus { status (String); credits (int); balance (int?); factory fromJson }`
  - `class CreditEntry { id, type (String); amount, balanceAfter (int); createdAt (DateTime); factory fromJson }`
  - `class CreditHistoryPage { items (List<CreditEntry>); nextCursor (String?); factory fromJson }`
  - `Future<AdSession> AccountService.startAdSession()`, `Future<AdSessionStatus> AccountService.adSession(String nonce)`, `Future<CreditHistoryPage> AccountService.history({String? cursor, int limit = 20})`
  - `String creditHistoryLabel(String type)`, `String creditAmountLabel(int amount)`, `String watchAdLabel(int credits)`, `String adsLeftLabel(int remaining)`, `String inviteMessage(String code)`, `const String kBackTomorrow = 'Back tomorrow'`

- [ ] **Step 0: Be on the branch** — `git checkout feat/credits-stage3`.

- [ ] **Step 1: Write the failing service tests** — append inside `main()` of `account_service_test.dart`:

```dart
  test('/me carries today\'s rewarded ads', () async {
    server.on('GET', '/me', (_) => envelope(userJson()));
    final user = await service(signedIn: true).me();
    expect(
      (user.ads.rewardCredits, user.ads.dailyCap, user.ads.remainingToday),
      (5, 10, 10),
    );
    expect(AccountUser.fromJson(user.toJson()).ads.remainingToday, 10,
        reason: 'the kept profile keeps it');
    expect(user.withBalance(3).ads.remainingToday, 10);
  });

  test('an ad session is asked for, signed in, and polled by its nonce',
      () async {
    server
      ..on(
        'POST',
        '/rewards/ads/session',
        (_) => envelope({
          'nonce': 'n1',
          'ssvUserId': 'u1',
          'rewardCredits': 5,
          'adsRemainingToday': 7,
        }),
      )
      ..on(
        'GET',
        '/rewards/ads/session/n1',
        (_) => envelope({'status': 'granted', 'credits': 5, 'balance': 99}),
      );
    final s = service(signedIn: true);
    final session = await s.startAdSession();
    expect((session.nonce, session.ssvUserId, session.rewardCredits,
        session.adsRemainingToday), ('n1', 'u1', 5, 7));
    expect(
      server.to('POST', '/rewards/ads/session').last.headers['Authorization'],
      'Bearer a1',
    );
    final status = await s.adSession('n1');
    expect((status.status, status.credits, status.balance), ('granted', 5, 99));
  });

  test('a pending session has no balance yet', () async {
    server.on('GET', '/rewards/ads/session/n1',
        (_) => envelope({'status': 'pending'}));
    final status = await service(signedIn: true).adSession('n1');
    expect((status.status, status.credits, status.balance), ('pending', 0, null));
  });

  test('history pages newest first by cursor', () async {
    server.on('GET', '/credits/history', (request) {
      final cursor = request.url.queryParameters['cursor'];
      return envelope(cursor == null
          ? {
              'items': [
                {
                  'id': 'c2',
                  'type': 'feature_charge',
                  'amount': -6,
                  'balanceAfter': 94,
                  'createdAt': '2026-10-03T12:00:00.000Z',
                },
              ],
              'nextCursor': 'c2',
            }
          : {'items': [], 'nextCursor': null});
    });
    final s = service(signedIn: true);
    final first = await s.history();
    expect(first.items.single.type, 'feature_charge');
    expect(first.items.single.amount, -6);
    expect(first.items.single.createdAt, DateTime.utc(2026, 10, 3, 12));
    expect(first.nextCursor, 'c2');
    expect(server.to('GET', '/credits/history').last.url.queryParameters,
        {'limit': '20'});

    final next = await s.history(cursor: 'c2');
    expect(next.items, isEmpty);
    expect(next.nextCursor, isNull);
    expect(server.to('GET', '/credits/history').last.url.queryParameters,
        {'limit': '20', 'cursor': 'c2'});
  });
```

- [ ] **Step 2: Write the failing wording tests** — append inside `main()` of `account_copy_test.dart`:

```dart
  test('history reads in plain words', () {
    expect(creditHistoryLabel('signup_bonus'), 'Welcome bonus');
    expect(creditHistoryLabel('referral_invitee'), 'Invite bonus');
    expect(creditHistoryLabel('referral_inviter'), 'A friend joined');
    expect(creditHistoryLabel('rewarded_ad'), 'Watched an ad');
    expect(creditHistoryLabel('feature_charge'), 'Auto captions');
    expect(creditHistoryLabel('feature_refund'), 'Refund');
    expect(creditHistoryLabel('admin_adjustment'), 'Adjustment');
    expect(creditHistoryLabel('something_new'), 'Credits');
    expect(creditAmountLabel(5), '+5');
    expect(creditAmountLabel(-6), '−6');
  });

  test('earning reads as the spec writes it', () {
    expect(watchAdLabel(5), 'Watch an ad · +5');
    expect(adsLeftLabel(7), '7 left today');
    expect(adsLeftLabel(1), '1 left today');
    expect(kBackTomorrow, 'Back tomorrow');
    final invite = inviteMessage('AB3DEF7K');
    expect(invite, contains('AB3DEF7K'));
    expect(invite,
        contains('https://play.google.com/store/apps/details?id=com.techfamz.slimshotai'));
  });
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/account/services/account_service_test.dart test/features/account/logic/account_copy_test.dart`
Expected: FAIL to compile — `ads`, `startAdSession`, `adSession`, `history`, the labels are not defined.

- [ ] **Step 4: The models** — in `account_models.dart`:

Add to `AccountUser`'s constructor `this.ads = const AdAllowance.none(),`, the field

```dart
  /// Today's rewarded ads (`/me.ads`).
  final AdAllowance ads;
```

in `fromJson` `ads: AdAllowance.fromJson(json['ads']),`, in `toJson` `'ads': ads.toJson(),`, and in `withBalance` `ads: ads,`. At the end of the file:

```dart
/// Today's rewarded ads, as `/me.ads` describes them. Resets at 00:00 UTC.
class AdAllowance {
  const AdAllowance({
    required this.rewardCredits,
    required this.dailyCap,
    required this.remainingToday,
  });

  const AdAllowance.none()
      : rewardCredits = 0,
        dailyCap = 0,
        remainingToday = 0;

  factory AdAllowance.fromJson(Object? json) {
    if (json is! Map) return const AdAllowance.none();
    int read(String key) => (json[key] as num?)?.toInt() ?? 0;
    return AdAllowance(
      rewardCredits: read('rewardCredits'),
      dailyCap: read('dailyCap'),
      remainingToday: read('remainingToday'),
    );
  }

  final int rewardCredits;
  final int dailyCap;
  final int remainingToday;

  Map<String, Object?> toJson() => {
        'rewardCredits': rewardCredits,
        'dailyCap': dailyCap,
        'remainingToday': remainingToday,
      };
}

/// One rewarded ad's session: what its server-side verification carries.
class AdSession {
  const AdSession({
    required this.nonce,
    required this.ssvUserId,
    required this.rewardCredits,
    required this.adsRemainingToday,
  });

  factory AdSession.fromJson(Map<String, dynamic> json) {
    final nonce = json['nonce'];
    final ssvUserId = json['ssvUserId'];
    if (nonce is! String || ssvUserId is! String) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No ad session.',
      );
    }
    return AdSession(
      nonce: nonce,
      ssvUserId: ssvUserId,
      rewardCredits: (json['rewardCredits'] as num?)?.toInt() ?? 0,
      adsRemainingToday: (json['adsRemainingToday'] as num?)?.toInt() ?? 0,
    );
  }

  final String nonce;
  final String ssvUserId;
  final int rewardCredits;
  final int adsRemainingToday;
}

/// How an ad's reward went: `pending`, `granted`, `capped` or `rejected`.
class AdSessionStatus {
  const AdSessionStatus({
    required this.status,
    this.credits = 0,
    this.balance,
  });

  factory AdSessionStatus.fromJson(Map<String, dynamic> json) =>
      AdSessionStatus(
        status: json['status'] as String? ?? 'pending',
        credits: (json['credits'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toInt(),
      );

  final String status;
  final int credits;

  /// The balance after a grant; absent until then.
  final int? balance;
}

/// One line of the credit history.
class CreditEntry {
  const CreditEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
  });

  factory CreditEntry.fromJson(Map<String, dynamic> json) => CreditEntry(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        balanceAfter: (json['balanceAfter'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  final String id;
  final String type;
  final int amount;
  final int balanceAfter;
  final DateTime createdAt;
}

/// A page of history, newest first; [nextCursor] null at the end.
class CreditHistoryPage {
  const CreditHistoryPage({required this.items, this.nextCursor});

  factory CreditHistoryPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    return CreditHistoryPage(
      items: items is List
          ? [
              for (final item in items)
                if (item is Map)
                  CreditEntry.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<CreditEntry> items;
  final String? nextCursor;
}
```

- [ ] **Step 5: The requests** — in `AccountService`, after `quote`:

```dart
  /// A new session for one rewarded ad: its nonce goes into the ad's
  /// server-side verification, and is what the reward is asked about.
  Future<AdSession> startAdSession() async => AdSession.fromJson(
        await _api.send(
          () => _api.jsonRequest(
            'POST',
            '/rewards/ads/session',
            const <String, Object?>{},
          ),
        ),
      );

  /// How the reward for [nonce] went.
  Future<AdSessionStatus> adSession(String nonce) async =>
      AdSessionStatus.fromJson(
        await _api.send(
          () => http.Request('GET', _api.uri('/rewards/ads/session/$nonce')),
        ),
      );

  /// A page of the credit history, newest first.
  Future<CreditHistoryPage> history({String? cursor, int limit = 20}) async =>
      CreditHistoryPage.fromJson(
        await _api.send(
          () => http.Request(
            'GET',
            _api.uri('/credits/history').replace(queryParameters: {
              'limit': '$limit',
              if (cursor != null) 'cursor': cursor,
            }),
          ),
        ),
      );
```

- [ ] **Step 6: The wording** — at the end of `account_copy.dart`:

```dart
/// A history line's kind, in plain words.
String creditHistoryLabel(String type) => switch (type) {
      'signup_bonus' => 'Welcome bonus',
      'referral_invitee' => 'Invite bonus',
      'referral_inviter' => 'A friend joined',
      'rewarded_ad' => 'Watched an ad',
      'feature_charge' => 'Auto captions',
      'feature_refund' => 'Refund',
      'admin_adjustment' => 'Adjustment',
      'account_deleted' => 'Account deleted',
      'purchase' => 'Purchase',
      _ => 'Credits',
    };

/// "+5", "−6" (a true minus sign).
String creditAmountLabel(int amount) =>
    amount >= 0 ? '+$amount' : '−${amount.abs()}';

String watchAdLabel(int credits) => 'Watch an ad · +$credits';

String adsLeftLabel(int remaining) => '$remaining left today';

const String kBackTomorrow = 'Back tomorrow';

/// What Invite a friend shares: the code and where to get the app.
String inviteMessage(String code) =>
    'Get free credits on SlimShot AI with my invite code $code\n'
    'https://play.google.com/store/apps/details?id=com.techfamz.slimshotai';
```

- [ ] **Step 7: Run them to see them pass**

Run: `flutter test test/features/account/services/account_service_test.dart test/features/account/logic/account_copy_test.dart`
Expected: PASS.

- [ ] **Step 8: Full suite and analyzer** — `flutter test`, `flutter analyze --no-pub`. Expected: all pass; `48 issues found`.

- [ ] **Step 9: Commit**

```bash
git add lib/features/account test/features/account
git commit -m "feat(credits): the ad session, reward poll and history endpoints

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: One rewarded ad, end to end

**Files:**
- Create: `lib/features/account/services/credit_ads.dart`
- Modify: `lib/core/services/ad_service.dart`
- Modify: `lib/main.dart`
- Modify: `lib/features/account/providers/account_providers.dart`
- Modify: `test/support/account_harness.dart`
- Test: `test/features/account/services/credit_ads_test.dart` (create)

**Interfaces:**
- Consumes: `AccountService.startAdSession/adSession`, `AdSession`, `AdSessionStatus` (Task 1).
- Produces:
  - `enum AdPlayback { notShown, closed, earned }`
  - `abstract class RewardedAdPlayer { Future<AdPlayback> play({required String userId, required String customData}); }`
  - `class PluginRewardedAdPlayer implements RewardedAdPlayer { PluginRewardedAdPlayer(String adUnitId); }`
  - `enum AdRewardOutcome { granted, capped, rejected, notEarned, pending, noAd, dailyCap }`
  - `class AdReward { const AdReward(AdRewardOutcome outcome, {int credits = 0, int? balance}); }`
  - `class CreditAdService { CreditAdService({required AccountService account, required RewardedAdPlayer player, Future<void> Function(Duration)? delay, DateTime Function()? clock}); Future<AdReward> watch(); static const pollEvery, pollFor, pollAfterEarlyClose; }`
  - `String adRewardMessage(AdReward reward)` (in `credit_ads.dart`)
  - `static const bool AdService.creditAdsEnabled = true`; `static String get AdService.rewardedAdUnitId`
  - providers `creditAdsEnabledProvider` (bool), `rewardedAdPlayerProvider`, `creditAdServiceProvider`, `shareTextProvider` (`Future<void> Function(String)`)
  - harness: `class FakeRewardedAdPlayer implements RewardedAdPlayer { AdPlayback playback = AdPlayback.earned; final List<(String, String)> plays = []; }`; `accountOverrides(server, {session, google, FakeRewardedAdPlayer? ads, List<String>? shared})`

- [ ] **Step 1: The fake player** — in `test/support/account_harness.dart` add the import `package:slimshotai/features/account/services/credit_ads.dart` and:

```dart
/// The rewarded ad, scripted: [playback] is how the next one ends.
class FakeRewardedAdPlayer implements RewardedAdPlayer {
  AdPlayback playback = AdPlayback.earned;

  /// (userId, customData) of every ad played.
  final List<(String, String)> plays = [];

  @override
  Future<AdPlayback> play({
    required String userId,
    required String customData,
  }) async {
    plays.add((userId, customData));
    return playback;
  }
}
```

- [ ] **Step 2: Write the failing tests** — create `test/features/account/services/credit_ads_test.dart`:

```dart
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
}
```

(A `MockClient` handler throwing `http.ClientException` surfaces from `SlimshotApi` as `SlimshotApiException(NETWORK)` — that is what "a dropped poll" exercises; a plain `Exception` would not be mapped.)

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/account/services/credit_ads_test.dart`
Expected: FAIL to compile — `credit_ads.dart` does not exist.

- [ ] **Step 4: Implement** — create `lib/features/account/services/credit_ads.dart`:

```dart
import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/services/slimshot_api.dart';
import '../logic/account_copy.dart';
import 'account_service.dart';

/// How a rewarded ad ended.
enum AdPlayback {
  /// No ad could be loaded or shown.
  notShown,

  /// Shown, and closed before the reward was earned.
  closed,

  /// Shown, and watched to the reward.
  earned,
}

/// One rewarded ad: loaded, given its server-side verification, shown.
/// Behind an interface so the flow is tested without a device.
abstract class RewardedAdPlayer {
  /// Completes when the ad closes. [userId] and [customData] go into the
  /// ad's server-side verification **before** it shows.
  Future<AdPlayback> play({required String userId, required String customData});
}

/// The `google_mobile_ads` rewarded ad.
class PluginRewardedAdPlayer implements RewardedAdPlayer {
  PluginRewardedAdPlayer(this.adUnitId);

  final String adUnitId;

  static const Duration loadTimeout = Duration(seconds: 15);

  @override
  Future<AdPlayback> play({
    required String userId,
    required String customData,
  }) async {
    final loaded = Completer<RewardedAd?>();
    final timer = Timer(loadTimeout, () {
      if (!loaded.isCompleted) loaded.complete(null);
    });
    unawaited(RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          // Landed after the timeout: nobody is waiting to show it.
          if (loaded.isCompleted) {
            ad.dispose();
            return;
          }
          loaded.complete(ad);
        },
        onAdFailedToLoad: (_) {
          if (!loaded.isCompleted) loaded.complete(null);
        },
      ),
    ));
    final ad = await loaded.future;
    timer.cancel();
    if (ad == null) return AdPlayback.notShown;

    await ad.setServerSideOptions(
      ServerSideVerificationOptions(userId: userId, customData: customData),
    );
    var earned = false;
    final closed = Completer<AdPlayback>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) {
          closed.complete(earned ? AdPlayback.earned : AdPlayback.closed);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete(AdPlayback.notShown);
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return closed.future;
  }
}

enum AdRewardOutcome { granted, capped, rejected, notEarned, pending, noAd, dailyCap }

/// How one ad went, and the balance the server answered with a grant.
class AdReward {
  const AdReward(this.outcome, {this.credits = 0, this.balance});

  final AdRewardOutcome outcome;
  final int credits;
  final int? balance;
}

/// One rewarded ad, end to end. **The app never adds credits itself**: AdMob
/// tells the server (SSV), and this only asks the server how it went.
class CreditAdService {
  CreditAdService({
    required AccountService account,
    required RewardedAdPlayer player,
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  })  : _account = account,
        _player = player,
        _delay = delay ?? Future<void>.delayed,
        _clock = clock ?? DateTime.now;

  final AccountService _account;
  final RewardedAdPlayer _player;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;

  static const Duration pollEvery = Duration(seconds: 1);

  /// How long a watched ad's grant is waited for (contract §13).
  static const Duration pollFor = Duration(seconds: 30);

  /// An ad closed before its reward is asked about briefly — AdMob may still
  /// call the server — rather than for the full half minute.
  static const Duration pollAfterEarlyClose = Duration(seconds: 5);

  Future<AdReward> watch() async {
    final AdSession session;
    try {
      // A new session — a new nonce — for every ad.
      session = await _account.startAdSession();
    } on SlimshotApiException catch (e) {
      if (e.code == 'AD_DAILY_CAP_REACHED') {
        return const AdReward(AdRewardOutcome.dailyCap);
      }
      rethrow;
    }
    final playback = await _player.play(
      userId: session.ssvUserId,
      customData: session.nonce,
    );
    if (playback == AdPlayback.notShown) {
      return const AdReward(AdRewardOutcome.noAd);
    }
    final limit = playback == AdPlayback.earned ? pollFor : pollAfterEarlyClose;
    final began = _clock();
    while (_clock().difference(began) < limit) {
      await _delay(pollEvery);
      final AdSessionStatus status;
      try {
        status = await _account.adSession(session.nonce);
      } on SlimshotApiException catch (e) {
        if (e.code == SlimshotApiException.network) continue;
        rethrow;
      }
      switch (status.status) {
        case 'granted':
          return AdReward(
            AdRewardOutcome.granted,
            credits: status.credits,
            balance: status.balance,
          );
        case 'capped':
          return const AdReward(AdRewardOutcome.capped);
        case 'rejected':
          return const AdReward(AdRewardOutcome.rejected);
      }
    }
    return AdReward(playback == AdPlayback.earned
        ? AdRewardOutcome.pending
        : AdRewardOutcome.notEarned);
  }
}

/// The one line a reward ends with.
String adRewardMessage(AdReward reward) => switch (reward.outcome) {
      AdRewardOutcome.granted => '+${reward.credits} credits',
      AdRewardOutcome.capped => "That's today's last reward",
      AdRewardOutcome.rejected => 'No reward this time',
      AdRewardOutcome.notEarned => 'Watch to the end to earn credits',
      AdRewardOutcome.pending => 'Your reward is on its way',
      AdRewardOutcome.noAd => 'No ad right now. Try again soon.',
      AdRewardOutcome.dailyCap => kBackTomorrow,
    };
```

- [ ] **Step 5: The switch** — in `ad_service.dart`, below `enabled`:

```dart
  /// Rewarded ads that **earn credits**: their own switch, on (spec §3 E).
  /// `enabled` stays off, so interstitials and the Pro-unlock ads stay off;
  /// the SDK starts when either is on (`main.dart`). The reward itself is
  /// verified on the server (SSV), never granted by the app.
  static const bool creditAdsEnabled = true;
```

and rename the private getter `_rewardedAdUnitId` to the public `rewardedAdUnitId` (update its uses in this file). In `main.dart` replace the ad block with:

```dart
  // `AdService.enabled` (interstitials, Pro-unlock ads) is off; credit ads
  // have their own switch. The SDK starts when either is on.
  if (AdService.enabled || AdService.creditAdsEnabled) {
    MobileAds.instance.initialize();
  }
  if (AdService.enabled) {
    AdService.loadInterstitialAd(); // Start background preload immediately
    AdService.loadRewardedAd(); // Start background preload for Rewarded Ads
  }
```

- [ ] **Step 6: The providers** — in `account_providers.dart` add imports for `ad_service.dart`, `share_plus`, and `../services/credit_ads.dart`, and:

```dart
/// Whether Watch an ad is offered (`AdService.creditAdsEnabled`).
final creditAdsEnabledProvider =
    Provider<bool>((ref) => AdService.creditAdsEnabled);

final rewardedAdPlayerProvider = Provider<RewardedAdPlayer>(
  (ref) => PluginRewardedAdPlayer(AdService.rewardedAdUnitId),
);

final creditAdServiceProvider = Provider<CreditAdService>(
  (ref) => CreditAdService(
    account: ref.watch(accountServiceProvider),
    player: ref.watch(rewardedAdPlayerProvider),
  ),
);

/// The system share sheet, for Invite a friend.
final shareTextProvider = Provider<Future<void> Function(String text)>(
  (ref) => (text) async {
    await Share.share(text);
  },
);
```

and in the harness extend `accountOverrides`:

```dart
List<Override> accountOverrides(
  FakeServer server, {
  AccountSession? session,
  GoogleIdTokens? google,
  FakeRewardedAdPlayer? ads,
  List<String>? shared,
}) {
  final shared0 = session ?? AccountSession(vault: MemoryTokenVault());
  final player = ads ?? FakeRewardedAdPlayer();
  var now = DateTime(2026, 10, 6);
  return [
    accountFeatureProvider.overrideWithValue(true),
    accountSessionProvider.overrideWithValue(shared0),
    accountApiProvider.overrideWithValue(fakeApi(server, session: shared0)),
    googleIdTokensProvider.overrideWithValue(google ?? FakeGoogleIdTokens()),
    rewardedAdPlayerProvider.overrideWithValue(player),
    // The poll on a clock the test owns: no real second goes by.
    creditAdServiceProvider.overrideWith(
      (ref) => CreditAdService(
        account: ref.watch(accountServiceProvider),
        player: player,
        delay: (d) async => now = now.add(d),
        clock: () => now,
      ),
    ),
    shareTextProvider.overrideWithValue((text) async => shared?.add(text)),
  ];
}
```

(The existing local named `shared` is renamed `shared0` because the new parameter takes the name; every use inside the function changes with it.)

- [ ] **Step 7: Run them to see them pass**

Run: `flutter test test/features/account`
Expected: PASS.

- [ ] **Step 8: Full suite and analyzer** — `flutter test`, `flutter analyze --no-pub`. Expected: all pass; `48 issues found`. Then `flutter build apk --debug` (a plugin's real code path is now reachable from `main`). Expected: `Built build\app\outputs\flutter-apk\app-debug.apk`.

- [ ] **Step 9: Commit**

```bash
git add lib/features/account lib/core/services/ad_service.dart lib/main.dart test/support/account_harness.dart test/features/account
git commit -m "feat(credits): one rewarded ad end to end, verified on the server

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The earn block — Watch an ad, Invite a friend

**Files:**
- Create: `lib/features/account/widgets/earn_credits_block.dart`
- Test: `test/features/account/widgets/earn_credits_block_test.dart` (create)

**Interfaces:**
- Consumes: Task 1 wording and `AccountUser.ads`/`referralCode`; Task 2 providers and `adRewardMessage`; `AccountNotifier.applyBalance/refresh` (stage 2/1); `ToastUtils.show`.
- Produces: `class EarnCreditsBlock extends ConsumerStatefulWidget { const EarnCreditsBlock({Key? key, void Function(int balance)? onEarned}); }` — keys `earn_watch_ad`, `earn_invite`.

- [ ] **Step 1: Write the failing tests** — create `test/features/account/widgets/earn_credits_block_test.dart`:

```dart
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

  testWidgets('a watched ad shows the server\'s balance and says so',
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

  testWidgets('Invite a friend shares the user\'s own code', (tester) async {
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
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/account/widgets/earn_credits_block_test.dart`
Expected: FAIL to compile — `earn_credits_block.dart` does not exist.

- [ ] **Step 3: Implement** — create `lib/features/account/widgets/earn_credits_block.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/slimshot_api.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/toast_utils.dart';
import '../logic/account_copy.dart';
import '../providers/account_providers.dart';
import '../services/credit_ads.dart';

/// The ways to earn credits: Watch an ad, Invite a friend. One block for the
/// caption shortfall and the Credits screen, so the two cannot drift.
///
/// [onEarned] hears the balance a granted ad left — the server's number;
/// the app never adds credits itself.
class EarnCreditsBlock extends ConsumerStatefulWidget {
  const EarnCreditsBlock({super.key, this.onEarned});

  final void Function(int balance)? onEarned;

  @override
  ConsumerState<EarnCreditsBlock> createState() => _EarnCreditsBlockState();
}

class _EarnCreditsBlockState extends ConsumerState<EarnCreditsBlock> {
  bool _watching = false;

  Future<void> _watch() async {
    setState(() => _watching = true);
    final notifier = ref.read(accountProvider.notifier);
    try {
      final reward = await ref.read(creditAdServiceProvider).watch();
      final balance = reward.balance;
      if (reward.outcome == AdRewardOutcome.granted && balance != null) {
        await notifier.applyBalance(balance);
        widget.onEarned?.call(balance);
      }
      if (mounted) {
        ToastUtils.show(
          context,
          adRewardMessage(reward),
          isError: reward.outcome != AdRewardOutcome.granted &&
              reward.outcome != AdRewardOutcome.pending,
        );
      }
    } on SlimshotApiException catch (e) {
      if (mounted) ToastUtils.show(context, accountErrorMessage(e), isError: true);
    } finally {
      // Today's count, and a late grant, come from the server.
      unawaited(notifier.refresh());
      if (mounted) setState(() => _watching = false);
    }
  }

  Future<void> _invite(String code) =>
      ref.read(shareTextProvider)(inviteMessage(code));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(accountProvider).user;
    if (user == null) return const SizedBox.shrink();
    final adsOn = ref.watch(creditAdsEnabledProvider);
    final allowance = user.ads;
    final atCap = allowance.remainingToday <= 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (adsOn) ...[
          _EarnButton(
            key: const Key('earn_watch_ad'),
            label: atCap ? kBackTomorrow : watchAdLabel(allowance.rewardCredits),
            busy: _watching,
            onPressed: atCap || _watching ? null : _watch,
          ),
          if (!atCap)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                adsLeftLabel(allowance.remainingToday),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 10),
        ],
        _EarnButton(
          key: const Key('earn_invite'),
          label: 'Invite a friend',
          onPressed: () => unawaited(_invite(user.referralCode)),
        ),
      ],
    );
  }
}

class _EarnButton extends StatelessWidget {
  const _EarnButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            disabledForegroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textPrimary,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      );
}
```

- [ ] **Step 4: Run them to see them pass**

Run: `flutter test test/features/account/widgets/earn_credits_block_test.dart`
Expected: PASS. (If a toast's hold timer is reported pending at a test's end, add `await tester.pump(const Duration(seconds: 5));` before the test returns — the toast cancels its own timer on dispose, so this should not be needed.)

- [ ] **Step 5: Full suite and analyzer** — `flutter test`, `flutter analyze --no-pub`. Expected: all pass; `48 issues found`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/account/widgets/earn_credits_block.dart test/features/account/widgets/earn_credits_block_test.dart
git commit -m "feat(credits): the earn block — watch an ad, invite a friend

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Earning from the caption shortfall

**Files:**
- Modify: `lib/features/video_editor/widgets/panels/caption_progress_sheet.dart`
- Modify: `lib/screens/video_editor_screen.dart`
- Test: `test/features/video_editor/widgets/auto_caption_sheets_test.dart`

**Interfaces:**
- Consumes: `EarnCreditsBlock` (Task 3); the sheet's `_quote`/`_decision` (stage 2).
- Produces: `CaptionProgressSheet({…, Widget Function(CreditQuote quote, void Function(int balance) onEarned)? earnCredits})`.

- [ ] **Step 1: Write the failing tests** — inside the `CaptionProgressSheet` group:

```dart
    Widget earnButton(CreditQuote quote, void Function(int) onEarned,
            int balance) =>
        TextButton(
          key: const Key('fake_earn'),
          onPressed: () => onEarned(balance),
          child: const Text('earn'),
        );

    testWidgets('earning enough carries the run on', (tester) async {
      var uploads = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () async => sound,
            quote: const CreditQuote(credits: 30, balance: 0, enough: false),
            onUpload: () => uploads++,
          ),
          request: const CaptionRequest(),
          earnCredits: (q, onEarned) => earnButton(q, onEarned, 35),
        ),
      );
      await tester.pump();
      await tapKey(tester, 'fake_earn');
      expect(uploads, 1);
      expect((popped.single as List<CaptionDraft>).single.text, 'Hello');
    });

    testWidgets('earning too little updates the line and waits',
        (tester) async {
      var uploads = 0;
      await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () async => sound,
            quote: const CreditQuote(credits: 30, balance: 0, enough: false),
            onUpload: () => uploads++,
          ),
          request: const CaptionRequest(),
          earnCredits: (q, onEarned) => earnButton(q, onEarned, 5),
        ),
      );
      await tester.pump();
      await tapKey(tester, 'fake_earn');
      expect(find.text('Needs 30 credits · You have 5'), findsOneWidget);
      expect(uploads, 0);
    });
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/video_editor/widgets/auto_caption_sheets_test.dart`
Expected: FAIL to compile — `earnCredits` is not a parameter.

- [ ] **Step 3: Implement** — in `CaptionProgressSheet` add the field

```dart
  /// The ways to earn the difference, under the shortfall line. It reports
  /// the server's new balance through `onEarned`.
  final Widget Function(
    CreditQuote quote,
    void Function(int balance) onEarned,
  )? earnCredits;
```

(constructor: `this.earnCredits,`). In the state add:

```dart
  /// A balance the user just earned: enough carries the run on, too little
  /// updates the line.
  void _earned(int balance) {
    final quote = _quote;
    final decision = _decision;
    if (quote == null || decision == null || decision.isCompleted) return;
    if (balance >= quote.credits) {
      setState(() {
        _quote = null;
        _decision = null;
      });
      decision.complete(true);
    } else {
      setState(() => _quote = CreditQuote(
            credits: quote.credits,
            balance: balance,
            enough: false,
          ));
    }
  }
```

and in the shortfall block, replace the `// Stage 3 puts Watch an ad here.` comment with:

```dart
                if (widget.earnCredits != null) ...[
                  widget.earnCredits!(quote, _earned),
                  const SizedBox(height: 12),
                ],
```

In `video_editor_screen.dart` pass `earnCredits: (quote, onEarned) => EarnCreditsBlock(onEarned: onEarned),` to `CaptionProgressSheet(…)` and import `../features/account/widgets/earn_credits_block.dart`.

- [ ] **Step 4: Run them to see them pass**

Run: `flutter test test/features/video_editor/widgets/auto_caption_sheets_test.dart`
Expected: PASS.

- [ ] **Step 5: Full suite and analyzer** — expected all pass, `48 issues found`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/video_editor/widgets/panels/caption_progress_sheet.dart lib/screens/video_editor_screen.dart test/features/video_editor/widgets/auto_caption_sheets_test.dart
git commit -m "feat(captions): earn the difference from the shortfall, and carry on

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The Credits screen, and the ways to it

**Files:**
- Create: `lib/features/account/screens/credits_screen.dart`
- Modify: `lib/features/account/widgets/credits_pill.dart`
- Modify: `lib/features/account/widgets/settings_account_section.dart`
- Test: `test/features/account/screens/credits_screen_test.dart` (create)
- Test: `test/features/account/widgets/credits_pill_test.dart`, `settings_account_section_test.dart`

**Interfaces:**
- Consumes: `AccountService.history`, `creditHistoryLabel`, `creditAmountLabel` (Task 1); `EarnCreditsBlock` (Task 3); `ColourFieldBackdrop`, `FrostedGlass`.
- Produces: `class CreditsScreen extends ConsumerStatefulWidget`; `void openCreditsScreen(BuildContext context)` (root navigator); keys `credits_balance`, `credits_more`.

- [ ] **Step 1: Write the failing tests** — create `test/features/account/screens/credits_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/screens/credits_screen.dart';

import '../../../support/account_fakes.dart';
import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;

  Map<String, Object?> entry(String id, String type, int amount) => {
        'id': id,
        'type': type,
        'amount': amount,
        'balanceAfter': 94,
        'createdAt': '2026-10-03T12:00:00.000Z',
      };

  setUp(() {
    server = FakeServer()
      ..on('GET', '/me', (_) => envelope(userJson(balance: 94)))
      ..on('GET', '/credits/history', (request) {
        final cursor = request.url.queryParameters['cursor'];
        return envelope(cursor == null
            ? {
                'items': [
                  entry('c2', 'feature_charge', -6),
                  entry('c1', 'signup_bonus', 100),
                ],
                'nextCursor': 'c1',
              }
            : {
                'items': [entry('c0', 'rewarded_ad', 5)],
                'nextCursor': null,
              });
      });
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: accountOverrides(
        server,
        session: signedInSession(profile: userJson(balance: 94)),
      ),
      child: const MaterialApp(home: CreditsScreen()),
    ));
    await settle(tester);
  }

  testWidgets('the balance, the ways to earn, and the history',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text('Credits'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('credits_balance'))).data,
      '94',
    );
    expect(find.text('Invite a friend'), findsOneWidget);
    expect(find.text('Auto captions'), findsOneWidget);
    expect(find.text('−6'), findsOneWidget);
    expect(find.text('Welcome bonus'), findsOneWidget);
    expect(find.text('+100'), findsOneWidget);
  });

  testWidgets('More reads the next page, and goes at the end',
      (tester) async {
    await pumpScreen(tester);
    await tester.ensureVisible(find.byKey(const Key('credits_more')));
    await tester.tap(find.byKey(const Key('credits_more')));
    await settle(tester);
    expect(find.text('Watched an ad'), findsOneWidget);
    expect(find.byKey(const Key('credits_more')), findsNothing);
    expect(server.to('GET', '/credits/history').last.url.queryParameters['cursor'],
        'c1');
  });
}
```

Append inside `main()` of `credits_pill_test.dart`:

```dart
  testWidgets('signed in, the balance opens Credits', (tester) async {
    server
      ..on('GET', '/me', (_) => envelope(userJson(balance: 94)))
      ..on('GET', '/credits/history',
          (_) => envelope({'items': [], 'nextCursor': null}));
    await pumpPill(
      tester,
      accountOverrides(server,
          session: signedInSession(profile: userJson(balance: 94))),
    );
    await tester.tap(find.byKey(const Key('credits_pill_balance')));
    await settle(tester);
    expect(find.byKey(const Key('credits_balance')), findsOneWidget);
  });
```

and inside `main()` of `settings_account_section_test.dart`:

```dart
  testWidgets('signed in, a Credits row opens Credits', (tester) async {
    server.on('GET', '/credits/history',
        (_) => envelope({'items': [], 'nextCursor': null}));
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Credits'));
    await settle(tester);
    expect(find.byKey(const Key('credits_balance')), findsOneWidget);
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/account`
Expected: FAIL — `credits_screen.dart` does not exist; the pill and the section have no way to it.

- [ ] **Step 3: Implement the screen** — create `lib/features/account/screens/credits_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/services/slimshot_api.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/widgets/colour_field_backdrop.dart';
import '../../../core/widgets/frosted_glass.dart';
import '../logic/account_copy.dart';
import '../models/account_models.dart';
import '../providers/account_providers.dart';
import '../widgets/earn_credits_block.dart';

/// Opens Credits on the root navigator — above the app shell's floating
/// nav, from a tab.
void openCreditsScreen(BuildContext context) {
  unawaited(Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(builder: (_) => const CreditsScreen()),
  ));
}

/// The balance, the ways to earn, and the history.
class CreditsScreen extends ConsumerStatefulWidget {
  const CreditsScreen({super.key});

  @override
  ConsumerState<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends ConsumerState<CreditsScreen> {
  final List<CreditEntry> _entries = [];
  String? _next;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(accountServiceProvider)
          .history(cursor: _loaded ? _next : null);
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.items);
        _next = page.nextCursor;
        _loaded = true;
      });
    } on SlimshotApiException catch (e) {
      if (mounted) setState(() => _error = accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(accountProvider).user?.creditBalance ?? 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: ColourFieldBackdrop()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        LucideIcons.arrowLeft,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Credits',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.coins,
                        color: AppColors.credit, size: 30),
                    const SizedBox(width: 10),
                    Text(
                      '$balance',
                      key: const Key('credits_balance'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FrostedGlass(
                  borderRadius: BorderRadius.circular(24),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: EarnCreditsBlock(),
                  ),
                ),
                const SizedBox(height: 28),
                for (final entry in _entries) _HistoryRow(entry),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                if (_next != null || _error != null)
                  TextButton(
                    key: const Key('credits_more'),
                    onPressed: _loading ? null : _load,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: Text(_error != null ? 'Try again' : 'More'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.entry);

  final CreditEntry entry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    creditHistoryLabel(entry.type),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeago.format(entry.createdAt),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              creditAmountLabel(entry.amount),
              style: TextStyle(
                color: entry.amount >= 0
                    ? AppColors.success
                    : AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}
```

(`_load` reads the first page while `_loaded` is false, then the `_next` cursor; a failed page leaves `_next` and offers Try again on the same button.)

- [ ] **Step 4: The ways to it** — in `credits_pill.dart`, give the balance pill `onTap: () => openCreditsScreen(context),` and import `../screens/credits_screen.dart`. In `settings_account_section.dart`, after the Email row's `SettingsDivider`, add:

```dart
            SettingsItem(
              icon: LucideIcons.coins,
              title: 'Credits',
              subtitle: '${user.creditBalance}',
              onTap: () => openCreditsScreen(context),
            ),
            const SettingsDivider(),
```

and import `../screens/credits_screen.dart`.

- [ ] **Step 5: Run them to see them pass**

Run: `flutter test test/features/account`
Expected: PASS.

- [ ] **Step 6: Full suite and analyzer** — expected all pass, `48 issues found`.

- [ ] **Step 7: Commit**

```bash
git add lib/features/account test/features/account
git commit -m "feat(credits): the Credits screen — balance, earning, history

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Record the stage

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the section** — directly after "Accounts and credits — stage 2: the silent price check":

```markdown
### Accounts and credits — stage 3: earning

**Awaiting device verification.** Plan: `docs/superpowers/plans/2026-10-06-credits-stage3-earning.md`.
A signed-in user earns by **watching a rewarded ad** or **inviting a friend**, from the caption
shortfall and from the **Credits screen** (the pill and Settings' Credits row open it, on the root
navigator; balance, the ways to earn, the history paged by cursor).

**The app never grants credits.** `CreditAdService.watch` asks for a session (a new nonce per ad),
plays the ad through `RewardedAdPlayer` with `ServerSideVerificationOptions(userId: ssvUserId,
customData: nonce)` set **before** `show`, then polls the session once a second: up to 30s after a
watched ad, 5s after one closed early (AdMob may still call the server; past that "Watch to the end
to earn credits" — a 30s wait ending "on its way" for an ad the user skipped reads as broken). The
balance shown is the server's (`granted.balance` → `applyBalance`), and `/me` is read again after
every ad for today's count. `409 AD_DAILY_CAP_REACHED` plays nothing and the button reads "Back
tomorrow". A dropped poll is ridden out. `PluginRewardedAdPlayer` is the only plugin code, untested
by design (it needs a device); a load landing after its 15s timeout is disposed, never shown late.

**Credit ads have their own switch** (`AdService.creditAdsEnabled`, on); `AdService.enabled` —
interstitials and the Pro-unlock ads — stays off. The SDK starts when either is on. **AdMob
setup is outside the code**: server-side verification on the rewarded unit (`…/3806842044`) with
the callback `https://<server>/api/app/v1/rewards/admob/ssv`, the unit in the server's
`ADMOB_AD_UNIT_IDS`, and the test phone added as a test device — Google's sample units never call
the server, and clicking your own live ads breaks AdMob policy.

**`EarnCreditsBlock` is the one earning UI** (caption sheet and Credits screen). In the editor the
sheet takes it through `CaptionProgressSheet.earnCredits`, so the panel stays free of account
code; a balance that now covers the price carries the run on by itself (the shortfall's decision
completes `true` and the pipeline uploads), too little updates the line. **Invite a friend**
shares `inviteMessage(referralCode)` — the code and the Play Store link — through `Share.share`.
```

- [ ] **Step 2: Full suite and analyzer** — expected all pass, `48 issues found`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: credits stage 3 in CLAUDE.md

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Outside the code (for the user, before the device test)

1. AdMob console → the rewarded unit `ca-app-pub-7001751702275942/3806842044` → turn on server-side verification, callback `https://slimshot-server.techfamz.com/api/app/v1/rewards/admob/ssv`.
2. Server `.env`: `ADMOB_AD_UNIT_IDS=ca-app-pub-7001751702275942/3806842044`; restart.
3. AdMob → Settings → Test devices: add the phone (its ID is printed in logcat as "Use RequestConfiguration… setTestDeviceIds").

## Device checks

1. Credits screen from the pill: balance, Watch an ad · +5, N left today, history.
2. Watch an ad to the end: "+5 credits", balance up by 5 everywhere.
3. Close an ad early: after ~5s "Watch to the end to earn credits".
4. Caption run with too few credits: the shortfall shows Watch an ad; earning enough carries the run on to Listening.
5. Invite a friend: the share sheet with the code and the Play Store link.
