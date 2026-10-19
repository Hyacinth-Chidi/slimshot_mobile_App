/// What the server's sound catalogue sends, as the app reads it.
///
/// Contract: `slimshot_server/docs/app-catalog-api.md`. Every reader is
/// defensive — a field the server leaves out reads as its empty value, and a
/// row the app cannot show (no id or no title) is dropped, never thrown on.
library;

/// The one category name the app knows: the top-level audio category whose
/// children are the sheet's pills. Everything under it is the dashboard's.
const String kSoundEffectsRoot = 'sound-effects';

/// The music library's root, beside the sound effects': the same sheet and
/// endpoints, pointed here.
const String kMusicRoot = 'music';

String? _string(Object? value) => value is String ? value : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

/// A pill, and the categories under it.
class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.slug,
    required this.name,
    this.children = const [],
  });

  final String id;
  final String slug;
  final String name;
  final List<CatalogCategory> children;

  static CatalogCategory? tryParse(Object? json) {
    if (json is! Map) return null;
    final slug = _string(json['slug']);
    if (slug == null || slug.isEmpty) return null;
    final children = json['children'];
    return CatalogCategory(
      id: _string(json['id']) ?? slug,
      slug: slug,
      name: _string(json['name']) ?? slug,
      children: children is List ? parseCategories(children) : const [],
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'slug': slug,
        'name': name,
        'children': [for (final c in children) c.toJson()],
      };
}

List<CatalogCategory> parseCategories(Object? json) => [
      if (json is List)
        for (final row in json) ?CatalogCategory.tryParse(row),
    ];

/// One sound in a list. The file's address is never here: it is asked for at
/// download time (`DownloadTicket`).
class CatalogSound {
  const CatalogSound({
    required this.id,
    required this.title,
    this.durationMs = 0,
    this.categorySlug,
    this.categoryName,
    this.coverUrl,
  });

  final String id;
  final String title;

  /// 0 when the server does not know.
  final int durationMs;
  final String? categorySlug;
  final String? categoryName;

  /// Null when the sound has no cover: the app draws its own.
  final String? coverUrl;

  /// Reads both the server's row (`category` and `cover` objects) and this
  /// class's own [toJson] (flat fields).
  static CatalogSound? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = _string(json['id']);
    final title = _string(json['title']);
    if (id == null || id.isEmpty || title == null || title.isEmpty) return null;
    final category = json['category'];
    final cover = json['cover'];
    return CatalogSound(
      id: id,
      title: title,
      durationMs: _int(json['durationMs']),
      categorySlug: category is Map
          ? _string(category['slug'])
          : _string(json['categorySlug']),
      categoryName: category is Map
          ? _string(category['name'])
          : _string(json['categoryName']),
      coverUrl: cover is Map ? _string(cover['url']) : _string(json['coverUrl']),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'durationMs': durationMs,
        'categorySlug': ?categorySlug,
        'categoryName': ?categoryName,
        'coverUrl': ?coverUrl,
      };
}

List<CatalogSound> parseSounds(Object? json) => [
      if (json is List)
        for (final row in json) ?CatalogSound.tryParse(row),
    ];

/// One page of a list; [nextCursor] null at the end.
class CatalogPage {
  const CatalogPage(this.items, this.nextCursor);

  final List<CatalogSound> items;
  final String? nextCursor;
}

/// Where to fetch a sound right now. Never stored: the address is only
/// promised until it expires, and each ask counts as a download.
class DownloadTicket {
  const DownloadTicket({
    required this.url,
    required this.filename,
    required this.format,
    required this.byteSize,
    required this.durationMs,
  });

  final String url;
  final String filename;
  final String format;
  final int byteSize;
  final int durationMs;

  static DownloadTicket? tryParse(Object? json) {
    if (json is! Map) return null;
    final url = _string(json['url']);
    if (url == null || url.isEmpty) return null;
    return DownloadTicket(
      url: url,
      filename: _string(json['filename']) ?? '',
      format: _string(json['format']) ?? '',
      byteSize: _int(json['byteSize']),
      durationMs: _int(json['durationMs']),
    );
  }
}

/// A sound's length as a row shows it: tenths of a second under ten seconds
/// (`0.8s` — `0:00` would say nothing about a click), `m:ss` from there. A
/// value that rounds to ten seconds takes the long form, never `10.0s`.
/// Null when the length is unknown.
String? formatSoundDuration(int durationMs) {
  if (durationMs <= 0) return null;
  final tenths = (durationMs / 100).round();
  if (tenths < 100) return '${tenths ~/ 10}.${tenths % 10}s';
  final seconds = (durationMs / 1000).round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
