import 'package:flutter/material.dart';

/// A speed of 1 runs an animation at the catalog's own natural duration.
const double kTextAnimationNaturalSpeed = 1.0;

/// The slowest and fastest an animation may be driven.
///
/// Past 3× a staggered animation is over before the eye resolves the stagger;
/// below 0.5× a flat half-second fade takes a full second, which on a short
/// overlay is most of its life.
const double kMinTextAnimationSpeed = 0.5;
const double kMaxTextAnimationSpeed = 3.0;

/// The version of the animation fields in a persisted [TextOverlayModel].
///
/// Schema 0 — the absent marker — means `animationInDuration` and
/// `animationOutDuration` hold **durations in seconds**, as every draft written
/// before the animation catalog does. Schema 1 means they hold **speeds**.
///
/// A version marker rather than a heuristic, because the two ranges overlap:
/// old durations ran 0.1–2.0s and speeds run 0.5–3.0, so a stored `1.5` is a
/// perfectly ordinary member of both and no amount of inspection can tell them
/// apart. Guessing would silently retime a project the user already made.
const int kTextAnimationSchema = 1;

class TextOverlayModel {
  final String id;
  String text;
  Color color;
  String fontFamily;
  
  // Advanced Style
  Color backgroundColor;
  Color strokeColor;
  double strokeWidth;
  Color shadowColor;
  double shadowBlurRadius;
  double borderRadius;
  double backgroundPadding;
  String textAlign;
  
  // Matrix/Position
  Offset position;
  double scale;
  double rotation;
  double? boxWidth;
  
  // Timing
  Duration startTime;
  Duration endTime;
  
  // Layering
  int laneIndex;
  
  // Animation: a `text_animation_catalog.dart` id, or 'none'. Legacy drafts
  // also hold 'fade' and 'scale', which resolve **by slot** — see
  // `resolveTextAnimation`.
  String inAnimation;
  String outAnimation;

  /// An animation that repeats for the whole span — a catalog id, or 'none'.
  ///
  /// Independent of [inAnimation]/[outAnimation]: a loop runs underneath both,
  /// so text can enter, settle into a wave, and leave.
  String loopAnimation;

  /// **Speed multipliers, despite the names.**
  ///
  /// The names are historical. These fields held an animation's *duration in
  /// seconds* before the catalog existed; they now hold a dimensionless speed
  /// (0.5–3.0, 1.0 natural) that **divides** the catalog's own duration, which
  /// is resolved from the animation and the glyph count. Renaming them would be
  /// a second migration stacked on the one [animationSchema] already performs,
  /// so the keys stay and the meaning is documented here.
  ///
  /// [animationInDuration] and [animationOutDuration] are expected to be equal
  /// — the animation tab is a single Speed slider — and the Kotlin port
  /// deliberately resolves both windows from one of them, because the
  /// proportional compression that fits them into a short span is a single rule
  /// that must not exist twice across the boundary.
  double animationInDuration;
  double animationOutDuration;

  /// A loop's period divides by this. Genuinely independent of the in/out
  /// speed: a cycle length is no part of the in/out compression.
  double loopSpeed;


  // To lock coordinate proportions regardless of flutter layout resizing
  Size? referenceCanvasSize;

  TextOverlayModel({
    required this.id,
    required this.text,
    this.color = Colors.white,
    this.fontFamily = 'Roboto',
    this.backgroundColor = Colors.transparent,
    this.strokeColor = Colors.transparent,
    this.strokeWidth = 0.0,
    this.shadowColor = Colors.transparent,
    this.shadowBlurRadius = 0.0,
    this.borderRadius = 16.0,
    this.backgroundPadding = 16.0,
    this.textAlign = 'center',
    this.position = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.boxWidth,
    this.startTime = Duration.zero,
    this.endTime = const Duration(seconds: 5), // default 5 seconds
    this.inAnimation = 'none',
    this.outAnimation = 'none',
    this.loopAnimation = 'none',
    this.animationInDuration = kTextAnimationNaturalSpeed,
    this.animationOutDuration = kTextAnimationNaturalSpeed,
    this.loopSpeed = kTextAnimationNaturalSpeed,
    this.laneIndex = 0,
    this.referenceCanvasSize,
  });

