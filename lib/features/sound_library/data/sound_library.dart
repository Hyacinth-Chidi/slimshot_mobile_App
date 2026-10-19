import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'catalog_models.dart';

/// A sound on the phone: playable and usable on the timeline with no
/// connection.
class LibrarySound {
  const LibrarySound({
    required this.id,
    required this.title,
    required this.filePath,
    required this.durationMs,
    required this.downloadedAt,
    this.categorySlug,
    this.categoryName,
    this.coverPath,
    this.library = kSoundEffectsRoot,
  });

  final String id;
  final String title;
  final String filePath;

  /// 0 when neither the server nor the file has said.
  final int durationMs;
  final DateTime downloadedAt;
  final String? categorySlug;
  final String? categoryName;
  final String? coverPath;

  /// Which library the sound came from — `sound-effects` or `music` — so
  /// each sheet's Downloaded shows its own. An entry saved before there were
  /// two is a sound effect.
  final String library;

  LibrarySound withDuration(int durationMs) => LibrarySound(
        id: id,
        title: title,
        filePath: filePath,
        durationMs: durationMs,
        downloadedAt: downloadedAt,
        categorySlug: categorySlug,
        categoryName: categoryName,
        coverPath: coverPath,
        library: library,
      );

  /// As a row: the Downloaded pill lists library sounds like any others.
  CatalogSound get asCatalogSound => CatalogSound(
        id: id,
        title: title,
        durationMs: durationMs,
        categorySlug: categorySlug,
        categoryName: categoryName,
      );

  /// File *names*, not paths: the documents directory's path can change
  /// between installs of the same backup.
  Map<String, Object?> _toJson() => {
        'id': id,
        'title': title,
        'fileName': _name(filePath),
        'durationMs': durationMs,
        'downloadedAt': downloadedAt.toIso8601String(),
        'categorySlug': ?categorySlug,
        'categoryName': ?categoryName,
        'library': library,
        if (coverPath != null) 'coverFileName': _name(coverPath!),
      };

  static LibrarySound? _fromJson(Object? json, String folder) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final fileName = json['fileName'];
    if (id is! String || title is! String || fileName is! String) return null;
    final cover = json['coverFileName'];
    final category = json['categorySlug'];
    final categoryName = json['categoryName'];
    return LibrarySound(
      id: id,
      title: title,
      filePath: '$folder/$fileName',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      downloadedAt:
          DateTime.tryParse('${json['downloadedAt']}') ?? DateTime(2000),
      categorySlug: category is String ? category : null,
      categoryName: categoryName is String ? categoryName : null,
      coverPath: cover is String ? '$folder/$cover' : null,
      library: json['library'] is String ? json['library'] as String : kSoundEffectsRoot,
    );
  }

  static String _name(String path) => path.split(RegExp(r'[/\\]')).last;
}

/// A download that did not end in a whole file on the phone.
class SoundDownloadFailed implements Exception {
  const SoundDownloadFailed(this.message, {this.offline = false});

  final String message;

  /// The connection was the problem, not the file or the server.
  final bool offline;

  @override
  String toString() => 'SoundDownloadFailed($message)';
}

/// The sounds downloaded to this phone, under `<documents>/sound_library/`.
///
/// Documents, not temp: Clear Cache and the OS sweep temp, and these are
/// used by drafts. Not under `drafts/<id>/` either, since one sound serves
/// every draft and deleting a draft must not take it. Nothing here deletes a
/// sound, so a draft can never point at a file the app removed.
///
/// A file is written as `<id>.part` and renamed once whole, and the index
/// (`library.json`) is written to a temp file and renamed, so a killed app
/// never leaves something that looks finished and is not.
class SoundLibrary {
  SoundLibrary({http.Client? client, Directory? root})
      : _client = client ?? http.Client(),
        _root = root;

  final http.Client _client;
  final Directory? _root;

  List<LibrarySound>? _entries;
  Future<List<LibrarySound>>? _loading;
  final Map<String, Future<LibrarySound>> _inFlight = {};
  Future<void> _writes = Future.value();

