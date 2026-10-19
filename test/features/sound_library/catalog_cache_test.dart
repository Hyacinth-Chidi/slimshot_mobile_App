import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/sound_library/data/catalog_cache.dart';
import 'package:slimshotai/features/sound_library/data/catalog_models.dart';

import 'support.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('catalog_cache_test'));
  tearDown(() => deleteTemp(root));

  test('round-trips categories and first pages', () async {
    final cache = CatalogCache(root: root);
    await cache.load();
    await cache.saveCategories(const [
      CatalogCategory(id: '1', slug: 'impacts', name: 'Impacts'),
      CatalogCategory(
        id: '2',
        slug: 'ui',
        name: 'UI',
        children: [CatalogCategory(id: '3', slug: 'ui-clicks', name: 'UI clicks')],
      ),
    ]);
    await cache.savePage('impacts', const [
      CatalogSound(id: 'a', title: 'Punch', durationMs: 300, coverUrl: 'https://c/a.png'),
      CatalogSound(id: 'b', title: 'Crash'),
    ]);

    final reopened = CatalogCache(root: root);
    await reopened.load();
    expect(reopened.categories.map((c) => c.slug), ['impacts', 'ui']);
    expect(reopened.categories[1].children.single.slug, 'ui-clicks');
    expect(reopened.page('impacts').map((s) => s.title), ['Punch', 'Crash']);
    expect(reopened.page('impacts').first.coverUrl, 'https://c/a.png');
    expect(reopened.page('impacts').first.durationMs, 300);
  });

  test('an unknown category has no page', () async {
    final cache = CatalogCache(root: root);
    await cache.load();
    expect(cache.page('nope'), isEmpty);
    expect(cache.categories, isEmpty);
  });

  test('a corrupt file reads as empty', () async {
    File('${root.path}/catalog_cache.json').writeAsStringSync('[[[');
    final cache = CatalogCache(root: root);
    await cache.load();
    expect(cache.categories, isEmpty);
    expect(cache.page('impacts'), isEmpty);
    // And it can be written again after.
    await cache.saveCategories(const [CatalogCategory(id: '1', slug: 'x', name: 'X')]);
    final reopened = CatalogCache(root: root);
    await reopened.load();
    expect(reopened.categories.single.slug, 'x');
  });
}
