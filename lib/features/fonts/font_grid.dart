import 'package:flutter/foundation.dart';

import '../../core/services/slimshot_api.dart';
import 'data/font_catalog_cache.dart';
import 'data/font_client.dart';
import 'data/font_library.dart';
import 'data/font_models.dart';
import 'data/font_preview_cache.dart';
import 'font_names.dart';
import 'font_service.dart';

/// What a download that failed for want of a connection says.
const String kFontNoConnectionMessage = 'No internet connection';

/// What any other failed download says.
const String kFontDownloadFailedMessage = "Couldn't download this font";

enum FontSource { system, bundled, server }

/// One tile of the Font tab.
class FontEntry {
  const FontEntry({
    required this.name,
    required this.label,
    required this.source,
    this.font,
  });

  /// What a text stores in `fontFamily`.
  final String name;

  /// What the tile says: `SYSTEM`, a bundled font's name, a server font's
  /// display name.
  final String label;
  final FontSource source;

  /// The server's font, for a server tile.
  final ServerFont? font;
}

/// The Font tab's tiles in order: System, the bundled fonts, then every
/// published font in the owner's order. A server font named like a local
/// one, or listed twice, shows once — names compared in any case, as the
/// server compares them.
List<FontEntry> fontGridEntries(List<ServerFont> fonts) {
  final entries = <FontEntry>[
    const FontEntry(name: kSystemFontName, label: 'SYSTEM', source: FontSource.system),
    for (final name in kBundledFontNames)
      FontEntry(name: name, label: name, source: FontSource.bundled),
  ];
  final seen = {for (final e in entries) e.name.toLowerCase()};
  for (final font in fonts) {
    if (!seen.add(font.name.toLowerCase())) continue;
    entries.add(FontEntry(
      name: font.name,
      label: font.displayName,
      source: FontSource.server,
      font: font,
    ));
  }
  return entries;
}

/// The entries matching [query], ignoring case, spaces, dashes and
/// underscores, on the label or the name.
List<FontEntry> filterFontEntries(List<FontEntry> entries, String query) {
  final wanted = _fold(query);
  if (wanted.isEmpty) return entries;
  return [
    for (final e in entries)
      if (_fold(e.label).contains(wanted) || _fold(e.name).contains(wanted)) e,
  ];
}

String _fold(String text) => text.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');

/// What a tile shows.
sealed class FontTileState {
  const FontTileState();
}

/// On the phone: a tap applies it.
final class FontReady extends FontTileState {
  const FontReady();
}

/// Not downloaded yet: the arrow.
final class FontNotOnPhone extends FontTileState {
  const FontNotOnPhone();
}

/// On its way: the ring, at [progress] (0..1).
final class FontDownloading extends FontTileState {
  const FontDownloading(this.progress);
  final double progress;
}

/// The last download failed: the arrow, and a tap tries again.
final class FontFailed extends FontTileState {
  const FontFailed();
}

/// The Font tab's state: the lists, search, and what each tile is doing.
///
/// The saved list shows at once and the server's is asked for on every
/// opening and on refresh. A 429 keeps what is shown and asks nothing until
/// the server's wait has passed; with no server address nothing is asked at
/// all. **The last tap wins**: a download that lands after another
/// font was chosen, or after the tab closed, applies nothing.
class FontGridController extends ChangeNotifier {
  FontGridController({
    required FontService service,
    required FontClient client,
    required FontCatalogCache cache,
    required FontLibrary library,
    required FontPreviewCache previews,
    bool? serverConfigured,
    DateTime Function()? now,
  })  : _service = service,
        _client = client,
        _cache = cache,
        _library = library,
        _previews = previews,
        _serverConfigured = serverConfigured ?? SlimshotApi.isConfigured,
        _now = now ?? DateTime.now;

  final FontService _service;
  final FontClient _client;
  final FontCatalogCache _cache;
  final FontLibrary _library;
  final FontPreviewCache _previews;
  final bool _serverConfigured;
  final DateTime Function() _now;

  List<ServerFont> _fonts = const [];
  String _query = '';
  final Map<String, double> _downloading = {};
  final Set<String> _failed = {};
  int _choice = 0;
  DateTime? _waitUntil;
  String? _notice;
  bool _disposed = false;

  FontPreviewCache get previews => _previews;

  /// The tiles, filtered by [query].
  List<FontEntry> get entries =>
      filterFontEntries(fontGridEntries(_fonts), _query);

  String get query => _query;
  set query(String value) {
    if (value == _query) return;
    _query = value;
    _notify();
  }

  /// A message for a toast, once.
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  FontTileState stateOf(FontEntry entry) {
    if (entry.source != FontSource.server) return const FontReady();
    final progress = _downloading[entry.name];
    if (progress != null) return FontDownloading(progress);
    // Failed before on-the-phone: a file the engine refused is on the phone
    // and still not a font, and a tap must be offered to fetch it again.
    if (_failed.contains(entry.name)) return const FontFailed();
    if (_library.find(entry.name) != null) return const FontReady();
    return const FontNotOnPhone();
  }

  /// Shows the saved list at once, then asks the server for its own — on
  /// every opening, so a font the owner publishes is there the next time the
  /// tab opens. The server caches the list and clears it on any change, so
  /// asking costs one small read.
  Future<void> open() async {
    if (!_serverConfigured) return;
    await _previews.prepare();
    await _library.load();
    final saved = await _cache.load();
    if (saved != null) {
      _fonts = saved.fonts;
      _notify();
    }
    await _fetch();
  }

  /// Fetches the server's list now, unless the server asked for a wait.
  Future<void> refresh() async {
    if (!_serverConfigured) return;
    await _fetch();
  }

  Future<void> _fetch() async {
    final waitUntil = _waitUntil;
    if (waitUntil != null && _now().isBefore(waitUntil)) return;
    final List<ServerFont> fonts;
    try {
      fonts = await _client.list();
    } on SlimshotApiException catch (e) {
      if (e.code == 'RATE_LIMITED') {
        _waitUntil = _now().add(Duration(seconds: e.detailInt('retryAfterSeconds') ?? 30));
      }
      return;
    } catch (_) {
      return;
    }
    if (_disposed) return;
    _fonts = fonts;
    _notify();
    await _cache.save(SavedFontList(fonts: fonts, fetchedAt: _now()));
    await _previews.fetchAll([
      for (final font in fonts)
        if (font.previewUrl case final url?) url,
    ]);
    _notify();
    await _service.updateOutdated(fonts);
  }

  /// Applies [entry]'s font through [apply] once it is drawable — at once
  /// when it is already on the phone — unless another font is chosen first.
  Future<void> choose(FontEntry entry, ValueChanged<String> apply) async {
    final choice = ++_choice;
    if (entry.source != FontSource.server) {
      apply(entry.name);
      return;
    }
    final onPhone = _library.find(entry.name) != null;
    if (!onPhone) {
      _failed.remove(entry.name);
      _downloading[entry.name] = 0;
      _notify();
    }
    final result = await _service.ensureAvailable(
      entry.name,
      onProgress: (progress) {
        if (_downloading.containsKey(entry.name)) {
          _downloading[entry.name] = progress;
          _notify();
        }
      },
    );
    _downloading.remove(entry.name);
    if (_disposed) return;
    if (result == FontAvailability.available) {
      if (choice == _choice) apply(entry.name);
    } else {
      _failed.add(entry.name);
      _notice = result == FontAvailability.offline
          ? kFontNoConnectionMessage
          : kFontDownloadFailedMessage;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