  Future<Directory> _folder() async {
    final root = _root ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/sound_library');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Every sound on the phone, newest first. An entry whose file is gone is
  /// dropped; an index that cannot be read is an empty library.
  Future<List<LibrarySound>> load() {
    final entries = _entries;
    if (entries != null) return Future.value(List.unmodifiable(entries));
    return _loading ??= _readIndex().then((read) {
      _entries = read;
      return List<LibrarySound>.unmodifiable(read);
    });
  }

  /// The sound, if it is on the phone. Answers from what [load] read.
  LibrarySound? find(String id) {
    for (final entry in _entries ?? const <LibrarySound>[]) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Fetches [sound] from [ticket] into the library. A second call for a
  /// sound already on its way shares the first one's download.
  Future<LibrarySound> download(
    CatalogSound sound,
    DownloadTicket ticket, {
    void Function(double progress)? onProgress,
    String library = kSoundEffectsRoot,
  }) {
    final existing = _inFlight[sound.id];
    if (existing != null) return existing;
    final future = _download(sound, ticket, onProgress, library);
    _inFlight[sound.id] = future;
    return future.whenComplete(() => _inFlight.remove(sound.id));
  }

  Future<LibrarySound> _download(
    CatalogSound sound,
    DownloadTicket ticket,
    void Function(double progress)? onProgress,
    String library,
  ) async {
    await load();
    final dir = await _folder();
    final base = _safe(sound.id);
    final part = File('${dir.path}/$base.part');
    final file = File('${dir.path}/$base.${_extension(ticket)}');
    try {
      final response = await _client.send(http.Request('GET', Uri.parse(ticket.url)));
      if (response.statusCode != HttpStatus.ok) {
        await response.stream.drain<void>();
        throw SoundDownloadFailed('HTTP ${response.statusCode}');
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
      if (received == 0) throw const SoundDownloadFailed('Empty file.');
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
    } catch (e) {
      if (await part.exists()) await part.delete();
      if (e is SoundDownloadFailed) rethrow;
      throw SoundDownloadFailed(
        '$e',
        offline: e is SocketException ||
            e is TimeoutException ||
            e is http.ClientException,
      );
    }

    final entry = LibrarySound(
      id: sound.id,
      title: sound.title,
      filePath: file.path,
      durationMs: sound.durationMs > 0 ? sound.durationMs : ticket.durationMs,
      downloadedAt: DateTime.now(),
      categorySlug: sound.categorySlug,
      categoryName: sound.categoryName,
      coverPath: await _fetchCover(sound, dir, base),
      library: library,
    );
    _entries = [entry, ...?_entries?.where((e) => e.id != entry.id)];
    await _writeIndex();
    return entry;
  }

  /// The cover beside the sound, or null. Failing here is not failing the
  /// download: the row draws the app's own cover.
  Future<String?> _fetchCover(CatalogSound sound, Directory dir, String base) async {
    final url = sound.coverUrl;
    if (url == null) return null;
    final cover = File('${dir.path}/$base.cover');
    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode != HttpStatus.ok || response.bodyBytes.isEmpty) {
        return null;
      }
      await cover.writeAsBytes(response.bodyBytes, flush: true);
      return cover.path;
    } catch (_) {
      return null;
    }
  }

  Future<List<LibrarySound>> _readIndex() async {
    final dir = await _folder();
    final index = File('${dir.path}/library.json');
    if (!await index.exists()) return [];
    try {
      final json = jsonDecode(await index.readAsString());
      final rows = json is Map ? json['sounds'] : null;
      if (rows is! List) return [];
      final entries = <LibrarySound>[];
      for (final row in rows) {
        final entry = LibrarySound._fromJson(row, dir.path);
        if (entry != null && await File(entry.filePath).exists()) {
          entries.add(entry);
        }
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
          'sounds': [for (final e in _entries ?? const <LibrarySound>[]) e._toJson()],
        }),
        flush: true,
      );
      await temp.rename('${dir.path}/library.json');
    });
    _writes = next.catchError((_) {});
    return next;
  }

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String _extension(DownloadTicket ticket) {
    final format = _safe(ticket.format);
    if (format.isNotEmpty) return format;
    final dot = ticket.filename.lastIndexOf('.');
    if (dot >= 0 && dot < ticket.filename.length - 1) {
      return _safe(ticket.filename.substring(dot + 1));
    }
    return 'audio';
  }
}
