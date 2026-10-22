import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'font_models.dart';

/// The fonts the Font tab shows, as the server last listed them.
class SavedFontList {
  const SavedFontList({required this.fonts, required this.fetchedAt});

  final List<ServerFont> fonts;
  final DateTime fetchedAt;
}

/// The list, kept in `<app support>/font_catalog.json` so the grid opens at
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
  Future<SavedFontList?> load() async {
    await _writes;
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final fetchedAt = DateTime.tryParse('${json['fetchedAt']}');
      if (fetchedAt == null) return null;
      return SavedFontList(fonts: parseServerFonts(json['fonts']), fetchedAt: fetchedAt);
    } catch (_) {
      return null;
    }
  }

  /// Keeps [list], one write at a time, through a temp file.
  Future<void> save(SavedFontList list) {
    final next = _writes.then((_) async {
      final file = await _file();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'fetchedAt': list.fetchedAt.toUtc().toIso8601String(),
          'fonts': [for (final f in list.fonts) f.toJson()],
        }),
        flush: true,
      );
      await temp.rename(file.path);
    });
    _writes = next.catchError((_) {});
    return next;
  }
}
