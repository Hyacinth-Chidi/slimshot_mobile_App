/// Keyframes for text, photo and video overlays.
///
/// **They ride beside the plain fields.** An overlay's `position`, `scale`,
/// `rotation` and `opacity` are unchanged and are its **base values** — what
/// every existing reader already uses, and all an overlay has until someone
/// places a diamond. An [OverlayKeyframes] track set sits next to them. That
/// is what let this feature land without touching the dozens of places that
/// read an overlay's position: an un-keyframed overlay is exactly what it was.
///
/// What a diamond *does* is `keyframe_core.dart`'s, shared with clips; this
/// file only says which parameters an overlay has ([OverlayProperty]) and how
/// to turn base values plus tracks into [KeyframeParams] and back
/// ([OverlayMotion]). Interpolation and easing are `AnimatableDouble`'s — the
/// same code, pinned against the Kotlin port, that clips use.
library;

import 'dart:ui' show Offset;

import 'animatable_double.dart';
import 'keyframe_core.dart';

/// Every property an overlay diamond pins.
///
/// Units are the plain fields': position in the overlay's own canvas pixels
/// (each model's convention, converted to canvas fractions at the composer),
/// scale a multiplier, rotation radians, opacity 0..1.
enum OverlayProperty { x, y, scale, rotation, opacity }

/// An overlay's keyframe tracks, by property. Empty is every overlay that
/// exists today.
class OverlayKeyframes {
  const OverlayKeyframes([this.tracks = const {}]);

  static const OverlayKeyframes none = OverlayKeyframes();

  final Map<OverlayProperty, List<Keyframe>> tracks;

  bool get isEmpty => tracks.values.every((t) => t.isEmpty);

  /// The keyframes on [p], possibly none.
  List<Keyframe> of(OverlayProperty p) => tracks[p] ?? const <Keyframe>[];

  /// Null when empty, so a model can leave the key out and an un-keyframed
  /// overlay's draft stays byte-identical to today's.
  Map<String, dynamic>? toJson() {
    if (isEmpty) return null;
    return {
      for (final p in OverlayProperty.values)
        if (of(p).isNotEmpty)
          p.name: (List<Keyframe>.of(of(p))
                ..sort((a, b) => a.progress.compareTo(b.progress)))
              .map((k) => k.toJson())
              .toList(),
    };
  }

  /// Reads whatever a draft holds, and **never throws**.
  ///
  /// A property name this build does not know is ignored, a track that is not
  /// a list is skipped, and an entry that is not a map is dropped — losing one
  /// keyframe leaves a project openable, and throwing loses the project. Each
  /// keyframe's own fields are read by `Keyframe.fromJson`, which degrades the
  /// same way.
  factory OverlayKeyframes.fromJson(dynamic json) {
    if (json is! Map) return none;
    final tracks = <OverlayProperty, List<Keyframe>>{};
    for (final p in OverlayProperty.values) {
      final raw = json[p.name];
      if (raw is! List) continue;
      final keyframes = <Keyframe>[
        for (final entry in raw)
          if (entry is Map) Keyframe.fromJson(Map<String, dynamic>.from(entry)),
      ];
      if (keyframes.isEmpty) continue;
      // Sorted through the parameter's own constructor, so a track read from
      // disk is ordered exactly as one built in memory.
      tracks[p] =
          AnimatableDouble.sorted(baseValue: 0, keyframes: keyframes).keyframes;
    }
    return tracks.isEmpty ? none : OverlayKeyframes(tracks);
  }
}

/// An overlay's base placement and its keyframe tracks, as one value.
///
/// Each overlay model exposes one (`motion`) and takes one back
/// (`withMotion`), so every keyframe operation — capture, remove, move, ease,
/// the edit rule — is written once against this type rather than three times
/// against three models.
class OverlayMotion {
  const OverlayMotion({
    required this.position,
    required this.scale,
    required this.rotation,
    required this.opacity,
    this.keyframes = OverlayKeyframes.none,
  });

  final Offset position;
  final double scale;
  final double rotation;
  final double opacity;
  final OverlayKeyframes keyframes;

  bool get hasKeyframes => !keyframes.isEmpty;

  double _base(OverlayProperty p) => switch (p) {
        OverlayProperty.x => position.dx,
        OverlayProperty.y => position.dy,
        OverlayProperty.scale => scale,
        OverlayProperty.rotation => rotation,
        OverlayProperty.opacity => opacity,
      };

  /// Every property as the parameter the shared keyframe core works on: its
  /// base value, and its track. In [OverlayProperty] order.
  KeyframeParams<OverlayProperty> get params => {
        for (final p in OverlayProperty.values)
          p: AnimatableDouble.sorted(
            baseValue: _base(p),
            keyframes: keyframes.of(p),
          ),
      };

  /// The motion [params] describe — the inverse of [params].
  ///
  /// A property missing from the map keeps a neutral base (0 for position and
  /// rotation, 1 for scale and opacity), which only a hand-built map can hit.
  factory OverlayMotion.fromParams(KeyframeParams<OverlayProperty> params) {
    double base(OverlayProperty p, double fallback) =>
        params[p]?.baseValue ?? fallback;
    final tracks = <OverlayProperty, List<Keyframe>>{
      for (final e in params.entries)
        if (e.value.keyframes.isNotEmpty) e.key: e.value.keyframes,
    };
    return OverlayMotion(
      position: Offset(base(OverlayProperty.x, 0), base(OverlayProperty.y, 0)),
      scale: base(OverlayProperty.scale, 1),
      rotation: base(OverlayProperty.rotation, 0),
      opacity: base(OverlayProperty.opacity, 1),
      keyframes:
          tracks.isEmpty ? OverlayKeyframes.none : OverlayKeyframes(tracks),
    );
  }

  /// This motion with [keyframes] in place of its tracks.
  OverlayMotion copyWithKeyframes(OverlayKeyframes keyframes) => OverlayMotion(
        position: position,
        scale: scale,
        rotation: rotation,
        opacity: opacity,
        keyframes: keyframes,
      );

  /// The placement at [progress] through the overlay, as a still motion with
  /// no tracks — or this very motion when nothing is keyframed, so the common
  /// case allocates nothing.
  OverlayMotion at(double progress) {
    if (!hasKeyframes) return this;
    final p = params;
    double v(OverlayProperty q) => p[q]!.resolveAt(progress);
    return OverlayMotion(
      position: Offset(v(OverlayProperty.x), v(OverlayProperty.y)),
      scale: v(OverlayProperty.scale),
      rotation: v(OverlayProperty.rotation),
      opacity: v(OverlayProperty.opacity),
    );
  }
}

/// How far [seconds] is through an overlay spanning [start]–[end], 0..1.
///
/// **Overlay-relative**, as a clip's keyframes are clip-relative: trimming or
/// extending the overlay stretches its motion with it. A zero or negative
/// span — an overlay trimmed to nothing, or a hand-edited draft — is progress
/// 0, never a division by zero.
double overlayProgressAt(Duration start, Duration end, double seconds) {
  final startSeconds = start.inMicroseconds / 1e6;
  final span = end.inMicroseconds / 1e6 - startSeconds;
  if (span <= 0) return 0;
  return ((seconds - startSeconds) / span).clamp(0.0, 1.0).toDouble();
}
