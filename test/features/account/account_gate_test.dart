import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/account_gate.dart';
import 'package:slimshotai/features/account/logic/username_rules.dart';

import '../../support/account_fakes.dart';
import '../../support/account_harness.dart';
import '../../support/fake_server.dart';

const reason = 'Sign in to use Auto captions';
const claimHeading = 'Choose a username to claim your free credits';

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  Future<List<Object?>> openGate(
    WidgetTester tester, {
    bool signedIn = false,
    bool needsClaim = false,
    bool keptProfile = true,
  }) async {
    final session = signedIn
        ? signedInSession(
            profile: keptProfile ? userJson(needsClaim: needsClaim) : null,
          )
        : null;
    final results = await pumpHost(
      tester,
      accountOverrides(server, session: session),
      (context, ref) => requireAccount(context, ref, reason: reason),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return results;
  }

  testWidgets('signed in and claimed: straight through', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson()));
    final results = await openGate(tester, signedIn: true);
    expect(results, [true]);
    expect(find.text(reason), findsNothing);
  });

  testWidgets('signed out: the sign-in sheet, and closing it is a no',
      (tester) async {
    final results = await openGate(tester);
    expect(find.text(reason), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(results, [false]);
  });

  testWidgets('a new account goes from sign-in straight to the claim',
      (tester) async {
    server
      ..on(
        'POST',
        '/auth/email/start',
        (_) => envelope({'sentTo': 'ann@example.com', 'resendAfterSeconds': 60}),
      )
      ..on(
        'POST',
        '/auth/email/verify',
        (_) => envelope(signInJson(needsClaim: true)),
      )
      ..on(
        'GET',
        '/usernames/ann_1/availability',
        (_) => envelope({'username': 'ann_1', 'available': true}),
      )
      ..on(
        'POST',
        '/me/claim',
        (_) => envelope({
          'user': userJson(balance: 100),
          'bonus': {'granted': true, 'credits': 100},
          'referral': null,
        }),
      );
    final results = await openGate(tester);

    await tester.enterText(find.byKey(const Key('sign_in_email')), 'ann@example.com');
    await tester.tap(find.text('Continue'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('sign_in_code')), '123456');
    await settle(tester);

    expect(server.lastBody('POST', '/auth/email/verify')['code'], '123456');
    expect(find.text(claimHeading), findsOneWidget);
    await tester.enterText(find.byKey(const Key('username_field')), 'ann_1');
    await tester.pump(kUsernameCheckDelay);
    await settle(tester);
    await tester.tap(find.text('Claim'));
    await settle(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);

    expect(results, [true]);
  });

  testWidgets('signed in but not claimed: the claim sheet only', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson(needsClaim: true)));
    final results = await openGate(tester, signedIn: true, needsClaim: true);
    expect(find.text(claimHeading), findsOneWidget);
    expect(find.text(reason), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(results, [false]);
  });

  testWidgets(
      'a kept session whose profile has not loaded is not asked to sign in '
      'again', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson()));
    final results = await openGate(tester, signedIn: true, keptProfile: false);
    expect(results, [true]);
    expect(find.text(reason), findsNothing);
  });
}
