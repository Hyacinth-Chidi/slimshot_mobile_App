import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/account/widgets/sign_in_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';

import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  late FakeGoogleIdTokens google;

  setUp(() {
    server = FakeServer()
      ..on(
        'POST',
        '/auth/email/start',
        (_) => envelope({
          'sentTo': 'ann@example.com',
          'resendAfterSeconds': 60,
          'expiresInSeconds': 600,
        }),
      )
      ..on('POST', '/auth/email/verify', (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return body['code'] == '123456'
            ? envelope(signInJson())
            : failure('OTP_INVALID', 422, details: {'attemptsLeft': 3});
      })
      ..on('POST', '/auth/google', (_) => envelope(signInJson()));
    google = FakeGoogleIdTokens();
  });

  Future<List<Object?>> open(WidgetTester tester) async {
    final results = await pumpHost(
      tester,
      accountOverrides(server, google: google),
      (context, ref) => showEditorSheet<bool>(
        context,
        builder: (_) => const SignInSheet(reason: 'Sign in to use Auto captions'),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return results;
  }

  Future<void> sendCode(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('sign_in_email')), 'ann@example.com');
    await tester.tap(find.text('Continue'));
    await settle(tester);
  }

  testWidgets('says why it opened, and offers Google and email', (tester) async {
    await open(tester);
    expect(find.text('Sign in to use Auto captions'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byKey(const Key('sign_in_email')), findsOneWidget);
  });

  testWidgets('without Google set up, email is the only way in', (tester) async {
    google = FakeGoogleIdTokens(isAvailable: false);
    await open(tester);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.byKey(const Key('sign_in_email')), findsOneWidget);
  });

  testWidgets('something that is not an email is not sent', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('sign_in_email')), 'ann');
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(server.requests, isEmpty);
  });

  testWidgets('an email gets a code, and asking again waits', (tester) async {
    await open(tester);
    await sendCode(tester);

    expect(server.lastBody('POST', '/auth/email/start'), {
      'email': 'ann@example.com',
      'deviceToken': 'dev-1',
    });
    expect(find.text('Code sent to ann@example.com'), findsOneWidget);
    expect(find.text('Send again in 60s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 60));
    expect(find.text('Send a new code'), findsOneWidget);
  });

  testWidgets('the right code signs in and closes the sheet', (tester) async {
    final results = await open(tester);
    await sendCode(tester);
    await tester.enterText(find.byKey(const Key('sign_in_code')), '123456');
    await settle(tester);

    expect(results, [true]);
    final container = containerOf(tester);
    expect(container.read(accountProvider).isSignedIn, isTrue);
    expect((await container.read(accountSessionProvider).read())!.accessToken, 'a1');
  });

  testWidgets('a wrong code says how many tries are left', (tester) async {
    final results = await open(tester);
    await sendCode(tester);
    await tester.enterText(find.byKey(const Key('sign_in_code')), '111111');
    await settle(tester);

    expect(find.text('Wrong code · 3 tries left'), findsOneWidget);
    expect(results, isEmpty);
    final code = tester.widget<TextField>(find.byKey(const Key('sign_in_code')));
    expect(code.controller!.text, isEmpty);
  });

  testWidgets('a disposable address is refused in one line', (tester) async {
    server.on(
      'POST',
      '/auth/email/start',
      (_) => failure('EMAIL_DOMAIN_NOT_ALLOWED', 422),
    );
    await open(tester);
    await sendCode(tester);
    expect(find.text('Use a regular email address.'), findsOneWidget);
    expect(find.byKey(const Key('sign_in_email')), findsOneWidget);
  });

  testWidgets('Google signs in with the token the picker gave', (tester) async {
    final results = await open(tester);
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);

    expect(server.lastBody('POST', '/auth/google'), {
      'idToken': 'google-id-token',
      'deviceToken': 'dev-1',
    });
    expect(results, [true]);
  });

  testWidgets('closing the Google picker changes nothing', (tester) async {
    google.idToken = null;
    final results = await open(tester);
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);

    expect(google.requests, 1);
    expect(server.to('POST', '/auth/google'), isEmpty);
    expect(results, isEmpty);
    expect(find.text('Sign in to use Auto captions'), findsOneWidget);
  });

  testWidgets('a Google account without a verified email is pointed at email',
      (tester) async {
    server.on('POST', '/auth/google', (_) => failure('GOOGLE_EMAIL_UNVERIFIED', 422));
    await open(tester);
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);
    expect(find.text('Use your email instead.'), findsOneWidget);
  });
}
