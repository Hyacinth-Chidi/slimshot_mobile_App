import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/account/widgets/credits_pill.dart';

import '../../../support/account_fakes.dart';
import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  Future<void> pumpPill(WidgetTester tester, List<Override> overrides) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: CreditsPill())),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('a build without a server shows nothing', (tester) async {
    await pumpPill(tester, [accountFeatureProvider.overrideWithValue(false)]);
    expect(find.byKey(const Key('credits_pill_free')), findsNothing);
    expect(find.byKey(const Key('credits_pill_balance')), findsNothing);
  });

  testWidgets('signed out it offers free credits, and a tap asks to sign in',
      (tester) async {
    await pumpPill(tester, accountOverrides(server));
    expect(find.text('Free credits'), findsOneWidget);
    await tester.tap(find.byKey(const Key('credits_pill_free')));
    await settle(tester);
    expect(find.text('Sign in to get free credits'), findsOneWidget);
  });

  testWidgets('signed in it shows the balance', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson(balance: 94)));
    await pumpPill(
      tester,
      accountOverrides(server, session: signedInSession(profile: userJson(balance: 94))),
    );
    expect(find.text('94'), findsOneWidget);
    expect(find.text('Free credits'), findsNothing);
  });

  testWidgets(
      'an account not yet claimed is offered its credits through the claim',
      (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson(needsClaim: true, balance: 0)));
    await pumpPill(
      tester,
      accountOverrides(
        server,
        session: signedInSession(profile: userJson(needsClaim: true, balance: 0)),
      ),
    );
    await tester.tap(find.byKey(const Key('credits_pill_free')));
    await settle(tester);
    expect(find.text('Choose a username to claim your free credits'), findsOneWidget);
  });

  testWidgets('coming back to the app reads the balance again', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson()));
    await pumpPill(
      tester,
      accountOverrides(server, session: signedInSession(profile: userJson())),
    );
    final before = server.to('GET', '/me').length;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);
    expect(server.to('GET', '/me').length, before + 1);
  });
}
