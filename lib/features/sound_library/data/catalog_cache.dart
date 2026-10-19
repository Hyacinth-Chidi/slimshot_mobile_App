import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'catalog_models.dart';

/// What the sheet last saw of the catalogue, so it opens with something to
/// show — offline included — before the server answers.
///
/// The pills and the **first page** of each pill only: later pages are the
/// session's, and the server is asked again on every opening, as its
/// contract asks. Cover addresses ride along; offline their images simply
/// fail and the row draws the app's own cover. In `<app support>`, which no
/// cache clearing sweeps but which is not the user's work either.
class CatalogCache {
  CatalogCache({Directory? root}) : _root = root;

  final Directory? _root;

  List<CatalogCategory> _categories = const [];
  final Map<String, List<CatalogSound>> _pages = {};
  Future<void> _writes = Future.value();

  List<CatalogCategory> get categories => _categories;

  List<CatalogSound> firstPage(String category) => _pages[category] ?? const [];

  Future<File> _file() async {
    final root = _root ?? await getApplicationSupportDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    return File('${root.path}/catalog_cache.json');
  }

  /// Reads what was kept. A file that cannot be read is an empty cache.
  Future<void> load() async {
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

  Future<void> saveFirstPage(String category, List<CatalogSound> sounds) {
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
