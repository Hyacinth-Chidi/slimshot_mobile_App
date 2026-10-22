import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/fonts/data/font_catalog_cache.dart';
import 'package:slimshotai/features/fonts/data/font_models.dart';

import 'support.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('font_catalog_cache_test'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  final fetched = DateTime.utc(2026, 10, 22, 12);
  SavedFontLists lists() => SavedFontLists(
        trending: parseServerFonts([fontRow('pd', 'Playfair Display'), fontRow('lb', 'Lato', style: 'Bold')]),
        more: parseServerFonts([fontRow('rg', 'Righteous')]),
        fetchedAt: fetched,
      );

  test('saved lists round-trip with their time', () async {
    await FontCatalogCache(root: root).save(lists());
    final read = await FontCatalogCache(root: root).load();
    expect(read!.trending.map((f) => f.name), ['Playfair Display', 'Lato Bold']);
    expect(read.more.single.name, 'Righteous');
    expect(read.fetchedAt, fetched);
    expect(read.trending.first.previewUrl, 'https://cdn.test/previews/pd-v1.png');
  });

  test('a corrupt file reads as nothing saved', () async {
    File('${root.path}/font_catalog.json').writeAsStringSync('{not json');
    expect(await FontCatalogCache(root: root).load(), isNull);
  });

  test('nothing saved reads as nothing', () async {
    expect(await FontCatalogCache(root: root).load(), isNull);
  });

  test('stale after five minutes', () {
    final saved = lists();
    expect(isStale(saved, fetched.add(const Duration(minutes: 4, seconds: 59))), isFalse);
    expect(isStale(saved, fetched.add(const Duration(minutes: 5, seconds: 1))), isTrue);
  });
}
