import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';

import '../../support/account_fakes.dart';

http.Response envelope(Object data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status);

http.Response failure(
  String code,
  int status, {
  Map<String, Object?>? details,
}) =>
    http.Response(
      jsonEncode({
        'success': false,
        'error': {
          'code': code,
          'message': 'm',
          if (details != null) 'details': details,
          'traceId': 't',
        },
      }),
      status,
    );

Matcher throwsCode(String code) => throwsA(
      isA<SlimshotApiException>().having((e) => e.code, 'code', code),
    );

SlimshotApi apiWith(
  MockClient client, {
  AccountSession? session,
  DeviceTokenStore? devices,
}) =>
    SlimshotApi(
      baseUrl: 'https://api.test/',
      client: client,
      session: session ?? signedInSession(access: 'a1', refresh: 'r1'),
      tokens: devices ?? MemoryDeviceTokens(),
    );

const fresh = {'accessToken': 'a2', 'refreshToken': 'r2', 'expiresIn': 900};

void main() {
  group('signed-in requests', () {
    test('carry the access token, and never register the install', () async {
      final seen = <http.Request>[];
      final api = apiWith(MockClient((request) async {
        seen.add(request);
        return envelope({'ok': true});
      }));
      await api.send(() => http.Request('GET', api.uri('/me')));

      expect(seen, hasLength(1));
      expect(seen.single.headers['Authorization'], 'Bearer a1');
      expect(seen.single.url.toString(), 'https://api.test/api/app/v1/me');
    });

    test('with no session nothing is sent: the user has to sign in', () async {
      var sends = 0;
      final api = apiWith(
        MockClient((_) async {
          sends++;
          return envelope({});
        }),
        session: AccountSession(vault: MemoryTokenVault()),
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.signInRequired),
      );
      expect(sends, 0);
    });

    test('an expired token is refreshed once and the request rebuilt',
        () async {
      var built = 0;
      late http.Request exchange;
      final session = signedInSession(access: 'a1', refresh: 'r1');
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            exchange = request;
            return envelope(fresh);
          }
          return request.headers['Authorization'] == 'Bearer a2'
              ? envelope({'ok': true})
              : failure('UNAUTHENTICATED', 401);
        }),
        session: session,
      );
      final data = await api.send(() {
        built++;
        return http.Request('GET', api.uri('/me'));
      });

      expect(data, {'ok': true});
      expect(built, 2);
      expect(jsonDecode(exchange.body), {'refreshToken': 'r1'});
      expect(exchange.headers['Authorization'], isNull);
      final saved = await session.read();
      expect((saved!.accessToken, saved.refreshToken), ('a2', 'r2'));
    });

    test('two requests refused at once share one refresh', () async {
      var refreshes = 0;
      final api = apiWith(MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return envelope(fresh);
        }
        return request.headers['Authorization'] == 'Bearer a2'
            ? envelope({'ok': true})
            : failure('UNAUTHENTICATED', 401);
      }));
      final results = await Future.wait([
        api.send(() => http.Request('GET', api.uri('/me'))),
        api.send(() => http.Request('GET', api.uri('/credits/history'))),
      ]);
      expect(results, [
        {'ok': true},
        {'ok': true},
      ]);
      expect(refreshes, 1);
    });

    test('a refused refresh ends the session', () async {
      final session = signedInSession(access: 'a1', refresh: 'r1');
      final api = apiWith(
        MockClient((request) async => failure('UNAUTHENTICATED', 401)),
        session: session,
      );
      final ended = expectLater(session.ended, emits(null));
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.signInRequired),
      );
      await ended;
      expect(await session.read(), isNull);
    });

    test('a refresh the server could not answer keeps the session', () async {
      final session = signedInSession(access: 'a1', refresh: 'r1');
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return http.Response('<html>Bad gateway</html>', 502);
          }
          return failure('UNAUTHENTICATED', 401);
        }),
        session: session,
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.badResponse),
      );
      expect((await session.read())!.accessToken, 'a1');
    });

    test('a refresh with no connection keeps the session', () async {
      final session = signedInSession(access: 'a1', refresh: 'r1');
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            throw http.ClientException('offline');
          }
          return failure('UNAUTHENTICATED', 401);
        }),
        session: session,
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.network),
      );
      expect((await session.read())!.accessToken, 'a1');
    });

    test('a second refusal is an answer, not a loop', () async {
      var sends = 0;
      var refreshes = 0;
      final session = signedInSession(access: 'a1', refresh: 'r1');
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshes++;
            return envelope(fresh);
          }
          sends++;
          return failure('UNAUTHENTICATED', 401);
        }),
        session: session,
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.signInRequired),
      );
      expect((sends, refreshes), (2, 1));
      expect(await session.read(), isNull);
    });

    test('SIGN_IN_REQUIRED from the server ends the session', () async {
      final session = signedInSession();
      final api = apiWith(
        MockClient((_) async => failure('SIGN_IN_REQUIRED', 401)),
        session: session,
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.signInRequired),
      );
      expect(await session.read(), isNull);
    });
  });

  group('sign-in requests', () {
    test('carry the install token in the body, registering once', () async {
      final seen = <http.Request>[];
      final devices = MemoryDeviceTokens();
      final api = apiWith(
        MockClient((request) async {
          seen.add(request);
          if (request.url.path.endsWith('/devices')) {
            return envelope({'token': 'dev-1'}, 201);
          }
          return envelope({'sentTo': 'ann@example.com'});
        }),
        devices: devices,
      );
      await api.sendWithDevice('/auth/email/start', {'email': 'ann@example.com'});
      await api.sendWithDevice('/auth/email/start', {'email': 'ann@example.com'});

      final registrations = seen.where((r) => r.url.path.endsWith('/devices'));
      expect(registrations, hasLength(1));
      expect(jsonDecode(registrations.single.body), {'platform': 'android'});
      final start = seen.last;
      expect(jsonDecode(start.body), {
        'email': 'ann@example.com',
        'deviceToken': 'dev-1',
      });
      expect(start.headers['Authorization'], isNull);
      expect(start.headers['Content-Type'], startsWith('application/json'));
      expect(devices.token, 'dev-1');
    });

    test('an install the server no longer knows is registered again, once',
        () async {
      final devices = MemoryDeviceTokens('stale');
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return envelope({'token': 'fresh'}, 201);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return body['deviceToken'] == 'fresh'
              ? envelope({'ok': true})
              : failure('DEVICE_NOT_REGISTERED', 422);
        }),
        devices: devices,
      );
      final data = await api.sendWithDevice('/auth/google', {'idToken': 'g'});
      expect(data, {'ok': true});
      expect(devices.token, 'fresh');
    });

    test('a public request carries no bearer', () async {
      late http.Request seen;
      final api = apiWith(MockClient((request) async {
        seen = request;
        return envelope({'loggedOut': true});
      }));
      await api.sendPublic(
        () => api.jsonRequest('POST', '/auth/logout', {'refreshToken': 'r1'}),
      );
      expect(seen.headers['Authorization'], isNull);
      expect(jsonDecode(seen.body), {'refreshToken': 'r1'});
    });
  });

  group('answers', () {
    test('a refusal carries its code, message and details', () async {
      final api = apiWith(
        MockClient(
          (_) async => failure('OTP_INVALID', 422, details: {'attemptsLeft': 3}),
        ),
        devices: MemoryDeviceTokens('dev-1'),
      );
      await expectLater(
        api.sendWithDevice('/auth/email/verify', {'code': '1'}),
        throwsA(
          isA<SlimshotApiException>()
              .having((e) => e.code, 'code', 'OTP_INVALID')
              .having((e) => e.message, 'message', 'm')
              .having((e) => e.detailInt('attemptsLeft'), 'attemptsLeft', 3),
        ),
      );
    });

    test('no connection is NETWORK', () async {
      final api = apiWith(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/x'))),
        throwsCode(SlimshotApiException.network),
      );
    });

    test('a request that never answers times out as NETWORK', () async {
      final api = apiWith(
        MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        api.send(
          () => http.Request('GET', api.uri('/x')),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsCode(SlimshotApiException.network),
      );
    });

    test('a body that is not the envelope is BAD_RESPONSE', () async {
      final api = apiWith(MockClient((_) async => http.Response('<html>', 502)));
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/x'))),
        throwsCode(SlimshotApiException.badResponse),
      );
    });

    test('a build without a server address has no server', () {
      expect(SlimshotApi.isConfigured, isFalse);
    });
  });
}
