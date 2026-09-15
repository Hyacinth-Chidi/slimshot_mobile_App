import '../logic/animation/animatable_double.dart';
import '../logic/effects/effect_catalog.dart';
import '../logic/filter_presets.dart';

class VideoSegment {
  final String id;

  /// The [MediaAsset] this clip is cut from.
  ///
  /// Empty only for clips restored from a draft saved before projects could
  /// hold more than one file; those are reassigned to the migrated asset on
  /// load. Resolve it through `VideoEditorState.assetFor` rather than assuming
  /// any particular asset.
  final String assetId;

  final double sourceStart;
  final double sourceEnd;
  final double volume;
  final double speed;
  final String? transitionType;
  final double? transitionDuration;
  final String? overrideVideoPath;
  final bool isReversed;

  /// The user's pinch scale on top of the automatic contain-fit.
  ///
  /// 1.0 is the plain fit; above it the clip crops toward filling the canvas,
  /// below it shrinks into the background. Distinct from crop/zoom, which
  /// changes what part of the *source* is shown — this changes how the clip
  /// sits *on the canvas*.
  final double canvasScale;

  /// Where the clip's centre is dragged to, as offsets from the canvas centre
  /// in canvas fractions. Zero is centred.
  final double canvasOffsetX;
  final double canvasOffsetY;

  /// Colour filter on this clip alone, as a [FilterPresets] id.
  ///
  /// Null means the clip is ungraded — which is not the same as ungraded
  /// output, because the project may still carry a filter of its own
  /// (`VideoEditorState.selectedFilter`) that is applied to the finished frame.
  /// A clip filter is applied to the clip *before* a transition blends it, so
  /// two clips with different looks cross-fade between those looks.
  final String? filterId;
  final double filterIntensity;

  /// Visual effect on this clip alone, as a [VideoEffect] id.
  ///
  /// Null means the clip is unaffected. Distinct from [filterId]: a filter is a
  /// colour matrix applied to the texels as the clip is sampled, while an
  /// effect is a shader pass (or a chain of them) over the whole clip — grain,
  /// glitch, blur. The two compose, so a clip may carry both.
  ///
  /// **The stored string is kept verbatim even when this build does not know
  /// it.** An id from a newer build must survive a round trip through an older
  /// one's drafts rather than being silently erased on save; it simply resolves
  /// to null and draws nothing meanwhile. Resolve it through [effect], never by
  /// assuming the catalog contains it.
  final String? effectId;

  /// How strongly [effectId] is applied, **normalised 0..1**, and how that
  /// strength varies across the clip.
  ///
  /// Never a pixel radius: the same clip is drawn into a ~400px preview and a
  /// 1080p export, and a pixel parameter would make those two different
  /// pictures. The shader scales this into whatever units it needs against the
  /// frame it is actually drawing.
  ///
  /// An [AnimatableDouble] rather than a plain double so an effect can *move*
  /// over its clip — a glitch that pulses, a blur that clears — from a named
  /// envelope the catalog declares or from keyframes the user places. **A
  /// parameter carrying neither resolves flat to its base value at every
  /// progress**, which is exactly what the scalar did, so a clip that has not
  /// asked for animation renders identically to how it always has.
  ///
  /// The intensity slider writes [AnimatableDouble.baseValue] and leaves the
  /// envelope and keyframes alone — retuning a strength must not silently
  /// discard the shape the user (or the catalog) put on it.
  final AnimatableDouble effectIntensity;

  /// The effect strength at [progress] (0..1 through the clip's effect
  /// window).
  ///
  /// Convenience for the Dart-side consumers that need a number rather than a
  /// parameter. Both renderers resolve it themselves, on their own clock.
  double effectIntensityAt(double progress) =>
      effectIntensity.resolveAt(progress);

  VideoSegment({
    required this.id,
    this.assetId = '',
    required this.sourceStart,
    required this.sourceEnd,
    this.volume = 1.0,
    this.speed = 1.0,
    this.transitionType,
    this.transitionDuration,
    this.overrideVideoPath,
    this.isReversed = false,
    this.filterId,
    this.filterIntensity = 1.0,
    this.effectId,
    this.effectIntensity = kDefaultEffectIntensityParameter,
    this.canvasScale = 1.0,
    this.canvasOffsetX = 0.0,
    this.canvasOffsetY = 0.0,
  });

  double get duration => (sourceEnd - sourceStart) / speed;

  /// Source position [secondsIntoClip] seconds into this clip's span on the
  /// timeline.
  ///
  /// This is the same mapping playback uses, so anything laid out with it —
  /// the filmstrip especially — stays aligned to the playhead through trims,
  /// speed changes, reversal, and transition overlaps.
  double sourceAtOffset(double secondsIntoClip) {
    final offset = secondsIntoClip.clamp(0.0, duration) * speed;
    final source = isReversed ? sourceEnd - offset : sourceStart + offset;
    return source.clamp(sourceStart, sourceEnd).toDouble();
  }

