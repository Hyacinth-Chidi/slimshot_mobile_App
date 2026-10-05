import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';

import '../../../support/account_fakes.dart';
import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  ProviderContainer containerWith({
    AccountSession? session,
    FakeGoogleIdTokens? google,
  }) {
    final container = ProviderContainer(
      overrides: accountOverrides(server, session: session, google: google),
    );
    addTearDown(container.dispose);
    return container;
  }

  test('with no session the app is signed out and asks nothing', () async {
    final c = containerWith();
    expect(c.read(accountProvider).isSignedIn, isFalse);
    await pumpEventQueue();
    expect(server.requests, isEmpty);
  });

  test("a kept session shows the last profile at once, then the server's",
      () async {
    final answer = Completer<http.Response>();
    server.on('GET', '/me', (_) => answer.future);
    final c = containerWith(session: signedInSession(profile: userJson(balance: 100)));

    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).user!.creditBalance, 100);

    answer.complete(envelope(userJson(balance: 80)));
    await pumpEventQueue();
    expect(c.read(accountProvider).user!.creditBalance, 80);
  });

  test('offline, the last profile stays', () async {
    server.on('GET', '/me', (_) => throw http.ClientException('offline'));
    final c = containerWith(session: signedInSession(profile: userJson(balance: 100)));
    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).user!.creditBalance, 100);
  });

  test('a profile another build wrote waits for the server, never fails',
      () async {
    final session = signedInSession();
    await session.saveProfile('{not json');
    server.on('GET', '/me', (_) => envelope(userJson(balance: 7)));
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).user!.creditBalance, 7);
  });

  test('a session ended anywhere signs the whole app out', () async {
    server.on('GET', '/me', (_) => envelope(userJson()));
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).isSignedIn, isTrue);

    await session.end(); // say, a caption upload refused with SIGN_IN_REQUIRED
    await pumpEventQueue();
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });

  test('a server that no longer knows the session signs the app out',
      () async {
    server.on('GET', '/me', (_) => failure('SIGN_IN_REQUIRED', 401));
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).isSignedIn, isFalse);
    expect(await session.readProfile(), isNull);
  });

  test('signing in keeps the session and the profile', () async {
    final session = AccountSession(vault: MemoryTokenVault());
    final c = containerWith(session: session);
    await c
        .read(accountProvider.notifier)
        .completeSignIn(SignInResult.fromJson(signInJson()));

    expect((await session.read())!.accessToken, 'a1');
    expect(await session.readProfile(), contains('ann@example.com'));
    expect(c.read(accountProvider).user!.username, 'ann_1');
  });

  test('signing out tells the server, forgets everything and leaves Google',
      () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson()))
      ..on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    final google = FakeGoogleIdTokens();
    final session = signedInSession(refresh: 'r9', profile: userJson());
    final c = containerWith(session: session, google: google);
    c.read(accountProvider);
    await pumpEventQueue();

    await c.read(accountProvider.notifier).signOut();
    await pumpEventQueue(); // the server is told after the phone forgets
    expect(server.lastBody('POST', '/auth/logout'), {'refreshToken': 'r9'});
    expect(await session.read(), isNull);
    expect(await session.readProfile(), isNull);
    expect(google.signOuts, 1);
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });

  test('signing out works with no connection', () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson()))
      ..on('POST', '/auth/logout', (_) => throw http.ClientException('offline'));
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();

    await c.read(accountProvider.notifier).signOut();
    expect(c.read(accountProvider).isSignedIn, isFalse);
    expect(await session.read(), isNull);
  });

  test('signing out does not wait for the server', () async {
    // A dead connection — Wi-Fi without internet — would hold the logout for
    // its whole timeout; the phone must be signed out at once regardless.
    final hang = Completer<http.Response>();
    addTearDown(() => hang.complete(envelope({'loggedOut': true})));
    server
      ..on('GET', '/me', (_) => envelope(userJson()))
      ..on('POST', '/auth/logout', (_) => hang.future);
    final session = signedInSession(refresh: 'r9', profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();

    await c
        .read(accountProvider.notifier)
        .signOut()
        .timeout(const Duration(seconds: 1));
    expect(c.read(accountProvider).isSignedIn, isFalse);
    expect(await session.read(), isNull);
    await pumpEventQueue();
    expect(server.lastBody('POST', '/auth/logout'), {'refreshToken': 'r9'});
  });

  test('a token refresh that lands after signing out does not sign back in',
      () async {
    // The access token expired while the app was away; coming back, the
    // first request is refused and a refresh goes out — and the user signs
    // out before it answers.
    final exchange = Completer<http.Response>();
    server
      ..on(
        'GET',
        '/me',
        (r) => r.headers['Authorization'] == 'Bearer a2'
            ? envelope(userJson())
            : failure('UNAUTHENTICATED', 401),
      )
      ..on('POST', '/auth/refresh', (_) => exchange.future)
      ..on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    final vault = MemoryTokenVault()
      ..values[AccountSession.accessKey] = 'a1'
      ..values[AccountSession.refreshKey] = 'r1';
    final c = containerWith(session: AccountSession(vault: vault));
    c.read(accountProvider); // restore → /me refused → refresh, which hangs
    await pumpEventQueue();

    await c.read(accountProvider.notifier).signOut();
    exchange.complete(
      envelope({'accessToken': 'a2', 'refreshToken': 'r2', 'expiresIn': 900}),
    );
    await pumpEventQueue();

    expect(vault.values, isEmpty);
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });

  test('a profile that lands after signing out is not kept', () async {
    final late = Completer<http.Response>();
    server
      ..on('GET', '/me', (_) => late.future)
      ..on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider); // restore asks /me, which hangs
    await pumpEventQueue();

    await c.read(accountProvider.notifier).signOut();
    late.complete(envelope(userJson()));
    await pumpEventQueue();

    expect(await session.readProfile(), isNull);
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });

  test('a profile written while signing out is taken back', () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson()))
      ..on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    final vault = _GatedVault()
      ..values[AccountSession.accessKey] = 'tok'
      ..values[AccountSession.refreshKey] = 'ref'
      ..gate = Completer<void>();
    final c = containerWith(session: AccountSession(vault: vault));
    c.read(accountProvider); // restore: /me answers, the profile write waits
    await pumpEventQueue();

    await c.read(accountProvider.notifier).signOut();
    vault.gate!.complete();
    await pumpEventQueue();

    expect(vault.values.containsKey(AccountSession.profileKey), isFalse);
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });

  test('deleting the account confirms it and forgets everything', () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson()))
      ..on('DELETE', '/me', (_) => envelope({'deleted': true}));
    final google = FakeGoogleIdTokens();
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session, google: google);
    c.read(accountProvider);
    await pumpEventQueue();

    await c.read(accountProvider.notifier).deleteAccount();
    expect(server.lastBody('DELETE', '/me'), {'confirm': 'DELETE'});
    expect(await session.read(), isNull);
    expect(google.signOuts, 1);
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });

  test('a deletion the server refused keeps the account', () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson()))
      ..on('DELETE', '/me', (_) => failure('RATE_LIMITED', 429));
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();

    await expectLater(
      c.read(accountProvider.notifier).deleteAccount(),
      throwsA(isA<SlimshotApiException>()),
    );
    expect(c.read(accountProvider).isSignedIn, isTrue);
    expect(await session.read(), isNotNull);
  });

  test('an older answer never overwrites a newer one', () async {
    // The launch's /me is still on its way when the user claims; when it
    // lands it must not put the account back to "not claimed".
    final slowMe = Completer<http.Response>();
    server
      ..on('GET', '/me', (_) => slowMe.future)
      ..on(
        'POST',
        '/me/claim',
        (_) => envelope({
          'user': userJson(balance: 100),
          'bonus': {'granted': true, 'credits': 100},
          'referral': null,
        }),
      );
    final c = containerWith(
      session: signedInSession(profile: userJson(needsClaim: true, balance: 0)),
    );
    c.read(accountProvider);
    await pumpEventQueue();

    await c.read(accountProvider.notifier).claim(username: 'ann_1');
    slowMe.complete(envelope(userJson(needsClaim: true, balance: 0)));
    await pumpEventQueue();

    expect(c.read(accountProvider).needsClaim, isFalse);
    expect(c.read(accountProvider).user!.creditBalance, 100);
  });

  test('claiming adopts the claimed profile', () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson(needsClaim: true, balance: 0)))
      ..on(
        'POST',
        '/me/claim',
        (_) => envelope({
          'user': userJson(balance: 100),
          'bonus': {'granted': true, 'credits': 100},
          'referral': null,
        }),
      );
    final c = containerWith(
      session: signedInSession(profile: userJson(needsClaim: true, balance: 0)),
    );
    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).needsClaim, isTrue);

    final result = await c.read(accountProvider.notifier).claim(username: 'ann_1');
    expect(result.creditsGranted, 100);
    expect(c.read(accountProvider).needsClaim, isFalse);
    expect(c.read(accountProvider).user!.creditBalance, 100);
  });
}

/// A vault whose profile writes wait on [gate] — how a slow keystore write
/// overlaps a sign-out.
class _GatedVault extends MemoryTokenVault {
  Completer<void>? gate;

  @override
  Future<void> write(String key, String value) async {
    final wait = gate;
    if (key == AccountSession.profileKey && wait != null) await wait.future;
    await super.write(key, value);
  }
}
