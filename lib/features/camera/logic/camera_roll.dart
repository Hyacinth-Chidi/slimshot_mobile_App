import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reaction.dart';

/// Where the camera remembers its shots.
const kCameraRollKey = 'camera_roll';

/// How many shots the roll remembers; older ones stay in the gallery.
const kCameraRollMax = 300;

/// One shot the camera took and saved.
@immutable
class RollShot {
  const RollShot({
    required this.path,
    this.uri,
    required this.isVideo,
    required this.durationMs,
    required this.takenAt,
    this.reaction,
  });

  /// The file itself — in the gallery's SlimShotAI album, or in SlimShot's
  /// own folder where storage access is off.
  final String path;

  /// The shot's address in the phone's gallery, what deleting it goes
  /// through; null for one kept inside SlimShot.
  final String? uri;

  final bool isVideo;
  final int durationMs;
  final DateTime? takenAt;

  /// For a REACT reaction, what it was made from — the take of you and the
  /// video reacted to — so Edit opens it as those two layers. Null for any
  /// other shot.
  final ReactionTake? reaction;

  bool get inGallery => uri != null;

  Map<String, Object?> toJson() => {
        'path': path,
        if (uri != null) 'uri': uri,
        'video': isVideo,
        if (durationMs > 0) 'ms': durationMs,
        if (takenAt != null) 'at': takenAt!.millisecondsSinceEpoch,
        if (reaction != null) 'react': reaction!.toJson(),
      };

  /// Null for an entry it cannot read.
  static RollShot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    if (path is! String || path.isEmpty) return null;
    final uri = raw['uri'];
    final ms = raw['ms'];
    final at = raw['at'];
    return RollShot(
      path: path,
      uri: uri is String && uri.isNotEmpty ? uri : null,
      isVideo: raw['video'] == true,
      durationMs: ms is num ? ms.toInt() : 0,
      takenAt: at is num ? DateTime.fromMillisecondsSinceEpoch(at.toInt()) : null,
      reaction: ReactionTake.fromJson(raw['react']),
    );
  }
}

/// The camera's own shots, newest first: what the pile beside the shutter and
/// the viewer show. Only shots taken with SlimShot's camera — reading the
/// whole gallery needs a media permission the app does not hold (the system
/// photo picker needs none) — so the roll is the app's own record, kept on
/// the phone, and a shot deleted in the gallery drops out at the next
/// [load].
class CameraRoll extends ChangeNotifier {
  List<RollShot> _shots = const [];

  List<RollShot> get shots => _shots;

  /// Reads the roll back, leaving out every shot whose file is gone.
  Future<void> load({required Future<bool> Function(String path) exists}) async {
    final stored = await _read();
    final kept = <RollShot>[];
    for (final shot in stored) {
      if (await exists(shot.path)) kept.add(shot);
    }
    // A shot taken while the roll was being read stays on top.
    final taken = _shots.where((s) => !kept.any((k) => k.path == s.path));
    _shots = List.unmodifiable([...taken, ...kept]);
    if (kept.length != stored.length) await _write(_shots);
    notifyListeners();
  }

  Future<void> add(RollShot shot) async {
    final next = [shot, ..._shots.where((s) => s.path != shot.path)];
    if (next.length > kCameraRollMax) next.removeRange(kCameraRollMax, next.length);
    _shots = List.unmodifiable(next);
    notifyListeners();
    await _write(next);
  }

  Future<void> remove(RollShot shot) async {
    final next = _shots.where((s) => s.path != shot.path).toList();
    if (next.length == _shots.length) return;
    _shots = List.unmodifiable(next);
    notifyListeners();
    await _write(next);
  }

  /// The files the roll keeps, for the launch sweep of the camera's folder:
  /// every shot, and every reaction's take.
  static Future<Set<String>> storedPaths() async => {
        for (final shot in await _read()) ...[
          shot.path,
          if (shot.reaction != null) shot.reaction!.camera.path,
        ],
      };

  static Future<List<RollShot>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kCameraRollKey);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [for (final item in decoded) ?RollShot.fromJson(item)];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _write(List<RollShot> shots) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kCameraRollKey, jsonEncode([for (final shot in shots) shot.toJson()]));
    } catch (_) {
      // Not remembered: the shots are still in the gallery.
    }
  }
}

/// The files deleting [shot] leaves in the camera's own folder, to go with
/// it: the shot itself where it was kept inside SlimShot (one in the gallery
/// goes through its address), and a reaction's take. Never the video a
/// reaction was made against — that is the user's.
List<String> cameraFilesOf(RollShot shot) => [
      if (shot.uri == null) shot.path,
      if (shot.reaction != null) shot.reaction!.camera.path,
    ];
