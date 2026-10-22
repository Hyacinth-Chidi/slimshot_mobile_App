import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/fonts/data/font_client.dart';

import '../../support/account_fakes.dart';
import 'support.dart';

/// The answers come from the server's contract, `app-catalog-api.md` §8.
void main() {
  late List<http.Request> requests;

  FontClient clientWith(http.Response Function(http.Request) answer) {
    requests = [];
    return FontClient(SlimshotApi(
      baseUrl: 'https://api.test',
      session: signedInSession(access: 'a', refresh: 'r'),
      tokens: MemoryDeviceTokens(),
      client: MockClient((request) async {
        requests.add(request);
        return answer(request);
      }),
    ));
  }

  test('list asks for every published font, with no category', () async {
    final client = clientWith((_) => FakeFontServer.ok([fontRow('pd', 'Playfair Display')]));
    final fonts = await client.list();
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/app/v1/catalog/fonts');
    expect(request.url.queryParameters, isEmpty);
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(fonts.single.name, 'Playfair Display');
  });

  test('by id asks for the font', () async {
    final client = clientWith((_) => FakeFontServer.ok(fontRow('lb', 'Lato', style: 'Bold')));
    final font = await client.byId('lb');
    expect(requests.single.url.path, '/api/app/v1/catalog/fonts/lb');
    expect(font.name, 'Lato Bold');
  });

  test('by family encodes the name', () async {
    final client = clientWith((_) => FakeFontServer.ok(fontRow('pd', 'Playfair Display')));
    await client.byFamily('Playfair Display');
    expect(requests.single.url.toString(),
        endsWith('/api/app/v1/catalog/fonts/by-family/Playfair%20Display'));
  });

  test('download posts to the asset and reads the version', () async {
    final client = clientWith((_) => FakeFontServer.ok({
          'url': 'https://cdn.test/fonts/pd-v2.ttf',
          'expiresAt': '2026-10-22T12:10:00.000Z',
          'filename': 'PlayfairDisplay-Regular.ttf',
          'format': 'ttf',
          'byteSize': 301268,
          'version': 2,
        }));
    final ticket = await client.download('pd');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/app/v1/catalog/assets/pd/download');
    expect(ticket.version, 2);
    expect(ticket.url, 'https://cdn.test/fonts/pd-v2.ttf');
  });

  test('a 404 is a NOT_FOUND exception', () async {
    final client = clientWith((_) => FakeFontServer.error('NOT_FOUND', 404));
    await expectLater(
      client.byId('gone'),
      throwsA(isA<SlimshotApiException>().having((e) => e.code, 'code', 'NOT_FOUND')),
    );
  });

  test('an answer that is not a font is a bad response', () async {
    final client = clientWith((_) => FakeFontServer.ok({'nothing': true}));
    await expectLater(
      client.byId('x'),
      throwsA(isA<SlimshotApiException>()
          .having((e) => e.code, 'code', SlimshotApiException.badResponse)),
    );
  });
}