  VideoSegment copyWith({
    String? id,
    String? assetId,
    double? sourceStart,
    double? sourceEnd,
    double? volume,
    double? speed,
    String? transitionType,
    bool clearTransitionType = false,
    double? transitionDuration,
    bool clearTransitionDuration = false,
    String? overrideVideoPath,
    bool clearOverrideVideoPath = false,
    bool? isReversed,
    String? filterId,
    bool clearFilterId = false,
    double? filterIntensity,
    String? effectId,
    bool clearEffectId = false,
    AnimatableDouble? effectIntensity,
    double? canvasScale,
    double? canvasOffsetX,
    double? canvasOffsetY,
  }) {
    return VideoSegment(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      sourceStart: sourceStart ?? this.sourceStart,
      sourceEnd: sourceEnd ?? this.sourceEnd,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      transitionType: clearTransitionType ? null : (transitionType ?? this.transitionType),
      transitionDuration: clearTransitionDuration ? null : (transitionDuration ?? this.transitionDuration),
      overrideVideoPath: clearOverrideVideoPath ? null : (overrideVideoPath ?? this.overrideVideoPath),
      isReversed: isReversed ?? this.isReversed,
      filterId: clearFilterId ? null : (filterId ?? this.filterId),
      filterIntensity: filterIntensity ?? this.filterIntensity,
      effectId: clearEffectId ? null : (effectId ?? this.effectId),
      effectIntensity: effectIntensity ?? this.effectIntensity,
      canvasScale: canvasScale ?? this.canvasScale,
      canvasOffsetX: canvasOffsetX ?? this.canvasOffsetX,
      canvasOffsetY: canvasOffsetY ?? this.canvasOffsetY,
    );
  }

  /// This clip's own grade as a 4×5 `ColorFilter.matrix`, or null if ungraded.
  List<double>? get filterMatrix {
    final preset = FilterPresets.byId(filterId);
    if (preset == null) return null;
    return preset.getInterpolatedMatrix(filterIntensity);
  }

  /// This clip's effect resolved against the catalog, or null when it has none
  /// — including when it stores an id this build does not know.
  ///
  /// Every consumer goes through this rather than reading [effectId] directly,
  /// which is what makes an unrecognised id degrade to an unaffected clip
  /// instead of reaching a renderer with no shader for it.
  VideoEffect? get effect => videoEffectById(effectId);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'assetId': assetId,
      'sourceStart': sourceStart,
      'sourceEnd': sourceEnd,
      'volume': volume,
      'speed': speed,
      'transitionType': transitionType,
      'transitionDuration': transitionDuration,
      'overrideVideoPath': overrideVideoPath,
      'isReversed': isReversed,
      'filterId': filterId,
      'filterIntensity': filterIntensity,
      'effectId': effectId,
      // A bare number while nothing animates it, a map once something does —
      // see [AnimatableDouble.toJson]. So a clip that has not asked for
      // animation writes the field exactly as it always has, and a draft
      // written here still opens in a build that predates this model.
      'effectIntensity': effectIntensity.toJson(),
      'canvasScale': canvasScale,
      'canvasOffsetX': canvasOffsetX,
      'canvasOffsetY': canvasOffsetY,
    };
  }

  factory VideoSegment.fromJson(Map<String, dynamic> json) {
    return VideoSegment(
      id: json['id'] as String,
      // Absent in drafts saved before multi-asset projects; the loader
      // reassigns those to the migrated asset.
      assetId: json['assetId'] as String? ?? '',
      sourceStart: (json['sourceStart'] as num).toDouble(),
      sourceEnd: (json['sourceEnd'] as num).toDouble(),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      transitionType: json['transitionType'] as String?,
      transitionDuration: (json['transitionDuration'] as num?)?.toDouble(),
      overrideVideoPath: json['overrideVideoPath'] as String?,
      isReversed: json['isReversed'] as bool? ?? false,
      // Absent in drafts saved before clips could carry their own filter.
      filterId: json['filterId'] as String?,
      filterIntensity: (json['filterIntensity'] as num?)?.toDouble() ?? 1.0,
      // Absent in every draft written before clips could carry an effect, so
      // both reads fall back rather than throwing — a saved project must open
      // in a build that added fields under it.
      effectId: json['effectId'] as String?,
      // **Every draft saved before this stage holds a bare number here**, and
      // one written before effects existed holds nothing at all.
      // `AnimatableDouble.fromJson` takes `dynamic` for exactly that: a number
      // loads as a flat value with no envelope and no keyframes, a map loads
      // fully, and anything else — absent, null, junk — falls back rather than
      // throwing. A saved project turning into a crash on open is the worst
      // failure this read could have.
      effectIntensity: AnimatableDouble.fromJson(
        json['effectIntensity'],
        fallback: defaultEffectIntensity,
      ),
      canvasScale: (json['canvasScale'] as num?)?.toDouble() ?? 1.0,
      canvasOffsetX: (json['canvasOffsetX'] as num?)?.toDouble() ?? 0.0,
      canvasOffsetY: (json['canvasOffsetY'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
