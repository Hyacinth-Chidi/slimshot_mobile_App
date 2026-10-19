import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/sound_library/data/catalog_cache.dart';
import 'package:slimshotai/features/sound_library/data/catalog_client.dart';
import 'package:slimshotai/features/sound_library/data/sound_library.dart';
import 'package:slimshotai/features/sound_library/sound_effects_controller.dart';

import '../../support/account_fakes.dart';

Map<String, Object?> soundRow(String id, {int durationMs = 800, String? cover}) => {
      'id': id,
      'slug': '$id-slug',
      'title': 'Sound $id',
      'durationMs': durationMs,
      'category': {'slug': 'impacts', 'name': 'Impacts'},
      'cover': cover == null ? null : {'url': cover},
    };

/// A stand-in for the server and its CDN, keyed by what was asked:
/// `categories`, `assets:<category>:<cursor or ->`, `download:<id>`,
/// `file:<id>`. [gates] hold an answer until completed; [overrides] replace
/// one; [hits] counts every request.
class FakeCatalogServer {
  FakeCatalogServer() {
    client = MockClient(_answer);
  }

  List<Map<String, Object?>> categories = [
    {'id': '1', 'slug': 'impacts', 'name': 'Impacts', 'children': []},
    {'id': '2', 'slug': 'funny-memes', 'name': 'Funny & Memes', 'children': []},
  ];

  /// Each category's pages; a page's cursor is its index.
  Map<String, List<List<Map<String, Object?>>>> pages = {
    'impacts': [
      [soundRow('a'), soundRow('b')],
    ],
    'funny-memes': [
      [soundRow('m')],
    ],
  };

  final Map<String, int> hits = {};
  final Map<String, Completer<void>> gates = {};
  final Map<String, http.Response Function()> overrides = {};
  late final MockClient client;

  int hitsFor(String key) => hits[key] ?? 0;

  static http.Response ok(Object? data, {Map<String, Object?>? meta}) =>
      http.Response(jsonEncode({'success': true, 'data': data, 'meta': ?meta}), 200);

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
      return 'file:${request.url.pathSegments.last.split('.').first}';
    }
    if (path.endsWith('/catalog/categories')) return 'categories';
    if (path.endsWith('/catalog/assets')) {
      final q = request.url.queryParameters;
      return 'assets:${q['category']}:${q['cursor'] ?? '-'}';
    }
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
    if (key == 'categories') return ok(categories);
    if (key.startsWith('assets:')) {
      final parts = key.split(':');
      final list = pages[parts[1]];
      if (list == null) return error('NOT_FOUND', 404);
      final index = parts[2] == '-' ? 0 : int.parse(parts[2]);
      return ok(list[index], meta: {'nextCursor': index + 1 < list.length ? '${index + 1}' : null});
    }
    if (key.startsWith('download:')) {
      final id = key.substring('download:'.length);
      return ok({
        'url': 'https://cdn.test/audio/$id.mp3',
        'filename': '$id.mp3',
        'format': 'mp3',
        'byteSize': 3,
        'durationMs': 800,
      });
    }
    if (key.startsWith('file:')) return http.Response.bytes([1, 2, 3], 200);
    return error('NOT_FOUND', 404);
  }
}

/// Records what the sheet asked the speaker to do.
class FakePreviewPlayer implements SoundPreviewPlayer {
  final List<String> played = [];
  int stops = 0;
  bool disposed = false;
  double? duration = 0.8;

  @override
  Future<void> play(String path) async => played.add(path);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<double?> durationOf(String path) async => duration;

  @override
  Future<void> dispose() async => disposed = true;
}

/// A controller over [server], with its library and cache in [root].
class ControllerHarness {
  ControllerHarness(this.root, {FakeCatalogServer? server})
      : server = server ?? FakeCatalogServer() {
    library = SoundLibrary(client: this.server.client, root: root);
    cache = CatalogCache(root: root);
  }

  final Directory root;
  final FakeCatalogServer server;
  final FakePreviewPlayer player = FakePreviewPlayer();
  late final SoundLibrary library;
  late final CatalogCache cache;
  DateTime clock = DateTime(2026, 10, 19, 12);
  final List<Duration> waits = [];

  SoundEffectsController build() => SoundEffectsController(
        client: CatalogClient(SlimshotApi(
          baseUrl: 'https://api.test',
          session: signedInSession(access: 'a', refresh: 'r'),
          tokens: MemoryDeviceTokens(),
          client: server.client,
        )),
        library: library,
        cache: cache,
        player: player,
        now: () => clock,
        wait: (d) async => waits.add(d),
      );
}

/// Lets queued futures and file I/O run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
}
