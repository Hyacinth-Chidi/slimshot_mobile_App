import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/sound_library/data/catalog_cache.dart';
import 'package:slimshotai/features/sound_library/data/catalog_models.dart';

import 'support.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('catalog_cache_test'));
  tearDown(() => deleteTemp(root));

  test('a load waits for a save still being written', () async {
    // Reopening the sheet re-reads the cache from disk. Read while a save is
    // in flight, it brought back the older rows — and the pending save then
    // wrote those older rows back over the newer ones.
    final cache = CatalogCache(root: root);
    await cache.load();
    await cache.savePage('impacts', const [CatalogSound(id: 'a', title: 'A')]);
    final saving = cache.savePage('impacts', const [
      CatalogSound(id: 'a', title: 'A'),
      CatalogSound(id: 'b', title: 'B'),
    ]);
    await cache.load();
    expect(cache.page('impacts').map((s) => s.id), ['a', 'b']);
    await saving;
    final reopened = CatalogCache(root: root);
    await reopened.load();
    expect(reopened.page('impacts').map((s) => s.id), ['a', 'b']);
  });

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

  test('each library keeps its own cache', () async {
    final effects = CatalogCache(root: root, library: kSoundEffectsRoot);
    final music = CatalogCache(root: root, library: kMusicRoot);
    await effects.saveCategories(const [CatalogCategory(id: '1', slug: 'impacts', name: 'Impacts')]);
    await music.saveCategories(const [CatalogCategory(id: '2', slug: 'cinematic', name: 'Cinematic')]);
    final effectsAgain = CatalogCache(root: root, library: kSoundEffectsRoot);
    final musicAgain = CatalogCache(root: root, library: kMusicRoot);
    await effectsAgain.load();
    await musicAgain.load();
    expect(effectsAgain.categories.single.slug, 'impacts');
    expect(musicAgain.categories.single.slug, 'cinematic');
  });
}
