import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/features/account/logic/username_rules.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/account/widgets/settings_account_section.dart';

import '../../../support/account_fakes.dart';
import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  setUp(() {
    server = FakeServer()..on('GET', '/me', (_) => envelope(userJson()));
  });

  Future<void> pumpSection(WidgetTester tester, List<Override> overrides) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SettingsAccountSection()),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  AccountSession signedIn() => signedInSession(refresh: 'r1', profile: userJson());

  testWidgets('a build without a server has no account section', (tester) async {
    await pumpSection(tester, [accountFeatureProvider.overrideWithValue(false)]);
    expect(find.text('ACCOUNT'), findsNothing);
  });

  testWidgets('signed out it offers to sign in', (tester) async {
    await pumpSection(tester, accountOverrides(server));
    expect(find.text('ACCOUNT'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await settle(tester);
    expect(find.text('Sign in to get free credits'), findsOneWidget);
  });

  testWidgets('signed in it shows the username and the email', (tester) async {
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    expect(find.text('ann_1'), findsOneWidget);
    expect(find.text('ann@example.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('signing out asks first, then ends the session', (tester) async {
    server.on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Sign out'));
    await settle(tester);

    // Device-reported: one tap signed the user straight out.
    expect(find.text('Sign out of ann_1?'), findsOneWidget);
    expect(server.to('POST', '/auth/logout'), isEmpty);
    expect(find.text('ann_1'), findsOneWidget, reason: 'still signed in');

    await tester.tap(find.byKey(const Key('sign_out_confirm')));
    await settle(tester);
    expect(server.lastBody('POST', '/auth/logout'), {'refreshToken': 'r1'});
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Signed out'), findsOneWidget);
  });

  testWidgets('Cancel keeps the account signed in', (tester) async {
    server.on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Sign out'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(find.text('Sign out of ann_1?'), findsNothing);
    expect(server.to('POST', '/auth/logout'), isEmpty);
    expect(find.text('ann_1'), findsOneWidget);
    final container = containerOf(tester);
    expect(container.read(accountProvider).isSignedIn, isTrue);
  });

  testWidgets('deleting asks first, then deletes with the confirmation',
      (tester) async {
    server.on('DELETE', '/me', (_) => envelope({'deleted': true}));
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Delete account'));
    await settle(tester);
    expect(find.text("Your credits will be lost. This can't be undone."), findsOneWidget);
    expect(server.to('DELETE', '/me'), isEmpty);

    await tester.tap(find.byKey(const Key('delete_account_confirm')));
    await settle(tester);
    expect(server.lastBody('DELETE', '/me'), {'confirm': 'DELETE'});
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Account deleted'), findsOneWidget);
  });

  testWidgets('a deletion that fails says so and keeps the account',
      (tester) async {
    server.on(
      'DELETE',
      '/me',
      (_) => failure('RATE_LIMITED', 429, details: {'retryAfterSeconds': 30}),
    );
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Delete account'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('delete_account_confirm')));
    await settle(tester);

    expect(find.text('Try again in 30s.'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsAccountSection)),
    );
    expect(container.read(accountProvider).isSignedIn, isTrue);
  });

  testWidgets('the username can be changed', (tester) async {
    server
      ..on(
        'GET',
        '/usernames/ann_2/availability',
        (_) => envelope({'username': 'ann_2', 'available': true}),
      )
      ..on('PATCH', '/me/username', (_) => envelope(userJson(username: 'ann_2')));
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Username'));
    await settle(tester);

    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('username_field')), 'ann_2');
    await tester.pump(kUsernameCheckDelay);
    await settle(tester);
    await tester.tap(save);
    await settle(tester);

    expect(server.lastBody('PATCH', '/me/username'), {'username': 'ann_2'});
    expect(find.text('ann_2'), findsOneWidget);
  });

  testWidgets('signed in, a Credits row opens Credits', (tester) async {
    server.on('GET', '/credits/history',
        (_) => envelope({'items': [], 'nextCursor': null}));
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Credits'));
    await settle(tester);
    expect(find.byKey(const Key('credits_balance')), findsOneWidget);
  });
}
