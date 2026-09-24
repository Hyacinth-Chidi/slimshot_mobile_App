import 'package:flutter/material.dart';
import '../logic/animation/overlay_keyframes.dart';
import '../logic/chroma/chroma_key.dart';
import '../logic/mask/clip_mask.dart';

class ImageOverlayModel {
  final String id;
  final String imagePath;
  
  // Matrix/Position
  Offset position;
  double scale;
  double rotation;
  
  // Advanced Style
  double opacity;
  String? animationIn;
  String? animationOut;
  double animationInDuration;
  double animationOutDuration;
  
  // Timing
  Duration startTime;
  Duration endTime;

  // Layering
  int laneIndex;

  /// The shape this overlay is cut to, or [ClipMask.none].
  ///
  /// **Authored in the overlay's own box**, not in canvas fractions: an
  /// overlay is placed and scaled independently, so a mask measured against
  /// the canvas would slide off the picture the moment the overlay moved. The
  /// same `ClipMask` a clip carries, so a shape means one thing everywhere and
  /// there is one coverage function to keep preview and export agreeing.
  ClipMask mask;

  /// The colour dropped out of this overlay so the picture behind shows
  /// through — the clip's own [ChromaKey], deliberately the same model.
  ///
  /// A green screen means one thing everywhere, and one coverage function is
  /// what keeps the preview and the export agreeing. It could not exist while
  /// the preview drew overlays as Flutter widgets: a key is a per-pixel colour
  /// decision no widget can make, so the export would have dropped the green
  /// while the canvas still showed it. Now both sides run the same shader.
  ChromaKey chromaKey;

  /// Keyframe tracks for [position], [scale], [rotation] and [opacity], which
  /// stay the **base values** beside them — see `overlay_keyframes.dart`.
  /// Empty on every overlay nobody has placed a diamond on.
  OverlayKeyframes keyframes;

  ImageOverlayModel({
    required this.id,
    required this.imagePath,
    this.position = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.animationIn,
    this.animationOut,
    this.animationInDuration = 0.5,
    this.animationOutDuration = 0.5,
    this.startTime = Duration.zero,
    this.endTime = const Duration(seconds: 5), // default 5 seconds
    this.laneIndex = 0,
    this.mask = ClipMask.none,
    this.chromaKey = ChromaKey.none,
    this.keyframes = OverlayKeyframes.none,
  });

  ImageOverlayModel copyWith({
    String? id,
    String? imagePath,
    Offset? position,
    double? scale,
    double? rotation,
    double? opacity,
    String? animationIn,
    String? animationOut,
    bool clearAnimationIn = false,
    bool clearAnimationOut = false,
    double? animationInDuration,
    double? animationOutDuration,
    Duration? startTime,
    Duration? endTime,
    int? laneIndex,
    ClipMask? mask,
    ChromaKey? chromaKey,
    OverlayKeyframes? keyframes,
  }) {
    return ImageOverlayModel(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      animationIn: clearAnimationIn ? null : (animationIn ?? this.animationIn),
      animationOut: clearAnimationOut ? null : (animationOut ?? this.animationOut),
      animationInDuration: animationInDuration ?? this.animationInDuration,
      animationOutDuration: animationOutDuration ?? this.animationOutDuration,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      laneIndex: laneIndex ?? this.laneIndex,
      mask: mask ?? this.mask,
      chromaKey: chromaKey ?? this.chromaKey,
      keyframes: keyframes ?? this.keyframes,
    );
  }

  /// Base placement and keyframe tracks, as one value — see [OverlayMotion].
  OverlayMotion get motion => OverlayMotion(
        position: position,
        scale: scale,
        rotation: rotation,
        opacity: opacity,
        keyframes: keyframes,
      );

  /// This overlay with [m]'s base placement and tracks.
  ImageOverlayModel withMotion(OverlayMotion m) => copyWith(
        position: m.position,
        scale: m.scale,
        rotation: m.rotation,
        opacity: m.opacity,
        keyframes: m.keyframes,
      );

  /// This overlay as it is drawn at [seconds] on the timeline: its placement
  /// resolved through its keyframes — or this very overlay when it has none,
  /// which is every overlay that exists before a diamond is placed.
  ///
  /// **What the canvas draws and what a gesture anchors on.** A gesture that
  /// started from the stored base would jump a keyframed overlay to its base
  /// the moment it was touched.
  ///
  /// **Never write the result back into state.** Its placement fields hold
  /// the values *at* [seconds], not the base; storing it would silently move
  /// the base to wherever the playhead happened to be. Edits go through the
  /// notifier's edit rule.
  ImageOverlayModel shownAt(double seconds) {
    if (keyframes.isEmpty) return this;
    return withMotion(
      motion.at(overlayProgressAt(startTime, endTime, seconds)),
    ).copyWith(keyframes: keyframes);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'positionX': position.dx,
      'positionY': position.dy,
      'scale': scale,
      'rotation': rotation,
      'opacity': opacity,
      'animationIn': animationIn,
      'animationOut': animationOut,
      'animationInDuration': animationInDuration,
      'animationOutDuration': animationOutDuration,
      'startTimeMs': startTime.inMilliseconds,
      'endTimeMs': endTime.inMilliseconds,
      'laneIndex': laneIndex,
      // Omitted while unset, so an overlay nobody masked writes what it
      // always wrote.
      if (!mask.isNone) 'mask': mask.toJson(),
      if (!chromaKey.isNone) 'chromaKey': chromaKey.toJson(),
      if (!keyframes.isEmpty) 'keyframes': keyframes.toJson(),
    };
  }

  factory ImageOverlayModel.fromJson(Map<String, dynamic> json) {
    return ImageOverlayModel(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      position: Offset(
        (json['positionX'] as num?)?.toDouble() ?? 0.0,
        (json['positionY'] as num?)?.toDouble() ?? 0.0,
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      animationIn: json['animationIn'] as String?,
      animationOut: json['animationOut'] as String?,
      animationInDuration: (json['animationInDuration'] as num?)?.toDouble() ?? 0.5,
      animationOutDuration: (json['animationOutDuration'] as num?)?.toDouble() ?? 0.5,
      startTime: Duration(milliseconds: json['startTimeMs'] as int? ?? 0),
      endTime: Duration(milliseconds: json['endTimeMs'] as int? ?? 5000),
      laneIndex: json['laneIndex'] as int? ?? 0,
      // Absent in every overlay saved before shapes existed; junk reads as no
      // mask rather than a throw.
      mask: ClipMask.fromJson(json['mask']),
      chromaKey: ChromaKey.fromJson(json['chromaKey']),
      keyframes: OverlayKeyframes.fromJson(json['keyframes']),
    );
  }
}
