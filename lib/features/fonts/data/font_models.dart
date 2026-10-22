/// The server's font catalogue, as the app reads it
/// (`slimshot_server/docs/app-catalog-api.md` §8).
library;

/// A font's name in the app: its family for a Regular face, otherwise the
/// family and the style ("Lato Bold").
///
/// It is what a text stores in `fontFamily` and what the font is registered
/// under with the text engine. The server keeps (family, style) unique and
/// never edits either — both are read from the file — so the name is as
/// stable as the id, and templates that name "Playfair Display" find it.
String fontNameFor(String familyName, String styleName) {
  final family = familyName.trim();
  final style = styleName.trim();
  if (style.isEmpty || style.toLowerCase() == 'regular') return family;
  return '$family $style';
}

/// One font face on the server.
class ServerFont {
  const ServerFont({
    required this.id,
    required this.displayName,
    required this.familyName,
    required this.styleName,
    required this.version,
    required this.format,
    this.previewUrl,
  });

  final String id;

  /// The tile's label and what search matches. The owner can rename it.
  final String displayName;
  final String familyName;
  final String styleName;

  /// Goes up each time the owner uploads a fixed file for this font.
  final int version;

  /// `ttf` or `otf`.
  final String format;

  /// The name drawn in the font, white on transparent, 480×160.
  final String? previewUrl;

  /// The font's name in the app (see [fontNameFor]).
  String get name => fontNameFor(familyName, styleName);

  static ServerFont? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = _string(json['id']);
    final family = _string(json['familyName']);
    if (id == null || id.isEmpty || family == null || family.isEmpty) return null;
    final style = _string(json['styleName']) ?? 'Regular';
    final preview = json['preview'];
    return ServerFont(
      id: id,
      displayName: _string(json['displayName']) ?? fontNameFor(family, style),
      familyName: family,
      styleName: style,
      version: _int(json['version'], fallback: 1),
      format: _string(json['format']) ?? 'ttf',
      previewUrl: preview is Map ? _string(preview['url']) : null,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'familyName': familyName,
        'styleName': styleName,
        'version': version,
        'format': format,
        'preview': previewUrl == null ? null : {'url': previewUrl},
      };
}

/// A list of fonts as the server sent it; a row that does not parse is left
/// out rather than failing the list.
List<ServerFont> parseServerFonts(Object? data) {
  if (data is! List) return const [];
  return [
    for (final row in data)
      if (ServerFont.tryParse(row) case final font?) font,
  ];
}

/// Where to fetch a font now (`POST /assets/:id/download`). The [url] is good
/// for ten minutes and is never stored.
class FontDownloadTicket {
  const FontDownloadTicket({
    required this.url,
    required this.filename,
    required this.format,
    required this.byteSize,
    required this.version,
  });

  final String url;
  final String filename;
  final String format;
  final int byteSize;

  /// The version of the file at [url] — always the current one.
  final int version;

  static FontDownloadTicket? tryParse(Object? json) {
    if (json is! Map) return null;
    final url = _string(json['url']);
    if (url == null || url.isEmpty) return null;
    return FontDownloadTicket(
      url: url,
      filename: _string(json['filename']) ?? '',
      format: _string(json['format']) ?? '',
      byteSize: _int(json['byteSize']),
      version: _int(json['version'], fallback: 1),
    );
  }
}

String? _string(Object? value) => value is String ? value : null;

int _int(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;
