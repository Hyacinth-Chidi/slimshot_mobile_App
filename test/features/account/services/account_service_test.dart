import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/account/services/account_service.dart';

import '../../../support/account_fakes.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  AccountService service({bool signedIn = false}) => AccountService(
        fakeApi(
          server,
          session: signedIn ? signedInSession(access: 'a1', refresh: 'r1') : null,
        ),
      );

  test('Google sign-in sends the ID token and the install', () async {
    server.on('POST', '/auth/google', (_) => envelope(signInJson()));
    final result = await service().signInWithGoogle('id-1');

    expect(server.lastBody('POST', '/auth/google'), {
      'idToken': 'id-1',
      'deviceToken': 'dev-1',
    });
    expect(result.tokens.accessToken, 'a1');
    expect(result.tokens.refreshToken, 'r1');
    expect(result.user.username, 'ann_1');
  });

  test('an email code is asked for, then checked', () async {
    server
      ..on(
        'POST',
        '/auth/email/start',
        (_) => envelope({
          'sentTo': 'ann@example.com',
          'resendAfterSeconds': 60,
          'expiresInSeconds': 600,
        }),
      )
      ..on('POST', '/auth/email/verify', (_) => envelope(signInJson()));
    final accounts = service();

    final sent = await accounts.startEmail('ann@example.com');
    expect(sent.sentTo, 'ann@example.com');
    expect(sent.resendAfter, const Duration(seconds: 60));

    final result = await accounts.verifyEmail('ann@example.com', '123456');
    expect(server.lastBody('POST', '/auth/email/verify'), {
      'email': 'ann@example.com',
      'code': '123456',
      'deviceToken': 'dev-1',
    });
    expect(result.user.email, 'ann@example.com');
  });

  test('a sign-in answer without a session is BAD_RESPONSE', () async {
    server.on('POST', '/auth/google', (_) => envelope({'user': userJson()}));
    await expectLater(
      service().signInWithGoogle('id-1'),
      throwsA(isA<SlimshotApiException>()
          .having((e) => e.code, 'code', SlimshotApiException.badResponse)),
    );
  });

  test('the profile is read signed in', () async {
    server.on('GET', '/me', (_) => envelope(userJson(balance: 94)));
    final user = await service(signedIn: true).me();

    expect(server.to('GET', '/me').single.headers['Authorization'], 'Bearer a1');
    expect(user.creditBalance, 94);
    expect(user.referralCode, 'AB3DEF7K');
    expect(user.suspended, isFalse);
    expect(user.needsClaim, isFalse);
  });

  test('a suspended account reads as suspended', () async {
    server.on('GET', '/me', (_) => envelope(userJson(status: 'suspended')));
    expect((await service(signedIn: true).me()).suspended, isTrue);
  });

  test('availability asks about exactly the name typed', () async {
    server.on(
      'GET',
      '/usernames/ann_1/availability',
      (_) => envelope({'username': 'ann_1', 'available': false, 'reason': 'TAKEN'}),
    );
    final answer = await service(signedIn: true).usernameAvailability('ann_1');
    expect(answer.available, isFalse);
    expect(answer.reason, 'TAKEN');
  });

  test('a username change says what was asked', () async {
    server.on('PATCH', '/me/username', (_) => envelope(userJson(username: 'new_name')));
    final user = await service(signedIn: true).changeUsername('new_name');
    expect(server.lastBody('PATCH', '/me/username'), {'username': 'new_name'});
    expect(user.username, 'new_name');
  });

  test('a claim without a code sends no code, and reports the bonus', () async {
    server.on(
      'POST',
      '/me/claim',
      (_) => envelope({
        'user': userJson(),
        'bonus': {'granted': true, 'credits': 100},
        'referral': null,
      }),
    );
    final result = await service(signedIn: true).claim(username: 'ann_1');

    expect(server.lastBody('POST', '/me/claim'), {'username': 'ann_1'});
    expect(result.bonusCredits, 100);
    expect(result.referralOutcome, isNull);
    expect(result.creditsGranted, 100);
  });

  test('a claim with a code sends it, and reports the referral', () async {
    server.on(
      'POST',
      '/me/claim',
      (_) => envelope({
        'user': userJson(balance: 120),
        'bonus': {'granted': true, 'credits': 100},
        'referral': {'outcome': 'rewarded', 'credits': 20},
      }),
    );
    final result = await service(signedIn: true)
        .claim(username: 'ann_1', referralCode: 'AB3DEF7K');

    expect(server.lastBody('POST', '/me/claim'), {
      'username': 'ann_1',
      'referralCode': 'AB3DEF7K',
    });
    expect(result.referralOutcome, 'rewarded');
    expect(result.creditsGranted, 120);
  });

  test('a claim without a bonus says why', () async {
    server.on(
      'POST',
      '/me/claim',
      (_) => envelope({
        'user': userJson(balance: 0),
        'bonus': {'granted': false, 'reason': 'BONUS_ALREADY_CLAIMED'},
        'referral': null,
      }),
    );
    final result = await service(signedIn: true).claim(username: 'ann_1');
    expect(result.bonusCredits, 0);
    expect(result.bonusReason, 'BONUS_ALREADY_CLAIMED');
  });

  test('logout sends the refresh token, without a bearer', () async {
    server.on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    await service(signedIn: true).logout('r1');
    final request = server.to('POST', '/auth/logout').single;
    expect(server.lastBody('POST', '/auth/logout'), {'refreshToken': 'r1'});
    expect(request.headers['Authorization'], isNull);
  });

  test('deleting the account confirms in the body', () async {
    server.on('DELETE', '/me', (_) => envelope({'deleted': true}));
    await service(signedIn: true).deleteAccount();
    final request = server.to('DELETE', '/me').single;
    expect(server.lastBody('DELETE', '/me'), {'confirm': 'DELETE'});
    expect(request.headers['Content-Type'], startsWith('application/json'));
    expect(request.headers['Authorization'], 'Bearer a1');
  });

  test('a profile survives a round trip through JSON', () {
    final user = AccountUser.fromJson(userJson(status: 'suspended'));
    final again = AccountUser.fromJson(user.toJson());
    expect(again.id, user.id);
    expect(again.email, user.email);
    expect(again.username, user.username);
    expect(again.referralCode, user.referralCode);
    expect(again.creditBalance, user.creditBalance);
    expect(again.suspended, isTrue);
    expect(again.needsClaim, user.needsClaim);
  });

  test('a quote sends the feature and the audio length, signed in', () async {
    server.on(
      'POST',
      '/credits/quote',
      (_) => envelope({
        'credits': 6,
        'balance': 94,
        'enough': true,
        'pricingVersion': 3,
      }),
    );
    final quote = await service(signedIn: true)
        .quote(AccountService.autoCaptionsFeature, 125.4);

    expect(server.lastBody('POST', '/credits/quote'), {
      'feature': 'auto_captions',
      'durationSeconds': 125.4,
    });
    expect(
      server.to('POST', '/credits/quote').last.headers['Authorization'],
      'Bearer a1',
    );
    expect((quote.credits, quote.balance, quote.enough), (6, 94, true));
    expect(quote.isFree, isFalse);
  });

  test('a free quote is free, and a short one is not enough', () {
    expect(
      CreditQuote.fromJson({'credits': 0, 'balance': 3, 'enough': true}).isFree,
      isTrue,
    );
    final short =
        CreditQuote.fromJson({'credits': 6, 'balance': 2, 'enough': false});
    expect((short.enough, short.isFree), (false, false));
  });

  test("a quote missing 'enough' works it out rather than guessing yes", () {
    expect(CreditQuote.fromJson({'credits': 6, 'balance': 2}).enough, isFalse);
    expect(CreditQuote.fromJson({'credits': 6, 'balance': 6}).enough, isTrue);
  });
}
