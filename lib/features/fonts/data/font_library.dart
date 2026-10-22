import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'font_models.dart';

/// A font on the phone, usable with no connection.
class LibraryFont {
  const LibraryFont({
    required this.name,
    required this.id,
    required this.displayName,
    required this.familyName,
    required this.styleName,
    required this.version,
    required this.filePath,
  });

  /// The font's name in the app ([fontNameFor]).
  final String name;
  final String id;
  final String displayName;
  final String familyName;
  final String styleName;
  final int version;
  final String filePath;

  /// File *names*, not paths: the documents directory's path can change
  /// between installs of the same backup.
  Map<String, Object?> _toJson() => {
        'name': name,
        'id': id,
        'displayName': displayName,
        'familyName': familyName,
        'styleName': styleName,
        'version': version,
        'fileName': filePath.split(RegExp(r'[/\\]')).last,
      };

  static LibraryFont? _fromJson(Object? json, String folder) {
    if (json is! Map) return null;
    final name = json['name'];
    final id = json['id'];
    final fileName = json['fileName'];
    if (name is! String || id is! String || fileName is! String) return null;
    final family = json['familyName'];
    final style = json['styleName'];
    return LibraryFont(
      name: name,
      id: id,
      displayName: json['displayName'] is String ? json['displayName'] as String : name,
      familyName: family is String ? family : name,
      styleName: style is String ? style : 'Regular',
      version: (json['version'] as num?)?.toInt() ?? 1,
      filePath: '$folder/$fileName',
    );
  }
}

/// A download that did not end in a whole font on the phone.
class FontDownloadFailed implements Exception {
  const FontDownloadFailed(this.message, {this.offline = false});

  final String message;

  /// The connection was the problem, not the file or the server.
  final bool offline;

  @override
  String toString() => 'FontDownloadFailed($message)';
}

/// The fonts downloaded to this phone, under `<documents>/font_library/`.
///
/// Documents, not temp: Clear Cache and the OS sweep temp, and a project's
/// text depends on these. One font serves every project; nothing here deletes
/// one except the file a newer version of the same font replaces.
///
/// A file is written as `<id>.part` and renamed once whole, and the index
/// (`library.json`) is written to a temp file and renamed, so a killed app
/// never leaves something that looks finished and is not — the sound
/// library's rules.
class FontLibrary {
  FontLibrary({http.Client? client, Directory? root})
      : _client = client ?? http.Client(),
        _root = root;

  final http.Client _client;
  final Directory? _root;

  List<LibraryFont>? _entries;
  Future<List<LibraryFont>>? _loading;
  final Map<String, Future<LibraryFont>> _inFlight = {};
  Future<void> _writes = Future.value();

  Future<Directory> _folder() async {
    final root = _root ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/font_library');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Every font on the phone. An entry whose file is gone is dropped; an
  /// index that cannot be read is an empty library.
  Future<List<LibraryFont>> load() {
    final entries = _entries;
    if (entries != null) return Future.value(List.unmodifiable(entries));
    return _loading ??= _readIndex().then((read) {
      _entries = read;
      return List<LibraryFont>.unmodifiable(read);
    });
  }

  /// The font named [name] (case set aside), if [load] found it on the phone.
  LibraryFont? find(String name) {
    final wanted = name.toLowerCase();
    for (final entry in _entries ?? const <LibraryFont>[]) {
      if (entry.name.toLowerCase() == wanted) return entry;
    }
    return null;
  }

  /// Fetches [font] from [ticket] into the library, replacing an older version
  /// of it. A second call for a font already on its way shares the first.
  Future<LibraryFont> download(
    ServerFont font,
    FontDownloadTicket ticket, {
    void Function(double progress)? onProgress,
  }) {
    final existing = _inFlight[font.id];
    if (existing != null) return existing;
    final future = _download(font, ticket, onProgress);
    _inFlight[font.id] = future;
    return future.whenComplete(() => _inFlight.remove(font.id));
  }

  Future<LibraryFont> _download(
    ServerFont font,
    FontDownloadTicket ticket,
    void Function(double progress)? onProgress,
  ) async {
    await load();
    final dir = await _folder();
    final base = _safe(font.id);
    final part = File('${dir.path}/$base.part');
    final file = File('${dir.path}/$base-v${ticket.version}.${_extension(font, ticket)}');
    try {
      final response = await _client.send(http.Request('GET', Uri.parse(ticket.url)));
      if (response.statusCode != HttpStatus.ok) {
        await response.stream.drain<void>();
        throw FontDownloadFailed('HTTP ${response.statusCode}');
      }
      final total = ticket.byteSize > 0 ? ticket.byteSize : (response.contentLength ?? 0);
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }
      if (received == 0) throw const FontDownloadFailed('Empty file.');
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
    } catch (e) {
      if (await part.exists()) await part.delete();
      if (e is FontDownloadFailed) rethrow;
      throw FontDownloadFailed(
        '$e',
        offline: e is SocketException || e is TimeoutException || e is http.ClientException,
      );
    }

    final entry = LibraryFont(
      name: font.name,
      id: font.id,
      displayName: font.displayName,
      familyName: font.familyName,
      styleName: font.styleName,
      version: ticket.version,
      filePath: file.path,
    );
    final replaced = _entries?.where((e) => e.id == font.id && e.filePath != file.path).toList() ??
        const <LibraryFont>[];
    _entries = [entry, ...?_entries?.where((e) => e.id != font.id)];
    try {
      await _writeIndex();
      // Only once the index names the new file: a crash before this leaves
      // the old version usable rather than an index pointing at nothing.
      for (final old in replaced) {
        final stale = File(old.filePath);
        if (await stale.exists()) await stale.delete();
      }
    } on FileSystemException {
      // The font is whole and usable now; only remembering it across a
      // restart failed. The next download writes the index again.
    }
    return entry;
  }

  Future<List<LibraryFont>> _readIndex() async {
    final dir = await _folder();
    final index = File('${dir.path}/library.json');
    if (!await index.exists()) return [];
    try {
      final json = jsonDecode(await index.readAsString());
      final rows = json is Map ? json['fonts'] : null;
      if (rows is! List) return [];
      final entries = <LibraryFont>[];
      for (final row in rows) {
        final entry = LibraryFont._fromJson(row, dir.path);
        if (entry != null && await File(entry.filePath).exists()) entries.add(entry);
      }
      return entries;
    } catch (_) {
      return [];
    }
  }

  /// One write at a time: two downloads finishing together must not race
  /// each other's rename.
  Future<void> _writeIndex() {
    final next = _writes.then((_) async {
      final dir = await _folder();
      final temp = File('${dir.path}/library.json.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'fonts': [for (final e in _entries ?? const <LibraryFont>[]) e._toJson()],
        }),
        flush: true,
      );
      for (var attempt = 0;; attempt++) {
        try {
          await temp.rename('${dir.path}/library.json');
          return;
        } on FileSystemException {
          if (attempt >= 2) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }
    });
    _writes = next.catchError((_) {});
    return next;
  }

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String _extension(ServerFont font, FontDownloadTicket ticket) {
    for (final candidate in [ticket.format, font.format]) {
      final safe = _safe(candidate.toLowerCase());
      if (safe == 'ttf' || safe == 'otf') return safe;
    }
    return 'ttf';
  }
}
