import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// The fonts' preview images, kept in `<app support>/font_previews/` so an
/// offline grid still shows every typeface it has seen.
///
/// Keyed by URL: the server gives a changed preview a new URL, so a file here
/// never goes stale. A failed fetch is a missing preview — the tile shows the
/// font's name instead — never an error.
class FontPreviewCache {
  FontPreviewCache({http.Client? client, Directory? root})
      : _client = client ?? http.Client(),
        _dir = root == null ? null : Directory('${root.path}/font_previews');

  final http.Client _client;
  Directory? _dir;
  final Set<String> _known = {};
  final Map<String, Future<File?>> _inFlight = {};

  /// Finds the folder, so [fileFor] can answer for previews a previous run
  /// kept. Without a root given, nothing is found before this has run.
  Future<void> prepare() async {
    if (_dir != null) return;
    final support = await getApplicationSupportDirectory();
    _dir = Directory('${support.path}/font_previews');
  }

  /// The preview for [url] if it is on disk; never fetches.
  File? fileFor(String url) {
    final dir = _dir;
    if (dir == null) return null;
    final file = File('${dir.path}/${_fileName(url)}');
    if (_known.contains(url)) return file;
    if (file.existsSync()) {
      _known.add(url);
      return file;
    }
    return null;
  }

  /// The preview for [url], fetched once.
  Future<File?> fetch(String url) {
    final existing = fileFor(url);
    if (existing != null) return Future.value(existing);
    // A block body: an arrow would hand `whenComplete` the removed future —
    // this very one — and it would wait on itself for ever.
    return _inFlight[url] ??= _fetch(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  /// Fetches every preview not on disk yet, four at a time.
  Future<void> fetchAll(Iterable<String> urls) async {
    final queue = [for (final url in urls.toSet()) if (fileFor(url) == null) url];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        await fetch(queue.removeLast());
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
  }

  Future<File?> _fetch(String url) async {
    try {
      await prepare();
      final dir = _dir!;
      if (!await dir.exists()) await dir.create(recursive: true);
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode != HttpStatus.ok || response.bodyBytes.isEmpty) return null;
      final file = File('${dir.path}/${_fileName(url)}');
      final temp = File('${file.path}.part');
      await temp.writeAsBytes(response.bodyBytes, flush: true);
      await temp.rename(file.path);
      _known.add(url);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// A file name from the URL: FNV-1a over its bytes, 64 bits in hex.
  static String _fileName(String url) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(url)) {
      hash ^= byte;
      hash *= 0x100000001b3;
    }
    return '${hash.toUnsigned(64).toRadixString(16)}.png';
  }
}
