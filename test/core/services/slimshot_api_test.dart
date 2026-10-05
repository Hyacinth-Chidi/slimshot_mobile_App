import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';

class MemoryTokens implements DeviceTokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

http.Response envelope(Object data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status);

http.Response failure(String code, int status) => http.Response(
      jsonEncode({
        'success': false,
        'error': {'code': code, 'message': 'm', 'traceId': 't'},
      }),
      status,
    );

Matcher throwsCode(String code) => throwsA(
      isA<SlimshotApiException>().having((e) => e.code, 'code', code),
    );

void main() {
  test('registers once, keeps the token, and sends it', () async {
    final seen = <http.Request>[];
    final tokens = MemoryTokens();
    final api = SlimshotApi(
      baseUrl: 'https://api.test/',
      tokens: tokens,
      client: MockClient((request) async {
        seen.add(request);
        if (request.url.path.endsWith('/devices')) {
          return envelope({'token': 'tok-1'}, 201);
        }
        return envelope({'ok': true});
      }),
    );
    await api.send(() => http.Request('GET', api.uri('/captions/x')));
    await api.send(() => http.Request('GET', api.uri('/captions/x')));

    expect(
      seen.where((r) => r.url.path == '/api/app/v1/devices'),
      hasLength(1),
    );
    expect(jsonDecode(seen.first.body), {'platform': 'android'});
    expect(tokens.token, 'tok-1');
    expect(seen.last.headers['Authorization'], 'Bearer tok-1');
    expect(seen.last.url.toString(), 'https://api.test/api/app/v1/captions/x');
  });

  test('a stored token is used without registering', () async {
    var registrations = 0;
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens()..token = 'kept',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/devices')) registrations++;
        return envelope({'auth': request.headers['Authorization']});
      }),
    );
    final data = await api.send(() => http.Request('GET', api.uri('/x')));
    expect(data, {'auth': 'Bearer kept'});
    expect(registrations, 0);
  });

  test(
      'a token the server no longer knows is replaced once and the request rebuilt',
      () async {
    var built = 0;
    final tokens = MemoryTokens()..token = 'stale';
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: tokens,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/devices')) {
          return envelope({'token': 'fresh'}, 201);
        }
        return request.headers['Authorization'] == 'Bearer fresh'
            ? envelope({'ok': true})
            : failure('UNAUTHENTICATED', 401);
      }),
    );
    final data = await api.send(() {
      built++;
      return http.Request('GET', api.uri('/x'));
    });
    expect(data, {'ok': true});
    expect(built, 2);
    expect(tokens.token, 'fresh');
  });

  test('a second refusal is an answer, not a loop', () async {
    var registrations = 0;
    var sends = 0;
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/devices')) {
          registrations++;
          return envelope({'token': 'tok-$registrations'}, 201);
        }
        sends++;
        return failure('UNAUTHENTICATED', 401);
      }),
    );
    await expectLater(
      api.send(() => http.Request('GET', api.uri('/x'))),
      throwsCode('UNAUTHENTICATED'),
    );
    expect(sends, 2);
    expect(registrations, 2);
  });

  test('a server refusal carries its code and message', () async {
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens()..token = 't',
      client: MockClient((_) async => failure('CAPTIONS_UNAVAILABLE', 503)),
    );
    await expectLater(
      api.send(() => http.Request('GET', api.uri('/x'))),
      throwsA(
        isA<SlimshotApiException>()
            .having((e) => e.code, 'code', 'CAPTIONS_UNAVAILABLE')
            .having((e) => e.message, 'message', 'm'),
      ),
    );
  });

  test('no connection is NETWORK', () async {
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens()..token = 't',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      api.send(() => http.Request('GET', api.uri('/x'))),
      throwsCode(SlimshotApiException.network),
    );
  });

  test('a request that never answers times out as NETWORK', () async {
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens()..token = 't',
      client: MockClient((_) => Completer<http.Response>().future),
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
    final api = SlimshotApi(
      baseUrl: 'https://api.test',
      tokens: MemoryTokens()..token = 't',
      client: MockClient((_) async => http.Response('<html>', 502)),
    );
    await expectLater(
      api.send(() => http.Request('GET', api.uri('/x'))),
      throwsCode(SlimshotApiException.badResponse),
    );
  });

  test('a build without a server address has no server', () {
    expect(SlimshotApi.isConfigured, isFalse);
  });
}
