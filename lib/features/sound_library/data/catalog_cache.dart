import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'catalog_models.dart';

/// What the sheet last saw of the catalogue, so it opens with something to
/// show — offline included — before the server answers.
///
/// The pills and, for each pill, every row it last loaded — the first page
/// and any it scrolled on to — so offline the sheet shows what was last
/// seen. The server is still asked again on every opening, as its contract
/// asks. Cover addresses ride along; offline their images simply
/// fail and the row draws the app's own cover. In `<app support>`, which no
/// cache clearing sweeps but which is not the user's work either.
///
/// One per library: the sound effects and the music each keep their own file
/// (`catalog_cache_<library>.json`), or one would overwrite the other's pills.
class CatalogCache {
  CatalogCache({Directory? root, this.library = kSoundEffectsRoot}) : _root = root;

  final Directory? _root;

  /// The root this cache keeps: `sound-effects` or `music`.
  final String library;

  List<CatalogCategory> _categories = const [];
  final Map<String, List<CatalogSound>> _pages = {};
  Future<void> _writes = Future.value();

  List<CatalogCategory> get categories => _categories;

  /// The rows [category] last loaded.
  List<CatalogSound> page(String category) => _pages[category] ?? const [];

  Future<File> _file() async {
    final root = _root ?? await getApplicationSupportDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    return File('${root.path}/catalog_cache_$library.json');
  }

  /// Reads what was kept. A file that cannot be read is an empty cache.
  Future<void> load() async {
    // A save still being written goes first: read before it lands, the file
    // held the older rows, they replaced the newer ones in memory, and the
    // pending save then wrote the older rows back.
    await _writes;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      _categories = parseCategories(json['categories']);
      final pages = json['pages'];
      if (pages is Map) {
        _pages
          ..clear()
          ..addAll({
            for (final entry in pages.entries)
              if (entry.key is String) entry.key as String: parseSounds(entry.value),
          });
      }
    } catch (_) {
      _categories = const [];
      _pages.clear();
    }
  }

  Future<void> saveCategories(List<CatalogCategory> categories) {
    _categories = List.unmodifiable(categories);
    return _write();
  }

  Future<void> savePage(String category, List<CatalogSound> sounds) {
    _pages[category] = List.unmodifiable(sounds);
    return _write();
  }

  Future<void> _write() {
    final next = _writes.then((_) async {
      final file = await _file();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'categories': [for (final c in _categories) c.toJson()],
          'pages': {
            for (final entry in _pages.entries)
              entry.key: [for (final s in entry.value) s.toJson()],
          },
        }),
        flush: true,
      );
      await temp.rename(file.path);
    });
    _writes = next.catchError((_) {});
    return next;
  }
}
