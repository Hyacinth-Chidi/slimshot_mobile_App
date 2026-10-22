import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';

import '../../support/account_fakes.dart';

/// A font item as the server sends it (`app-catalog-api.md` §8.1).
Map<String, Object?> fontRow(
  String id,
  String family, {
  String style = 'Regular',
  int version = 1,
  String? displayName,
  bool preview = true,
}) =>
    {
      'id': id,
      'displayName': displayName ?? (style == 'Regular' ? family : '$family $style'),
      'familyName': family,
      'styleName': style,
      'version': version,
      'format': 'ttf',
      'preview': preview
          ? {'url': 'https://cdn.test/previews/$id-v$version.png', 'width': 480, 'height': 160}
          : null,
    };

/// A stand-in for the server and its CDN, keyed by what was asked:
/// `fonts:<slug>`, `font:<id>`, `family:<name>`, `download:<id>`,
/// `file:<id>`, `preview:<id>`. [gates] hold an answer until completed;
/// [overrides] replace one; [hits] counts every request.
class FakeFontServer {
  FakeFontServer() {
    client = MockClient(_answer);
  }

  Map<String, List<Map<String, Object?>>> lists = {
    'trending': [fontRow('pd', 'Playfair Display'), fontRow('lb', 'Lato', style: 'Bold')],
    'more-fonts': [fontRow('rg', 'Righteous')],
  };

  /// Published fonts in no category: found by id or family, never listed.
  List<Map<String, Object?>> hidden = [];

  final Map<String, int> hits = {};
  final Map<String, Completer<void>> gates = {};
  final Map<String, http.Response Function()> overrides = {};
  late final MockClient client;

  int hitsFor(String key) => hits[key] ?? 0;
  int get totalHits => hits.values.fold(0, (a, b) => a + b);

  Iterable<Map<String, Object?>> get _all => [...lists.values.expand((l) => l), ...hidden];

  Map<String, Object?>? _byId(String id) {
    for (final row in _all) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  static http.Response ok(Object? data) =>
      http.Response(jsonEncode({'success': true, 'data': data}), 200);

  static http.Response error(String code, int status, {Map<String, Object?>? details}) =>
      http.Response(
        jsonEncode({
          'success': false,
          'error': {'code': code, 'message': 'm', 'details': ?details, 'traceId': 't'},
        }),
        status,
      );

  String _key(http.Request request) {
    final path = request.url.path;
    if (request.url.host == 'cdn.test') {
      final name = request.url.pathSegments.last.split('-v').first;
      return path.contains('/previews/') ? 'preview:$name' : 'file:$name';
    }
    if (path.endsWith('/catalog/fonts')) return 'fonts:${request.url.queryParameters['category']}';
    final family = RegExp(r'/catalog/fonts/by-family/(.+)$').firstMatch(path);
    if (family != null) return 'family:${Uri.decodeComponent(family.group(1)!)}';
    final one = RegExp(r'/catalog/fonts/([^/]+)$').firstMatch(path);
    if (one != null) return 'font:${one.group(1)}';
    final download = RegExp(r'/catalog/assets/([^/]+)/download$').firstMatch(path);
    if (download != null) return 'download:${download.group(1)}';
    return 'unknown:$path';
  }

  Future<http.Response> _answer(http.Request request) async {
    final key = _key(request);
    hits[key] = (hits[key] ?? 0) + 1;
    final gate = gates[key];
    if (gate != null) await gate.future;
    final override = overrides[key];
    if (override != null) return override();
    if (key.startsWith('fonts:')) {
      final list = lists[key.substring('fonts:'.length)];
      return list == null ? error('NOT_FOUND', 404) : ok(list);
    }
    if (key.startsWith('font:')) {
      final row = _byId(key.substring('font:'.length));
      return row == null ? error('NOT_FOUND', 404) : ok(row);
    }
    if (key.startsWith('family:')) {
      final name = key.substring('family:'.length);
      for (final row in _all) {
        if (row['familyName'] == name && row['styleName'] == 'Regular') return ok(row);
      }
      return error('NOT_FOUND', 404);
    }
    if (key.startsWith('download:')) {
      final id = key.substring('download:'.length);
      final row = _byId(id);
      if (row == null) return error('NOT_FOUND', 404);
      final version = row['version'];
      return ok({
        'url': 'https://cdn.test/fonts/$id-v$version.ttf',
        'expiresAt': '2026-10-22T12:10:00.000Z',
        'filename': '$id.ttf',
        'format': 'ttf',
        'byteSize': 4,
        'version': version,
      });
    }
    if (key.startsWith('file:')) return http.Response.bytes([0, 1, 0, 0], 200);
    if (key.startsWith('preview:')) return http.Response.bytes([137, 80, 78, 71], 200);
    return error('NOT_FOUND', 404);
  }

  /// The app's server client over this fake.
  SlimshotApi api() => SlimshotApi(
        baseUrl: 'https://api.test',
        session: signedInSession(access: 'a', refresh: 'r'),
        tokens: MemoryDeviceTokens(),
        client: client,
      );
}
