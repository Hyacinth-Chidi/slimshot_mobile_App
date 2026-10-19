import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/sound_library/data/catalog_client.dart';
import 'package:slimshotai/features/sound_library/data/catalog_models.dart';

import '../../support/account_fakes.dart';

/// The answers below are copied from the server's contract,
/// `slimshot_server/docs/app-catalog-api.md` §3.
const _categories = [
  {'id': 'cm1alerts', 'slug': 'alerts', 'name': 'Alerts', 'children': []},
  {
    'id': 'cm1ui',
    'slug': 'ui',
    'name': 'UI',
    'children': [
      {'id': 'cm1uiclicks', 'slug': 'ui-clicks', 'name': 'UI clicks', 'children': []},
    ],
  },
];

const _sounds = [
  {
    'id': 'cm2a1',
    'slug': 'ui-button-3f9a2c1d',
    'title': 'UI Button',
    'author': 'SlimShot',
    'durationMs': 412,
    'category': {'slug': 'ui', 'name': 'UI'},
    'cover': {'url': 'https://cdn.techfamz.com/slimshot/covers/5c0e.png'},
  },
  {
    'id': 'cm2a2',
    'slug': 'chime-ding-91b2e0aa',
    'title': 'Chime Ding',
    'author': 'SlimShot',
    'durationMs': 1830,
    'category': {'slug': 'alerts', 'name': 'Alerts'},
    'cover': null,
  },
];

const _ticket = {
  'url': 'https://cdn.techfamz.com/slimshot/audio/0b6f.mp3',
  'expiresAt': '2026-10-18T12:10:00.000Z',
  'filename': 'ui-button-3f9a2c1d.mp3',
  'format': 'mp3',
  'byteSize': 81234,
  'durationMs': 412,
};

http.Response _ok(Object data, {Map<String, Object?>? meta}) => http.Response(
      jsonEncode({'success': true, 'data': data, 'meta': ?meta}),
      200,
    );

void main() {
  late List<http.BaseRequest> requests;

  CatalogClient clientWith(http.Response Function(http.Request) answer) {
    requests = [];
    return CatalogClient(SlimshotApi(
      baseUrl: 'https://api.test',
      session: signedInSession(access: 'a', refresh: 'r'),
      tokens: MemoryDeviceTokens(),
      client: MockClient((request) async {
        requests.add(request);
        return answer(request);
      }),
    ));
  }

  test('categories asks for kind=audio and the root', () async {
    final client = clientWith((_) => _ok(_categories));
    final pills = await client.categories(kSoundEffectsRoot);
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/app/v1/catalog/categories');
    expect(request.url.queryParameters, {'kind': 'audio', 'root': 'sound-effects'});
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(pills.map((c) => c.slug), ['alerts', 'ui']);
    expect(pills[1].name, 'UI');
    expect(pills[1].children.single.slug, 'ui-clicks');
  });

  test('sounds parses rows and the cursor', () async {
    final client = clientWith((_) => _ok(_sounds, meta: {'nextCursor': 'cm2a2'}));
    final page = await client.sounds('ui');
    expect(requests.single.url.queryParameters,
        {'kind': 'audio', 'category': 'ui', 'limit': '30'});
    expect(page.items.map((s) => s.id), ['cm2a1', 'cm2a2']);
    expect(page.items.first.title, 'UI Button');
    expect(page.items.first.durationMs, 412);
    expect(page.items.first.categorySlug, 'ui');
    expect(page.items.first.coverUrl, 'https://cdn.techfamz.com/slimshot/covers/5c0e.png');
    expect(page.items.last.coverUrl, isNull);
    expect(page.nextCursor, 'cm2a2');

    await client.sounds('ui', cursor: 'cm2a2');
    expect(requests.last.url.queryParameters['cursor'], 'cm2a2');
  });

  test('the last page has no cursor', () async {
    final client = clientWith((_) => _ok(_sounds, meta: {'nextCursor': null}));
    expect((await client.sounds('ui')).nextCursor, isNull);
  });

  test('a row without id or title is dropped', () async {
    final client = clientWith((_) => _ok([
          {'title': 'No id'},
          {'id': 'a', 'title': ''},
          'not a row',
          _sounds.first,
        ]));
    final page = await client.sounds('ui');
    expect(page.items.map((s) => s.id), ['cm2a1']);
  });

  test('download POSTs with no body and parses the ticket', () async {
    final client = clientWith((_) => _ok(_ticket));
    final ticket = await client.download('cm2a1');
    final request = requests.single as http.Request;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/app/v1/catalog/assets/cm2a1/download');
    expect(request.body, isEmpty);
    expect(ticket.url, 'https://cdn.techfamz.com/slimshot/audio/0b6f.mp3');
    expect(ticket.filename, 'ui-button-3f9a2c1d.mp3');
    expect(ticket.format, 'mp3');
    expect(ticket.byteSize, 81234);
    expect(ticket.durationMs, 412);
  });

  test('404 surfaces NOT_FOUND', () async {
    final client = clientWith((_) => http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'NOT_FOUND', 'message': 'm', 'traceId': 't'},
          }),
          404,
        ));
    expect(
      client.sounds('gone'),
      throwsA(isA<SlimshotApiException>().having((e) => e.code, 'code', 'NOT_FOUND')),
    );
  });

  test('retryAfterSeconds reads a rate limit', () {
    expect(
      retryAfterSeconds(const SlimshotApiException('RATE_LIMITED', '', {'retryAfterSeconds': 41})),
      41,
    );
    expect(retryAfterSeconds(const SlimshotApiException('NOT_FOUND')), isNull);
  });
}
