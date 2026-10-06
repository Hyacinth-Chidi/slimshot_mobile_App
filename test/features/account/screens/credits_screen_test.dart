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
    expect(
      server.to('GET', '/credits/history').last.url.queryParameters['cursor'],
      'c1',
    );
  });
}
