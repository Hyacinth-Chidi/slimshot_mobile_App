import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';

import '../../support/account_fakes.dart';
import '../../support/fake_server.dart';

Matcher throwsCode(String code) => throwsA(
      isA<SlimshotApiException>().having((e) => e.code, 'code', code),
    );

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  SlimshotApi api({AccountSession? session}) => fakeApi(
        server,
        session: session ?? signedInSession(access: 'a1', refresh: 'r1'),
      );

  http.Request download(SlimshotApi api) =>
      http.Request('GET', api.uri('/speech/tts_1/items/t0'));

  test("returns the body's bytes on 200", () async {
    server.on(
      'GET',
      '/speech/tts_1/items/t0',
      (_) => http.Response.bytes(
        [73, 68, 51, 4, 0, 255],
        200,
        headers: {'content-type': 'audio/mpeg'},
      ),
    );
    final client = api();

    final bytes = await client.sendForBytes(() => download(client));

    expect(bytes, [73, 68, 51, 4, 0, 255]);
    expect(
      server.to('GET', '/speech/tts_1/items/t0').single.headers['Authorization'],
      'Bearer a1',
    );
  });

  test('refreshes once on UNAUTHENTICATED and sends again', () async {
    var built = 0;
    server
      ..on(
        'POST',
        '/auth/refresh',
        (_) => envelope(
          {'accessToken': 'a2', 'refreshToken': 'r2', 'expiresIn': 900},
        ),
      )
      ..on(
        'GET',
        '/speech/tts_1/items/t0',
        (request) => request.headers['Authorization'] == 'Bearer a2'
            ? http.Response.bytes([1, 2, 3], 200)
            : failure('UNAUTHENTICATED', 401),
      );
    final client = api();

    final bytes = await client.sendForBytes(() {
      built++;
      return download(client);
    });

    expect(bytes, [1, 2, 3]);
    expect(built, 2);
    expect(server.to('POST', '/auth/refresh'), hasLength(1));
  });

  test("a refusal is decoded like send's", () async {
    server.on(
      'GET',
      '/speech/tts_1/items/t0',
      (_) => failure('NOT_FOUND', 404),
    );
    final client = api();
    await expectLater(
      client.sendForBytes(() => download(client)),
      throwsCode('NOT_FOUND'),
    );

    // A proxy's page is no answer at all, never a file.
    server.on(
      'GET',
      '/speech/tts_1/items/t0',
      (_) => http.Response('<html>Bad gateway</html>', 502),
    );
    await expectLater(
      client.sendForBytes(() => download(client)),
      throwsCode(SlimshotApiException.badResponse),
    );
  });

  test('no session is SIGN_IN_REQUIRED', () async {
    final client = api(session: AccountSession(vault: MemoryTokenVault()));

    await expectLater(
      client.sendForBytes(() => download(client)),
      throwsCode(SlimshotApiException.signInRequired),
    );
    expect(server.requests, isEmpty);
  });
}