  TextOverlayModel copyWith({
    String? id,
    String? text,
    Color? color,
    String? fontFamily,
    Color? backgroundColor,
    Color? strokeColor,
    double? strokeWidth,
    Color? shadowColor,
    double? shadowBlurRadius,
    double? borderRadius,
    double? backgroundPadding,
    String? textAlign,
    Offset? position,
    double? scale,
    double? rotation,
    double? boxWidth,
    Duration? startTime,
    Duration? endTime,
    String? inAnimation,
    String? outAnimation,
    String? loopAnimation,
    double? animationInDuration,
    double? animationOutDuration,
    double? loopSpeed,
    int? laneIndex,
    Size? referenceCanvasSize,
  }) {
    return TextOverlayModel(
      id: id ?? this.id,
      text: text ?? this.text,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowBlurRadius: shadowBlurRadius ?? this.shadowBlurRadius,
      borderRadius: borderRadius ?? this.borderRadius,
      backgroundPadding: backgroundPadding ?? this.backgroundPadding,
      textAlign: textAlign ?? this.textAlign,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      boxWidth: boxWidth ?? this.boxWidth,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      inAnimation: inAnimation ?? this.inAnimation,
      outAnimation: outAnimation ?? this.outAnimation,
      loopAnimation: loopAnimation ?? this.loopAnimation,
      animationInDuration: animationInDuration ?? this.animationInDuration,
      animationOutDuration: animationOutDuration ?? this.animationOutDuration,
      loopSpeed: loopSpeed ?? this.loopSpeed,
      laneIndex: laneIndex ?? this.laneIndex,
      referenceCanvasSize: referenceCanvasSize ?? this.referenceCanvasSize,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'color': color.value,
      'fontFamily': fontFamily,
      'backgroundColor': backgroundColor.value,
      'strokeColor': strokeColor.value,
      'strokeWidth': strokeWidth,
      'shadowColor': shadowColor.value,
      'shadowBlurRadius': shadowBlurRadius,
      'borderRadius': borderRadius,
      'backgroundPadding': backgroundPadding,
      'textAlign': textAlign,
      'positionX': position.dx,
      'positionY': position.dy,
      'scale': scale,
      'rotation': rotation,
      'boxWidth': boxWidth,
      'startTimeMs': startTime.inMilliseconds,
      'endTimeMs': endTime.inMilliseconds,
      'inAnimation': inAnimation,
      'outAnimation': outAnimation,
      'loopAnimation': loopAnimation,
      // Speeds, not seconds — see the field docs. The marker is what says so;
      // written unconditionally, so a draft this build saves is never read back
      // through the schema-0 migration.
      'animationSchema': kTextAnimationSchema,
      'animationInDuration': animationInDuration,
      'animationOutDuration': animationOutDuration,
      'loopSpeed': loopSpeed,
      'laneIndex': laneIndex,
      'refWidth': referenceCanvasSize?.width,
      'refHeight': referenceCanvasSize?.height,
    };
  }

  /// A persisted animation speed, migrated if the draft predates speeds.
  ///
  /// At schema 0 the stored number is a *duration* and is **discarded** rather
  /// than converted. That is not a shortcut: nothing ever drew it. The old
  /// preview played flutter_animate's stock 0.5s and the composer hardcoded 0.5
  /// on the way to the exporter, so the stored duration was already inert in
  /// both consumers. Mapping it to the natural speed is therefore exactly
  /// faithful — the project keeps the pace it has always played at — where
  /// converting it would change how an existing draft looks on open.
  static double _speedFrom(Map<String, dynamic> json, String key, int schema) {
    if (schema < kTextAnimationSchema) return kTextAnimationNaturalSpeed;
    final stored = (json[key] as num?)?.toDouble();
    if (stored == null) return kTextAnimationNaturalSpeed;
    return stored.clamp(kMinTextAnimationSpeed, kMaxTextAnimationSpeed);
  }

  factory TextOverlayModel.fromJson(Map<String, dynamic> json) {
    Size? refSize;
    if (json['refWidth'] != null && json['refHeight'] != null) {
      refSize = Size((json['refWidth'] as num).toDouble(), (json['refHeight'] as num).toDouble());
    }

    // Absent means 0 — a draft from before speeds existed. A schema *newer*
    // than this build's still reads its speeds as speeds: the fields would only
    // gain a third meaning through another migration, and discarding a value a
    // later build wrote would be worse than reading it.
    final schema = (json['animationSchema'] as num?)?.toInt() ?? 0;


    return TextOverlayModel(
      id: json['id'] as String,
      text: json['text'] as String,
      color: json['color'] != null ? Color(json['color'] as int) : Colors.white,
      fontFamily: json['fontFamily'] as String? ?? 'Roboto',
      backgroundColor: json['backgroundColor'] != null ? Color(json['backgroundColor'] as int) : Colors.transparent,
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : Colors.transparent,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 0.0,
      shadowColor: json['shadowColor'] != null ? Color(json['shadowColor'] as int) : Colors.transparent,
      shadowBlurRadius: (json['shadowBlurRadius'] as num?)?.toDouble() ?? 0.0,
      borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 16.0,
      backgroundPadding: (json['backgroundPadding'] as num?)?.toDouble() ?? 16.0,
      textAlign: json['textAlign'] as String? ?? 'center',
      position: Offset(
        (json['positionX'] as num?)?.toDouble() ?? 0.0,
        (json['positionY'] as num?)?.toDouble() ?? 0.0,
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      boxWidth: (json['boxWidth'] as num?)?.toDouble(),
      startTime: Duration(milliseconds: json['startTimeMs'] as int? ?? 0),
      endTime: Duration(milliseconds: json['endTimeMs'] as int? ?? 5000),
      inAnimation: json['inAnimation'] as String? ?? 'none',
      outAnimation: json['outAnimation'] as String? ?? 'none',
      loopAnimation: json['loopAnimation'] as String? ?? 'none',
      animationInDuration: _speedFrom(json, 'animationInDuration', schema),
      animationOutDuration: _speedFrom(json, 'animationOutDuration', schema),
      // The loop is new in schema 1, so an old draft cannot hold one; reading
      // it through the same helper keeps the clamp in exactly one place.
      loopSpeed: _speedFrom(json, 'loopSpeed', schema),
      laneIndex: json['laneIndex'] as int? ?? 0,
      referenceCanvasSize: refSize,
    );
  }
}

