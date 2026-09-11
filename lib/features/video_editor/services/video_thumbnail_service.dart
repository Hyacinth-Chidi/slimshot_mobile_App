import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Supplies filmstrip frames, cached in memory.
///
/// Frames are keyed by `(path, timeMs)`, so the cache is naturally multi-source
/// — a timeline built from several imported videos shares one cache without
/// them colliding.
///
/// Callers paint from [peek], which is synchronous and never blocks a frame,
/// and call [request] for whatever came back null. That split is what keeps
/// scrolling smooth: an already-decoded tile appears immediately, and a missing
/// one fills in when it arrives rather than holding up the strip.
class VideoThumbnailService {
  VideoThumbnailService._();

  static final VideoThumbnailService instance = VideoThumbnailService._();

  @visibleForTesting
  VideoThumbnailService.forTesting({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'slimshot_ai/video_thumbnails';

  MethodChannel _channel = const MethodChannel(_channelName);

  /// Insertion-ordered so the oldest entry is the first key — a cheap LRU.
  final LinkedHashMap<String, Uint8List?> _cache = LinkedHashMap();
  final Set<String> _inFlight = <String>{};

  /// Frames held in memory. At ~2KB per 160px JPEG this is a few megabytes,
  /// which covers a long timeline comfortably.
  static const int _maxEntries = 900;

  String _key(String path, int timeMs) => '$path@$timeMs';

  /// The frame for this instant if it has already been decoded.
  ///
  /// Returns null both when the frame is not loaded yet and when extraction
  /// failed; the strip renders a placeholder either way.
  Uint8List? peek(String path, int timeMs) => _cache[_key(path, timeMs)];

  /// True once we have tried this frame, successfully or not. Lets a caller
  /// stop re-requesting a frame the source cannot produce.
  bool isResolved(String path, int timeMs) => _cache.containsKey(_key(path, timeMs));

  /// Fetches any of [timesMs] that are neither cached nor already being
  /// fetched. Completes when this batch lands; other callers' batches are not
  /// waited on.
  Future<void> request({
    required String path,
    required List<int> timesMs,
    int width = 160,
    int height = 160,
  }) async {
    final missing = <int>[];
    for (final timeMs in timesMs) {
      final key = _key(path, timeMs);
      if (_cache.containsKey(key) || _inFlight.contains(key)) continue;
      _inFlight.add(key);
      missing.add(timeMs);
    }
    if (missing.isEmpty) return;

    try {
      final frames = await _channel.invokeListMethod<Uint8List?>('getFrames', {
        'path': path,
        'timesMs': missing,
        'width': width,
        'height': height,
      });

      for (var i = 0; i < missing.length; i++) {
        _store(_key(path, missing[i]), frames?.elementAtOrNull(i));
      }
    } catch (error) {
      // Record the failure so the strip does not spin on an unreadable file.
      for (final timeMs in missing) {
        _store(_key(path, timeMs), null);
      }
      debugPrint('[Thumbnails] $path failed: $error');
    } finally {
      for (final timeMs in missing) {
        _inFlight.remove(_key(path, timeMs));
      }
    }
  }

  void _store(String key, Uint8List? bytes) {
    _cache.remove(key);
    _cache[key] = bytes;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// One frame, fetched and returned directly.
  ///
  /// For one-off needs like the filter preview tile or a draft's cover image,
  /// where there is no strip to keep populated.
  Future<Uint8List?> singleFrame({
    required String path,
    required int timeMs,
    int width = 320,
    int height = 320,
  }) async {
    await request(
      path: path,
      timesMs: [timeMs],
      width: width,
      height: height,
    );
    return peek(path, timeMs);
  }

  /// One frame decoded fresh at exactly the requested size, uncached.
  ///
  /// The strip cache keys by `(path, timeMs)` only — sizes share a key — so a
  /// cover-quality frame must not go through it: it would either come back as
  /// a 160px strip tile or push a full-size image into the strip's memory.
  Future<Uint8List?> frameAtSize({
    required String path,
    required int timeMs,
    required int width,
    required int height,
  }) async {
    try {
      final frames = await _channel.invokeListMethod<Uint8List?>('getFrames', {
        'path': path,
        'timesMs': [timeMs],
        'width': width,
        'height': height,
      });
      return frames?.firstOrNull;
    } catch (error) {
      debugPrint('[Thumbnails] $path frameAtSize failed: $error');
      return null;
    }
  }

  /// Drops cached frames for one file and closes its native extractor.
  Future<void> releaseSource(String path) async {
    _cache.removeWhere((key, _) => key.startsWith('$path@'));
    try {
      await _channel.invokeMethod<void>('releaseSource', {'path': path});
    } catch (_) {
      // Nothing to release.
    }
  }

  Future<void> releaseAll() async {
    _cache.clear();
    _inFlight.clear();
    try {
      await _channel.invokeMethod<void>('releaseAll');
    } catch (_) {
      // Nothing to release.
    }
  }
}
