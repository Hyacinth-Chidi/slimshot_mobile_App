import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/services/slimshot_api.dart';
import 'data/font_catalog_cache.dart';
import 'data/font_client.dart';
import 'data/font_library.dart';
import 'data/font_models.dart';
import 'font_registry.dart';

/// What making a font available came to.
enum FontAvailability {
  /// Text in it draws in its own font now.
  available,

  /// The connection was the problem; trying again online may work.
  offline,

  /// Anything else: the server has no such font, refused, or the file
  /// would not register.
  failed,
}

/// Makes a font, named as texts name it, drawable: registered if it is on
/// the phone, otherwise found on the server, downloaded and registered.
///
/// Found in this order: the saved lists (by name), then the server's family
/// lookup — accepted only when the face it answers has the same name, since
/// that lookup returns a family's Regular face and "Lato Bold" is not
/// "Lato". Every download asks for a fresh address (one is good for ten
/// minutes and never stored). Nothing here throws.
class FontService {
  FontService({
    required FontClient client,
    required FontLibrary library,
    required FontCatalogCache cache,
    FontRegistry? registry,
  })  : _client = client,
        _library = library,
        _cache = cache,
        _registry = registry ?? FontRegistry.instance;

  final FontClient _client;
  final FontLibrary _library;
  final FontCatalogCache _cache;
  final FontRegistry _registry;
  final Map<String, Future<FontAvailability>> _inFlight = {};

  /// Makes [name] drawable. Calls for one name while it is on its way share
  /// it; [onProgress] hears the download of the call that started it.
  Future<FontAvailability> ensureAvailable(
    String name, {
    void Function(double progress)? onProgress,
  }) {
    if (_registry.isAvailable(name)) return Future.value(FontAvailability.available);
    return _inFlight[name] ??= _ensure(name, onProgress).whenComplete(() {
      _inFlight.remove(name);
    });
  }

  Future<FontAvailability> _ensure(
    String name,
    void Function(double progress)? onProgress,
  ) async {
    try {
      await _library.load();
      final onPhone = _library.find(name);
      if (onPhone != null) {
        final registered = await _register(name, onPhone.filePath);
        // A file the engine refuses is fetched again rather than kept as
        // the font for good; a good one is never fetched twice.
        if (registered == FontAvailability.available) return registered;
      }

      final font = await _resolve(name);
      if (font == null) return FontAvailability.failed;
      final ticket = await _client.download(font.id);
      final entry = await _library.download(font, ticket, onProgress: onProgress);
      return await _register(name, entry.filePath);
    } catch (e) {
      return _isOffline(e) ? FontAvailability.offline : FontAvailability.failed;
    }
  }

  /// The server font named [name]: from the saved lists, else the family
  /// lookup when it answers that very face; null when the server has none.
  Future<ServerFont?> _resolve(String name) async {
    final wanted = name.toLowerCase();
    final saved = await _cache.load();
    for (final font in [...?saved?.trending, ...?saved?.more]) {
      if (font.name.toLowerCase() == wanted) return font;
    }
    try {
      final font = await _client.byFamily(name);
      return font.name.toLowerCase() == wanted ? font : null;
    } on SlimshotApiException catch (e) {
      if (e.code == 'NOT_FOUND') return null;
      rethrow;
    }
  }

  Future<FontAvailability> _register(String name, String path) async =>
      await _registry.registerFile(name, path) ? FontAvailability.available : FontAvailability.failed;

  /// Makes each of [names] drawable, one at a time, whatever each comes to —
  /// what a grid of tiles asks for its looks.
  Future<void> prefetch(Iterable<String> names) async {
    for (final name in names.toSet()) {
      if (_registry.isAvailable(name)) continue;
      await ensureAvailable(name);
    }
  }

  /// Downloads a newer version of each font in [listed] that is on the phone
  /// in an older one. A font already registered this session keeps the
  /// registered bytes; the new file is used from the next start.
  Future<void> updateOutdated(Iterable<ServerFont> listed) async {
    try {
      await _library.load();
    } catch (_) {
      return;
    }
    for (final font in listed) {
      final onPhone = _library.find(font.name);
      if (onPhone == null || font.version <= onPhone.version) continue;
      try {
        final ticket = await _client.download(font.id);
        final entry = await _library.download(font, ticket);
        if (!_registry.isAvailable(font.name)) {
          await _registry.registerFile(font.name, entry.filePath);
        }
      } catch (_) {
        // The old version stays and keeps working; the next list tries again.
      }
    }
  }

  /// Registers every font in [names] that is on the phone.
  Future<void> registerOnPhone(Iterable<String> names) =>
      registerFontsOnPhone(names, library: _library, registry: _registry);

  static bool _isOffline(Object e) =>
      (e is FontDownloadFailed && e.offline) ||
      (e is SlimshotApiException && e.code == SlimshotApiException.network) ||
      e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException;
}
