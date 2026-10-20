import '../logic/animation/animatable_double.dart';
import '../logic/effects/effect_catalog.dart';
import 'media_asset.dart';

/// One effect over a stretch of the timeline: a bar on the lanes, beside text,
/// photos, video overlays and audio.
///
/// **It lives in timeline time.** Moving, trimming or deleting a clip leaves a
/// bar where it is — CapCut's behaviour, and what lets one effect span a cut,
/// start mid-clip or stack on another. It applies to the main video: the clips
/// and the background, under every overlay.
///
/// [intensity] is the bar's one keyframable property. Its keyframes and
/// envelope resolve at the bar's own progress, `(t - start) / duration`, so a
/// trimmed bar stretches its curve with it — the overlay rule.
class EffectBarModel {
  const EffectBarModel({
    required this.id,
    required this.effectId,
    required this.start,
    required this.end,
    this.laneIndex = 0,
    this.intensity = kDefaultEffectIntensityParameter,
  });

  final String id;

  /// A catalog id, persisted as written: an id this build does not know is
  /// kept, shown on the timeline and drawn as nothing — never dropped, so a
  /// draft from a newer build survives a round trip through this one.
  final String effectId;

  /// Timeline seconds.
  final double start;
  final double end;

  final int laneIndex;
  final AnimatableDouble intensity;

  double get duration => end - start;

  EffectBarModel copyWith({
    String? id,
    String? effectId,
    double? start,
    double? end,
    int? laneIndex,
    AnimatableDouble? intensity,
  }) {
    return EffectBarModel(
      id: id ?? this.id,
      effectId: effectId ?? this.effectId,
      start: start ?? this.start,
      end: end ?? this.end,
      laneIndex: laneIndex ?? this.laneIndex,
      intensity: intensity ?? this.intensity,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'effectId': effectId,
        'start': start,
        'end': end,
        'laneIndex': laneIndex,
        'intensity': intensity.toJson(),
      };

  /// Reads whatever a draft holds and **never throws**: a hand-edited or
  /// half-written bar comes back at a finite start, at least
  /// [kMinClipDurationSeconds] long — the timeline's own minimum — rather than
  /// as a bar nothing can draw or grab.
  factory EffectBarModel.fromJson(Map<String, dynamic> json) {
    double finite(Object? raw, double fallback) {
      if (raw is! num) return fallback;
      final value = raw.toDouble();
      return value.isFinite ? value : fallback;
    }

    final rawId = json['id'];
    final rawEffect = json['effectId'];
    final start = finite(json['start'], 0).clamp(0.0, double.maxFinite).toDouble();
    var end = finite(json['end'], start + kMinClipDurationSeconds);
    if (end - start < kMinClipDurationSeconds) end = start + kMinClipDurationSeconds;
    final rawLane = json['laneIndex'];

    return EffectBarModel(
      id: rawId is String ? rawId : 'effect_${DateTime.now().microsecondsSinceEpoch}',
      effectId: rawEffect is String ? rawEffect : '',
      start: start,
      end: end,
      laneIndex: rawLane is int && rawLane >= 0 ? rawLane : 0,
      intensity: AnimatableDouble.fromJson(
        json['intensity'],
        fallback: defaultEffectIntensity,
      ),
    );
  }
}
