import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    await tester.pump(); // the button enables on the next frame
    await tester.tap(find.text('Continue'));
    await settle(tester);
  }

  testWidgets('says why it opened, and offers Google and email', (tester) async {
    await open(tester);
    expect(find.text('Sign in to use Auto captions'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byKey(const Key('sign_in_email')), findsOneWidget);
  });

  testWidgets("the Google button carries Google's own G", (tester) async {
    await open(tester);
    final logo = find.descendant(
      of: find.widgetWithText(OutlinedButton, 'Continue with Google'),
      matching: find.byType(SvgPicture),
    );
    expect(logo, findsOneWidget);
    final loader = tester.widget<SvgPicture>(logo).bytesLoader as SvgAssetLoader;
    expect(loader.assetName, 'assets/google_g.svg');
  });

  testWidgets('the Google button fits a narrow phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('without Google set up, email is the only way in', (tester) async {
    google = FakeGoogleIdTokens(isAvailable: false);
    await open(tester);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.byKey(const Key('sign_in_email')), findsOneWidget);
  });

  testWidgets('Continue waits for an email address', (tester) async {
    VoidCallback? continueButton() => tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
        .onPressed;

    await open(tester);
    expect(continueButton(), isNull, reason: 'nothing typed');

    await tester.enterText(find.byKey(const Key('sign_in_email')), 'ann');
    await tester.pump();
    expect(continueButton(), isNull, reason: 'not an email address yet');

    await tester.enterText(
      find.byKey(const Key('sign_in_email')),
      'ann@example.com',
    );
    await tester.pump();
    expect(continueButton(), isNotNull);
  });

  testWidgets('the keyboard\'s done key sends nothing until it is an email',
      (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('sign_in_email')), 'ann');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
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
