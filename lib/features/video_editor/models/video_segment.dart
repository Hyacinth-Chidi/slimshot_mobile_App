import 'dart:ui' show Rect;

import '../logic/animation/animatable_double.dart';
import '../logic/effects/effect_catalog.dart';
import '../logic/filter_presets.dart';
import '../logic/color/color_adjustments.dart';
import '../logic/mask/clip_mask.dart';
import '../logic/speed/speed_curve.dart';
import '../logic/chroma/chroma_key.dart';

/// A parameter resting at 1.0 — an ungained volume, an unpinched scale.
///
/// Shared `const` instances rather than a literal per default, so an
/// unkeyframed clip's four parameters are the *same object* and the identity
/// comparisons a `copyWith` chain performs stay cheap.
const AnimatableDouble kUnitParameter = AnimatableDouble(baseValue: 1.0);

/// A parameter resting at 0.0 — a centred clip's offsets.
const AnimatableDouble kZeroParameter = AnimatableDouble(baseValue: 0.0);

/// An uncropped clip: the whole source frame.
const Rect kFullFrameRect = Rect.fromLTWH(0, 0, 1, 1);

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

  /// This clip's own gain, and how it varies across the clip.
  ///
  /// An [AnimatableDouble] so a diamond can fade a clip down without touching
  /// the project's master volume. Resolve it through [volumeAt] at a progress;
  /// read [AnimatableDouble.baseValue] only where a *control* needs to know
  /// what to show, since a slider tracking the resolved value would wander
  /// while playing and write back whatever the curve happened to be at when the
  /// user grabbed it.
  final AnimatableDouble volume;

  final double speed;

  /// A speed that ramps across the clip, or null for the flat [speed].
  ///
  /// **The two are exclusive.** With a curve set, [speed] is written to 1 and
  /// ignored: the curve decides how long the clip is and which source frame is
  /// due when. Setting a flat speed clears the curve. Not an
  /// [AnimatableDouble], for the reason the keyframes section of CLAUDE.md
  /// gives: every keyframed property is read *at* a progress, while speed
  /// decides what progress means — so source time has to be the curve's
  /// integral, which is what [SpeedCurve] is.
  final SpeedCurve? speedCurve;
  final String? transitionType;
  final double? transitionDuration;

  /// How the picture travels through this clip's outgoing transition — one of
  /// the keyframe curves. Null is a straight line, as every transition was
  /// before easing; linear is never stored. Exists only with a transition:
  /// clearing [transitionType] clears it.
  final KeyframeInterpolation? transitionEasing;
  final String? overrideVideoPath;
  final bool isReversed;

  /// The user's pinch scale on top of the automatic contain-fit.
  ///
  /// 1.0 is the plain fit; above it the clip crops toward filling the canvas,
  /// below it shrinks into the background. Distinct from crop/zoom, which
  /// changes what part of the *source* is shown — this changes how the clip
  /// sits *on the canvas*.
  /// An [AnimatableDouble] so a clip can push in across its own length — the
  /// Ken Burns move keyframes were always meant to serve.
  final AnimatableDouble canvasScale;

  /// Where the clip's centre is dragged to, as offsets from the canvas centre
  /// in canvas fractions. Zero is centred.
  final AnimatableDouble canvasOffsetX;
  final AnimatableDouble canvasOffsetY;

  /// The clip's rotation about its own centre, in **degrees**, clockwise.
  ///
  /// Degrees rather than radians because it is what the Transform ruler shows
  /// and what a draft should be readable as; the shader converts once.
  ///
  /// **This did not exist before the Transform sheet.** The old `rotate` tool
  /// was a menu entry with no handler, and the only `rotation` in the contract
  /// belonged to overlays. A clip's own angle is the sixth keyframable
  /// property, and it goes the full route: model, contract, shader, both
  /// engines, export.
  final AnimatableDouble canvasRotation;

  /// This clip's own crop, as fractions of its source frame.
  ///
  /// **Freehand only, and per clip.** There is no ratio: a per-clip ratio would
  /// fight the project canvas every clip is fitted into. It composes *inside*
  /// the project's crop (`composeCropRects`), so cropping a clip to its middle
  /// half means the middle half of what the project already shows.
  ///
  /// **A plain [Rect], deliberately not animatable.** An animated crop is a
  /// pan-and-scan — a real feature with its own design, and four coupled
  /// numbers rather than one parameter. It does not belong to the diamond.
  ///
  /// Fractions, like every other geometry here, so a trimmed or differently
  /// sized source keeps its crop and a draft renders identically on any device.
  final Rect cropRect;

  /// Mirrored across its own vertical axis (left for right) and horizontal
  /// axis (top for bottom).
  ///
  /// **Not a rotation.** Turning a picture 180° puts it upside down *and*
  /// back to front; a mirror does only the second, which is what selfie
  /// footage wants. Applied to the fitted coordinate in the shader before the
  /// content rect, so the picture mirrors inside its own frame and the frame
  /// stays where it sits on the canvas. Plain booleans, deliberately not
  /// animatable: half a mirror is not a picture.
  final bool flipHorizontal;
  final bool flipVertical;

  /// How present the clip is, 0..1. The seventh keyframable property.
  ///
  /// **A mix toward the letterbox fill in the engine, never alpha.** The clip
  /// pass has no blending and the fill is already what shows around a clip,
  /// so an alpha would be a value nothing reads. Applied after the clip's own
  /// grade (fading what the user sees) and before the effect chain (a blurred
  /// clip at 50% is a blurred clip, half-present). Clamped where resolved,
  /// because a keyframe can overshoot.
  final AnimatableDouble opacity;

  /// This clip's own brightness / contrast / saturation / temperature.
  ///
  /// Composed into [colorMatrix] **after** the clip's filter, so it rides the
  /// per-lane grade the engine already applies before a transition blends —
  /// no shader of its own. Independent of the project's adjustments: the two
  /// levels may coexist, unlike filters.
  final ColorAdjustments adjustments;

  /// This clip's mask: a window over the picture, outside which the letterbox
  /// fill shows through. Authored in fractions of the fitted frame, like the
  /// crop rect. See `logic/mask/clip_mask.dart`.
  final ClipMask mask;

  /// Which of this clip's pixels are dropped for the background to show
  /// through, keyed on colour. The mask's sibling — both are a coverage that
  /// multiplies into the same mix toward the letterbox fill — and off on every
  /// clip nobody has keyed.
  final ChromaKey chromaKey;

  /// Whether this clip carries a crop of its own.
  bool get isCropped => cropRect != kFullFrameRect;

  /// Colour filter on this clip alone, as a [FilterPresets] id.
  ///
  /// Null means the clip is ungraded — which is not the same as ungraded
  /// output, because the project may still carry a filter of its own
  /// (`VideoEditorState.selectedFilter`) that is applied to the finished frame.
  /// A clip filter is applied to the clip *before* a transition blends it, so
  /// two clips with different looks cross-fade between those looks.
  final String? filterId;
  final double filterIntensity;

  VideoSegment({
    required this.id,
    this.assetId = '',
    required this.sourceStart,
    required this.sourceEnd,
    this.volume = kUnitParameter,
    this.speed = 1.0,
    this.speedCurve,
    this.transitionType,
    this.transitionDuration,
    this.transitionEasing,
    this.overrideVideoPath,
    this.isReversed = false,
    this.filterId,
    this.filterIntensity = 1.0,
    this.canvasScale = kUnitParameter,
    this.canvasOffsetX = kZeroParameter,
    this.canvasOffsetY = kZeroParameter,
    this.canvasRotation = kZeroParameter,
    this.cropRect = kFullFrameRect,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.opacity = kUnitParameter,
    this.adjustments = ColorAdjustments.none,
    this.mask = ClipMask.none,
    this.chromaKey = ChromaKey.none,
  });

  /// Timeline length. A curve decides it through its integral — the source
  /// span times [SpeedCurve.durationFactor] — and a flat speed by division.
  double get duration {
    final span = sourceEnd - sourceStart;
    final curve = speedCurve;
    return curve == null ? span / speed : span * curve.durationFactor;
  }

  /// This clip's 0..1 position at a timeline instant, given where it starts.
  ///
  /// **Whole-clip, and the same for every keyframable property.** A diamond is
  /// one instant of the clip, so every property has to measure progress the
  /// same way — otherwise one diamond would sit at two different places
  /// depending on which property was asked.
  ///
  /// Distinct from the effect clock. [VideoEffect.introSeconds] makes an
  /// effect's `uProgress` run over its opening window and then rest at 1; that
  /// is the *effect's* clock, a different quantity that happens to share a
  /// range. Resolving a keyframe against it would put a clip's diamonds
  /// somewhere the timeline never drew them.
  ///
  /// [duration] already divides by speed, so a sped-up clip's keyframes stay
  /// where they were placed on the timeline rather than sliding out from under
  /// the edit.
  ///
  /// A zero-length clip is 0, not a division by zero: a clip with no length is
  /// already over, and NaN here would reach a shader uniform.
  double clipProgressAt(double timelineSeconds, double timelineStart) {
    final d = duration;
    if (d <= 0) return 0.0;
    return ((timelineSeconds - timelineStart) / d).clamp(0.0, 1.0).toDouble();
  }

  /// This clip's gain at [progress] (0..1 through the clip).
  double volumeAt(double progress) => volume.resolveAt(progress);

  /// The pinch scale at [progress].
  double canvasScaleAt(double progress) => canvasScale.resolveAt(progress);

  /// How present the clip is at [progress], clamped to 0..1.
  double opacityAt(double progress) =>
      opacity.resolveAt(progress).clamp(0.0, 1.0).toDouble();

  /// The drag offsets at [progress].
  double canvasOffsetXAt(double progress) => canvasOffsetX.resolveAt(progress);
  double canvasOffsetYAt(double progress) => canvasOffsetY.resolveAt(progress);

  /// The rotation at [progress], in degrees.
  double canvasRotationAt(double progress) => canvasRotation.resolveAt(progress);

  /// Whether this clip carries any keyframe at all, on any property.
  ///
  /// Three things ask: the timeline, before drawing diamonds; the composer,
  /// before allowing a merge (a curve is measured across *a clip*, so a merged
  /// media item would resolve one curve over the pair); and the notifier's edit
  /// rule, before deciding whether an edit writes a base value or a keyframe.
  ///
  /// **An envelope is not a keyframe.** A parameter can be `isAnimated` through
  /// an envelope the catalog gave it while the user has placed nothing, and in
  /// that state the plus button must still behave as though the clip were
  /// untouched.
  bool get hasKeyframes =>
      canvasScale.keyframes.isNotEmpty ||
      canvasOffsetX.keyframes.isNotEmpty ||
      canvasOffsetY.keyframes.isNotEmpty ||
      canvasRotation.keyframes.isNotEmpty ||
      volume.keyframes.isNotEmpty ||
      opacity.keyframes.isNotEmpty;

  /// Source position [secondsIntoClip] seconds into this clip's span on the
  /// timeline.
  ///
  /// This is the same mapping playback uses, so anything laid out with it —
  /// the filmstrip especially — stays aligned to the playhead through trims,
  /// speed changes, reversal, and transition overlaps.
  double sourceAtOffset(double secondsIntoClip) {
    final span = sourceEnd - sourceStart;
    final into = secondsIntoClip.clamp(0.0, duration).toDouble();
    final curve = speedCurve;
    // A curve inverts its integral; a flat speed is the product it always
    // was. Both give source seconds in **play order**, which reversal then
    // mirrors — so a curve's `x = 0` is what plays first either way.
    final offset = curve == null
        ? into * speed
        : (span <= 0 ? 0.0 : curve.sourceAtTime(into / span) * span);
    final source = isReversed ? sourceEnd - offset : sourceStart + offset;
    return source.clamp(sourceStart, sourceEnd).toDouble();
  }

  /// Playback rate [secondsIntoClip] into the clip — the flat [speed], or the
  /// curve's value at the source frame due there.
  double speedAtOffset(double secondsIntoClip) {
    final curve = speedCurve;
    if (curve == null) return speed;
    final span = sourceEnd - sourceStart;
    if (span <= 0) return 1.0;
    final into = secondsIntoClip.clamp(0.0, duration).toDouble();
    return curve.speedAtSource(curve.sourceAtTime(into / span));
  }

  VideoSegment copyWith({
    String? id,
    String? assetId,
    double? sourceStart,
    double? sourceEnd,
    AnimatableDouble? volume,
    double? speed,
    SpeedCurve? speedCurve,
    bool clearSpeedCurve = false,
    String? transitionType,
    bool clearTransitionType = false,
    double? transitionDuration,
    bool clearTransitionDuration = false,
    KeyframeInterpolation? transitionEasing,
    bool clearTransitionEasing = false,
    String? overrideVideoPath,
    bool clearOverrideVideoPath = false,
    bool? isReversed,
    String? filterId,
    bool clearFilterId = false,
    double? filterIntensity,
    AnimatableDouble? canvasScale,
    AnimatableDouble? canvasOffsetX,
    AnimatableDouble? canvasOffsetY,
    AnimatableDouble? canvasRotation,
    Rect? cropRect,
    bool? flipHorizontal,
    bool? flipVertical,
    AnimatableDouble? opacity,
    ColorAdjustments? adjustments,
    ClipMask? mask,
    ChromaKey? chromaKey,
  }) {
    return VideoSegment(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      sourceStart: sourceStart ?? this.sourceStart,
      sourceEnd: sourceEnd ?? this.sourceEnd,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      speedCurve: clearSpeedCurve ? null : (speedCurve ?? this.speedCurve),
      transitionType: clearTransitionType ? null : (transitionType ?? this.transitionType),
      transitionDuration: clearTransitionDuration ? null : (transitionDuration ?? this.transitionDuration),
      transitionEasing: clearTransitionEasing || clearTransitionType
          ? null
          : (transitionEasing ?? this.transitionEasing),
      overrideVideoPath: clearOverrideVideoPath ? null : (overrideVideoPath ?? this.overrideVideoPath),
      isReversed: isReversed ?? this.isReversed,
      filterId: clearFilterId ? null : (filterId ?? this.filterId),
      filterIntensity: filterIntensity ?? this.filterIntensity,
      canvasScale: canvasScale ?? this.canvasScale,
      canvasOffsetX: canvasOffsetX ?? this.canvasOffsetX,
      canvasOffsetY: canvasOffsetY ?? this.canvasOffsetY,
      canvasRotation: canvasRotation ?? this.canvasRotation,
      cropRect: cropRect ?? this.cropRect,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      opacity: opacity ?? this.opacity,
      adjustments: adjustments ?? this.adjustments,
      mask: mask ?? this.mask,
      chromaKey: chromaKey ?? this.chromaKey,
    );
  }

  /// Everything that grades this clip — its filter, then its adjustments — as
  /// one 4×5 matrix, or null when neither is set. **This** is what the clip
  /// sends the engine; [filterMatrix] alone is the filter for the sheet's
  /// tiles.
  List<double>? get colorMatrix {
    final filter = filterMatrix;
    if (adjustments.isIdentity) return filter;
    if (filter == null) return adjustments.matrix;
    return composeColorMatrices(adjustments.matrix, filter);
  }

  /// This clip's own grade as a 4×5 `ColorFilter.matrix`, or null if ungraded.
  List<double>? get filterMatrix {
    final preset = FilterPresets.byId(filterId);
    if (preset == null) return null;
    return preset.getInterpolatedMatrix(filterIntensity);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'assetId': assetId,
      'sourceStart': sourceStart,
      'sourceEnd': sourceEnd,
      // Bare numbers while nothing animates them, maps once something does —
      // see [AnimatableDouble.toJson]. So a clip nobody has keyframed writes
      // these fields exactly as it always has.
      'volume': volume.toJson(),
      'speed': speed,
      // Only when set, so a project nobody ramped writes what it always wrote.
      if (speedCurve != null) 'speedCurve': speedCurve!.toJson(),
      'transitionType': transitionType,
      'transitionDuration': transitionDuration,
      // Only when eased, so every draft without a curve is what it always was.
      if (transitionEasing != null) 'transitionEasing': transitionEasing!.name,
      'overrideVideoPath': overrideVideoPath,
      'isReversed': isReversed,
      'filterId': filterId,
      'filterIntensity': filterIntensity,
      'canvasScale': canvasScale.toJson(),
      'canvasOffsetX': canvasOffsetX.toJson(),
      'canvasOffsetY': canvasOffsetY.toJson(),
      'canvasRotation': canvasRotation.toJson(),
      'opacity': opacity.toJson(),
      // `[l, t, w, h]`, the shape the draft already uses for the project crop.
      // Omitted entirely for an uncropped clip, so a project that never
      // cropped a clip writes exactly what it always wrote.
      if (isCropped)
        'cropRect': [cropRect.left, cropRect.top, cropRect.width, cropRect.height],
      // Only when set: a project nobody mirrored writes what it always wrote.
      if (flipHorizontal) 'flipHorizontal': true,
      if (flipVertical) 'flipVertical': true,
      // Omitted while untouched, so a project nobody adjusted writes what it
      // always wrote.
      if (!adjustments.isIdentity) 'adjustments': adjustments.toJson(),
      if (!mask.isNone) 'mask': mask.toJson(),
      // Omitted while off, so a project nobody keyed writes what it always
      // wrote.
      if (!chromaKey.isNone) 'chromaKey': chromaKey.toJson(),
    };
  }

  /// A `[l, t, w, h]` list, or the full frame for anything else — absent,
  /// short, or junk. A malformed crop costs the clip its crop, never the
  /// project.
  static Rect _rectFromJson(Object? raw) {
    if (raw is! List || raw.length < 4) return kFullFrameRect;
    final v = <double>[];
    for (final e in raw.take(4)) {
      if (e is! num) return kFullFrameRect;
      v.add(e.toDouble());
    }
    if (v[2] <= 0 || v[3] <= 0) return kFullFrameRect;
    return Rect.fromLTWH(v[0], v[1], v[2], v[3]);
  }

  factory VideoSegment.fromJson(Map<String, dynamic> json) {
    return VideoSegment(
      id: json['id'] as String,
      // Absent in drafts saved before multi-asset projects; the loader
      // reassigns those to the migrated asset.
      assetId: json['assetId'] as String? ?? '',
      sourceStart: (json['sourceStart'] as num).toDouble(),
      sourceEnd: (json['sourceEnd'] as num).toDouble(),
      // Every draft written before keyframes holds a bare number here.
      // `fromJson` takes `dynamic` for exactly that: a number loads flat, a map
      // loads fully, and anything else falls back rather than throwing.
      volume: AnimatableDouble.fromJson(json['volume'], fallback: 1.0),
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      // Absent in every draft written before speed could ramp; junk reads as
      // no curve rather than a throw.
      speedCurve: SpeedCurve.fromJson(json['speedCurve']),
      transitionType: json['transitionType'] as String?,
      transitionDuration: (json['transitionDuration'] as num?)?.toDouble(),
      transitionEasing: _transitionEasingFromJson(json['transitionEasing']),
      overrideVideoPath: json['overrideVideoPath'] as String?,
      isReversed: json['isReversed'] as bool? ?? false,
      // Absent in drafts saved before clips could carry their own filter.
      filterId: json['filterId'] as String?,
      filterIntensity: (json['filterIntensity'] as num?)?.toDouble() ?? 1.0,
      // A draft from before the effects track also holds `effectId` and
      // `effectIntensity` here. They are not a clip's any more:
      // `migrateClipEffects` turns them into effect bars on load, and the
      // clip reads past them.
      canvasScale: AnimatableDouble.fromJson(json['canvasScale'], fallback: 1.0),
      canvasOffsetX:
          AnimatableDouble.fromJson(json['canvasOffsetX'], fallback: 0.0),
      canvasOffsetY:
          AnimatableDouble.fromJson(json['canvasOffsetY'], fallback: 0.0),
      // Absent in every draft written before clips could rotate.
      canvasRotation:
          AnimatableDouble.fromJson(json['canvasRotation'], fallback: 0.0),
      cropRect: _rectFromJson(json['cropRect']),
      // `== true`, so junk of any type reads as unflipped.
      flipHorizontal: json['flipHorizontal'] == true,
      flipVertical: json['flipVertical'] == true,
      // Absent in every draft written before clips could fade.
      opacity: AnimatableDouble.fromJson(json['opacity'], fallback: 1.0),
      adjustments: ColorAdjustments.fromJson(json['adjustments']),
      mask: ClipMask.fromJson(json['mask']),
      // Absent in every draft written before clips could be keyed; junk reads
      // as no key rather than a throw.
      chromaKey: ChromaKey.fromJson(json['chromaKey']),
    );
  }
}

/// A stored transition curve, or null for a straight line — absent, linear,
/// or a name this build cannot read (which [keyframeInterpolationByName]
/// already reads as linear).
KeyframeInterpolation? _transitionEasingFromJson(Object? name) {
  final easing = keyframeInterpolationByName(name);
  return easing == KeyframeInterpolation.linear ? null : easing;
}
