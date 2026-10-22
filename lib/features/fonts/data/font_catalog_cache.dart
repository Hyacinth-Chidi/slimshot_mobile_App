import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'font_models.dart';

/// The two lists the Font tab shows, as the server last sent them.
class SavedFontLists {
  const SavedFontLists({
    required this.trending,
    required this.more,
    required this.fetchedAt,
  });

  final List<ServerFont> trending;
  final List<ServerFont> more;
  final DateTime fetchedAt;
}

/// The lists, kept in `<app support>/font_catalog.json` so the grid opens at
/// once and works offline.
class FontCatalogCache {
  FontCatalogCache({Directory? root}) : _root = root;

  final Directory? _root;
  Future<void> _writes = Future.value();

  Future<File> _file() async {
    final root = _root ?? await getApplicationSupportDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    return File('${root.path}/font_catalog.json');
  }

  /// What was kept, or null — nothing saved, or a file that cannot be read.
  Future<SavedFontLists?> load() async {
    await _writes;
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final fetchedAt = DateTime.tryParse('${json['fetchedAt']}');
      if (fetchedAt == null) return null;
      return SavedFontLists(
        trending: parseServerFonts(json['trending']),
        more: parseServerFonts(json['more']),
        fetchedAt: fetchedAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// Keeps [lists], one write at a time, through a temp file.
  Future<void> save(SavedFontLists lists) {
    final next = _writes.then((_) async {
      final file = await _file();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'fetchedAt': lists.fetchedAt.toUtc().toIso8601String(),
          'trending': [for (final f in lists.trending) f.toJson()],
          'more': [for (final f in lists.more) f.toJson()],
        }),
        flush: true,
      );
      await temp.rename(file.path);
    });
    _writes = next.catchError((_) {});
    return next;
  }
}
