import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
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

  testWidgets('opening Credits reads the balance again', (tester) async {
    // A reward that landed while the screen was closed shows on opening.
    await tester.pumpWidget(ProviderScope(
      overrides: accountOverrides(
        server,
        session: signedInSession(profile: userJson(balance: 94)),
      ),
      child: MaterialApp(
        home: Scaffold(
          // Signed in before Credits opens, as the home screen is.
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(accountProvider);
              return TextButton(
                onPressed: () => openCreditsScreen(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ));
    await settle(tester);
    final before = server.to('GET', '/me').length;
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(server.to('GET', '/me').length, before + 1);
  });

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
    expect(
      server.to('GET', '/credits/history').last.url.queryParameters['cursor'],
      'c1',
    );
  });

  // Daily, weekly or monthly credits, on the Credits screen alone (the
  // owner's call). The server decides everything; the app shows it.
  group('credit claims', () {
    var now = DateTime.utc(2026, 10, 30, 9);
    final claimButton = find.byKey(const Key('credits_claim'));

    String labelOf(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(of: claimButton, matching: find.byType(Text)),
        )
        .data!;

    Future<void> pumpWithClaims(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...accountOverrides(
            server,
            session: signedInSession(profile: userJson(balance: 94)),
          ),
          claimClockProvider.overrideWithValue(() => now),
        ],
        child: const MaterialApp(home: CreditsScreen()),
      ));
      await settle(tester);
    }

    void status({bool enabled = true, int interval = 1, String? next}) {
      server.on('GET', '/rewards/daily', (_) => envelope({
            'enabled': enabled,
            'credits': 5,
            'intervalDays': interval,
            'nextClaimAt': next,
          }));
    }

    setUp(() => now = DateTime.utc(2026, 10, 30, 9));

    testWidgets('claimable: one tap adds them, then counts down',
        (tester) async {
      status();
      server.on('POST', '/rewards/daily/claim', (_) {
        // The history now holds the claim.
        server.on('GET', '/credits/history', (_) => envelope({
              'items': [entry('c3', 'daily_reward', 5)],
              'nextCursor': null,
            }));
        return envelope({
          'credits': 5,
          'balance': 99,
          'nextClaimAt': '2026-10-31T09:00:00.000Z',
        });
      });
      await pumpWithClaims(tester);
      expect(labelOf(tester), 'Claim daily credits · +5');

      await tester.tap(claimButton);
      await settle(tester);
      expect(server.to('POST', '/rewards/daily/claim'), hasLength(1));
      expect(
        tester.widget<Text>(find.byKey(const Key('credits_balance'))).data,
        '99',
      );
      expect(labelOf(tester), 'Next in 24:00:00');
      expect(find.text('+5 credits'), findsOneWidget);
      expect(find.text('Claimed credits'), findsOneWidget);

      // A second later, a second less.
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(labelOf(tester), 'Next in 23:59:59');
      await tester.pump(const Duration(seconds: 5)); // past the toast
    });

    testWidgets('claimed already: a countdown, then the claim comes back',
        (tester) async {
      status(interval: 7, next: '2026-10-30T09:00:05.000Z');
      await pumpWithClaims(tester);
      expect(labelOf(tester), 'Next in 0:00:05');
      expect(
        tester.widget<OutlinedButton>(
          find.descendant(of: claimButton, matching: find.byType(OutlinedButton)),
        ).onPressed,
        isNull,
      );

      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(labelOf(tester), 'Claim weekly credits · +5');
    });

    testWidgets('switched off: no button', (tester) async {
      status(enabled: false);
      await pumpWithClaims(tester);
      expect(claimButton, findsNothing);
      expect(find.text('Invite a friend'), findsOneWidget);
    });

    testWidgets('unreadable: no button', (tester) async {
      // FakeServer answers 404 for a route nobody set.
      await pumpWithClaims(tester);
      expect(claimButton, findsNothing);
    });

    // A claim from another phone, or a double tap, lands here.
    testWidgets('already claimed after all: the countdown it says',
        (tester) async {
      status();
      server.on(
        'POST',
        '/rewards/daily/claim',
        (_) => failure('DAILY_REWARD_NOT_READY', 409,
            details: {'nextClaimAt': '2026-10-30T10:00:00.000Z'}),
      );
      await pumpWithClaims(tester);
      await tester.tap(claimButton);
      await settle(tester);
      expect(labelOf(tester), 'Next in 1:00:00');
    });

    testWidgets('switched off since the screen opened: the button goes',
        (tester) async {
      status();
      server.on(
        'POST',
        '/rewards/daily/claim',
        (_) => failure('DAILY_REWARD_OFF', 409),
      );
      await pumpWithClaims(tester);
      await tester.tap(claimButton);
      await settle(tester);
      expect(claimButton, findsNothing);
    });
  });
}
