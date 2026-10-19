import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/services/slimshot_api.dart';
import 'data/catalog_cache.dart';
import 'data/catalog_client.dart';
import 'data/catalog_models.dart';
import 'data/sound_library.dart';

/// The pill that lists the sounds on the phone. Not a server slug: the
/// server's slugs are words, never this.
const String kDownloadedPill = '__downloaded__';

/// What plays a sound in the sheet. An interface so the rules can be tested
/// without a speaker.
abstract class SoundPreviewPlayer {
  Future<void> play(String path);
  Future<void> stop();

  /// The file's length in seconds, or null when it will not open.
  Future<double?> durationOf(String path);
  Future<void> dispose();
}

/// The sheet's player: one `just_audio` player, reused row to row. Plugin
/// code, exercised on a device.
class JustAudioPreviewPlayer implements SoundPreviewPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> play(String path) async {
    await _player.setFilePath(path);
    unawaited(_player.play());
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<double?> durationOf(String path) async {
    final probe = AudioPlayer();
    try {
      final duration = await probe.setFilePath(path);
      return duration == null ? null : duration.inMilliseconds / 1000.0;
    } catch (_) {
      return null;
    } finally {
      await probe.dispose();
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}

enum SoundSheetNoticeKind { downloadFailed, unavailable }

/// Something the sheet tells the user once, as a toast.
class SoundSheetNotice {
  const SoundSheetNotice(this.kind, this.title);

  final SoundSheetNoticeKind kind;
  final String title;
}

/// The sound effects sheet's state and every rule it follows, apart from the
/// widget so the rules can be tested without one.
///
/// Requests are numbered: an answer that arrives after the pill changed, or
/// after a refresh, is dropped. A rate limit stops automatic requests until
/// its window passes; Retry and pull-to-refresh wait the window out.
class SoundEffectsController extends ChangeNotifier {
  SoundEffectsController({
    required CatalogClient client,
    required SoundLibrary library,
    required CatalogCache cache,
    required SoundPreviewPlayer player,
    this.root = kSoundEffectsRoot,
    DateTime Function() now = DateTime.now,
    Future<void> Function(Duration) wait = Future<void>.delayed,
  })  : _client = client,
        _library = library,
        _cache = cache,
        _player = player,
        _now = now,
        _wait = wait;

  final CatalogClient _client;
  final SoundLibrary _library;
  final CatalogCache _cache;
  final SoundPreviewPlayer _player;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;
  final String root;

  final StreamController<SoundSheetNotice> _notices =
      StreamController.broadcast();

  List<CatalogCategory> _categories = const [];
  List<LibrarySound> _downloaded = const [];
  String _selected = kDownloadedPill;
  List<CatalogSound> _sounds = const [];
  String? _cursor;
  bool _loading = false;
  bool _offline = false;
  int _request = 0;
  DateTime? _blockedUntil;

  final Map<String, double> _progress = {};
  final Map<String, Future<LibrarySound?>> _fetches = {};
  String? _playingId;
  String? _listenPending;
  String? _addingId;
  bool _disposed = false;
  bool _opened = false;

  Stream<SoundSheetNotice> get notices => _notices.stream;

  List<String> get pills => [kDownloadedPill, for (final c in _categories) c.slug];

  String pillName(String slug) {
    if (slug == kDownloadedPill) return 'Downloaded';
    for (final c in _categories) {
      if (c.slug == slug) return c.name;
    }
    return slug;
  }

  String get selected => _selected;

  List<CatalogSound> get sounds => _selected == kDownloadedPill
      ? [for (final s in _downloaded) s.asCatalogSound]
      : _sounds;

  bool get loading => _loading;
  bool get offline => _offline;
  bool get hasMore => _selected != kDownloadedPill && _cursor != null;
  bool inLibrary(String id) => _library.find(id) != null;

  /// 0..1 while [id] downloads; null otherwise.
  double? progressOf(String id) => _progress[id];
  String? get playingId => _playingId;

  /// The sound whose + is downloading — the ring goes on the + rather than
  /// on the cover.
  String? get addingId => _addingId;

  LibrarySound? librarySound(String id) => _library.find(id);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _tell(SoundSheetNoticeKind kind, String title) {
    if (!_disposed) _notices.add(SoundSheetNotice(kind, title));
  }

  /// Shows what is kept at once, then asks the server. Once per controller:
  /// a second call is a no-op.
  Future<void> open() async {
    if (_opened) return;
    _opened = true;
    _downloaded = await _library.load();
    await _cache.load();
    if (_disposed) return;
    _categories = _cache.categories;
    if (_categories.isNotEmpty) {
      _selected = _categories.first.slug;
      _sounds = _cache.firstPage(_selected);
    }
    _notify();
    await _fetchCategories(opening: true);
    if (_selected != kDownloadedPill) await _loadFirstPage(automatic: true);
  }

  Future<void> select(String pill) async {
    if (_disposed) return;
    _selected = pill;
    _request++;
    _cursor = null;
    _loading = false;
    _sounds = pill == kDownloadedPill ? const [] : _cache.firstPage(pill);
    _notify();
    if (pill != kDownloadedPill) await _loadFirstPage(automatic: true);
  }

  Future<void> loadMore() async {
    if (_disposed || !hasMore || _loading || _isBlocked) return;
    final token = _request;
    final pill = _selected;
    _loading = true;
    _notify();
    try {
      final page = await _client.sounds(pill, cursor: _cursor);
      if (_disposed || token != _request) return;
      final seen = {for (final s in _sounds) s.id};
      _sounds = [..._sounds, ...page.items.where((s) => seen.add(s.id))];
      _cursor = page.nextCursor;
      _offline = false;
    } on SlimshotApiException catch (e) {
      if (_disposed || token != _request) return;
      await _failed(e, pill);
    } finally {
      if (!_disposed && token == _request) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Pull to refresh: the pills and the pill shown, again.
  Future<void> refresh() async {
    await _waitOutBlock();
    if (_disposed) return;
    _request++;
    await _fetchCategories();
    if (_selected != kDownloadedPill) await _loadFirstPage();
  }

  Future<void> retry() => refresh();

  bool get _isBlocked {
    final until = _blockedUntil;
    return until != null && _now().isBefore(until);
  }

  Future<void> _waitOutBlock() async {
    final until = _blockedUntil;
    if (until == null) return;
    final left = until.difference(_now());
    if (left > Duration.zero) await _wait(left);
    _blockedUntil = null;
  }

  Future<void> _fetchCategories({bool opening = false}) async {
    if (_isBlocked) return;
    final token = _request;
    try {
      final categories = await _client.categories(root);
      if (_disposed || token != _request) return;
      _categories = categories;
      _offline = false;
      unawaited(_cache.saveCategories(categories).catchError((_) {}));
      if (opening && _selected == kDownloadedPill && categories.isNotEmpty) {
        _selected = categories.first.slug;
        _sounds = _cache.firstPage(_selected);
      } else if (!pills.contains(_selected)) {
        _selected = kDownloadedPill;
        _sounds = const [];
        _cursor = null;
      }
    } on SlimshotApiException catch (e) {
      if (_disposed || token != _request) return;
      if (e.code == 'NOT_FOUND') {
        // The root is not there yet: the library is all there is.
        _categories = const [];
        _offline = false;
        unawaited(_cache.saveCategories(const []).catchError((_) {}));
        _selected = kDownloadedPill;
        _sounds = const [];
        _cursor = null;
      } else {
        _classify(e);
      }
    }
    _notify();
  }

  Future<void> _loadFirstPage({bool automatic = false}) async {
    if (automatic && _isBlocked) return;
    final token = ++_request;
    final pill = _selected;
    _loading = true;
    _notify();
    try {
      final page = await _client.sounds(pill);
      if (_disposed || token != _request) return;
      final seen = <String>{};
      _sounds = [for (final s in page.items) if (seen.add(s.id)) s];
      _cursor = page.nextCursor;
      _offline = false;
      unawaited(_cache.saveFirstPage(pill, _sounds).catchError((_) {}));
    } on SlimshotApiException catch (e) {
      if (_disposed || token != _request) return;
      await _failed(e, pill);
    } finally {
      if (!_disposed && token == _request) {
        _loading = false;
        _notify();
      }
    }
  }

  /// A list that failed. A category gone from the server sends the sheet
  /// back to the pills as they are now.
  Future<void> _failed(SlimshotApiException e, String pill) async {
    if (e.code == 'NOT_FOUND') {
      _loading = false;
      await _fetchCategories();
      if (!_disposed && !pills.contains(pill)) await select(kDownloadedPill);
      return;
    }
    _classify(e);
  }

  void _classify(SlimshotApiException e) {
    if (e.code == 'RATE_LIMITED') {
      _blockedUntil = _now().add(Duration(seconds: retryAfterSeconds(e) ?? 30));
      return;
    }
    _offline = true;
  }

  /// A tap on a row: listen. On the phone, it plays (or stops); not yet,
  /// it downloads first and plays when it lands — unless another row was
  /// tapped meanwhile, in which case it is kept and not played.
  Future<void> tapRow(CatalogSound sound) async {
    if (_disposed) return;
    final kept = _library.find(sound.id);
    if (kept != null) {
      _listenPending = null;
      if (_playingId == sound.id) {
        _playingId = null;
        _notify();
        await _player.stop();
      } else {
        _playingId = sound.id;
        _notify();
        await _player.play(kept.filePath);
      }
      return;
    }
    if (_offline) return;
    _listenPending = sound.id;
    if (_playingId != null) {
      _playingId = null;
      await _player.stop();
    }
    _notify();
    final entry = await _fetch(sound);
    if (_disposed || entry == null || _listenPending != sound.id) return;
    _listenPending = null;
    _playingId = sound.id;
    _notify();
    await _player.play(entry.filePath);
  }

  /// The + on a row: the sound, on the phone and with a length, ready for
  /// the timeline. Null when it cannot be had, when another add is running,
  /// or when the sheet closed before it landed.
  Future<LibrarySound?> add(CatalogSound sound) async {
    if (_disposed || _addingId != null) return null;
    if (_library.find(sound.id) == null && _offline) return null;
    _addingId = sound.id;
    _listenPending = null;
    if (_playingId != null) {
      _playingId = null;
      unawaited(_player.stop());
    }
    _notify();
    try {
      var entry = await _fetch(sound);
      if (_disposed || entry == null) return null;
      if (entry.durationMs <= 0) {
        final seconds = await _player.durationOf(entry.filePath);
        if (_disposed) return null;
        if (seconds == null || seconds <= 0) {
          _tell(SoundSheetNoticeKind.downloadFailed, sound.title);
          return null;
        }
        entry = entry.withDuration((seconds * 1000).round());
      }
      return entry;
    } finally {
      _addingId = null;
      _notify();
    }
  }

  /// The sound on the phone: from the library, or fetched — once, however
  /// many taps ask for it.
  Future<LibrarySound?> _fetch(CatalogSound sound) {
    final kept = _library.find(sound.id);
    if (kept != null) return Future.value(kept);
    return _fetches[sound.id] ??= _download(sound).whenComplete(() {
      _fetches.remove(sound.id);
    });
  }

  Future<LibrarySound?> _download(CatalogSound sound) async {
    _progress[sound.id] = 0;
    _notify();
    try {
      final ticket = await _client.download(sound.id);
      final entry = await _library.download(
        sound,
        ticket,
        onProgress: (p) {
          _progress[sound.id] = p;
          _notify();
        },
      );
      _downloaded = await _library.load();
      return entry;
    } on SlimshotApiException catch (e) {
      if (e.code == 'NOT_FOUND') {
        _sounds = [for (final s in _sounds) if (s.id != sound.id) s];
        _tell(SoundSheetNoticeKind.downloadFailed, sound.title);
      } else if (e.code == 'FORBIDDEN') {
        _tell(SoundSheetNoticeKind.unavailable, sound.title);
      } else {
        if (e.code == 'RATE_LIMITED') _classify(e);
        _tell(SoundSheetNoticeKind.downloadFailed, sound.title);
      }
      return null;
    } on SoundDownloadFailed {
      _tell(SoundSheetNoticeKind.downloadFailed, sound.title);
      return null;
    } finally {
      _progress.remove(sound.id);
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_player.stop().catchError((_) {}));
    unawaited(_player.dispose().catchError((_) {}));
    unawaited(_notices.close());
    super.dispose();
  }
}
