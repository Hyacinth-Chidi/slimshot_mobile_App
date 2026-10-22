import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/features/fonts/data/font_preview_cache.dart';

import 'support.dart';

void main() {
  late Directory root;
  late FakeFontServer server;

  setUp(() {
    root = Directory.systemTemp.createTempSync('font_preview_cache_test');
    server = FakeFontServer();
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  const url = 'https://cdn.test/previews/pd-v1.png';

  test('a preview is fetched once and then read from disk', () async {
    final cache = FontPreviewCache(client: server.client, root: root);
    expect(cache.fileFor(url), isNull);
    final first = await cache.fetch(url);
    final second = await cache.fetch(url);
    expect(first!.existsSync(), isTrue);
    expect(second!.path, first.path);
    expect(server.hitsFor('preview:pd'), 1);
    expect(cache.fileFor(url)!.path, first.path);
    expect(FontPreviewCache(client: server.client, root: root).fileFor(url)!.path, first.path);
  });

  test('two previews keep two files', () async {
    final cache = FontPreviewCache(client: server.client, root: root);
    await cache.fetchAll([url, 'https://cdn.test/previews/rg-v1.png']);
    expect(cache.fileFor(url), isNotNull);
    expect(cache.fileFor('https://cdn.test/previews/rg-v1.png'), isNotNull);
    expect(cache.fileFor(url)!.path, isNot(cache.fileFor('https://cdn.test/previews/rg-v1.png')!.path));
  });

  test('a preview that fails to fetch answers null, never throws', () async {
    final cache = FontPreviewCache(
      client: MockClient((_) async => throw http.ClientException('no route')),
      root: root,
    );
    expect(await cache.fetch(url), isNull);
    expect(cache.fileFor(url), isNull);
    server.overrides['preview:pd'] = () => http.Response('gone', 404);
    expect(await FontPreviewCache(client: server.client, root: root).fetch(url), isNull);
  });
}
