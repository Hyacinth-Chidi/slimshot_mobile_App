import 'package:flutter/material.dart';
import '../logic/chroma/chroma_key.dart';
import '../logic/mask/clip_mask.dart';

class VideoOverlayModel {
  final String id;
  final String videoPath;
  
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
  
  // Timeline Timing (Where it sits on the editor timeline)
  Duration timelineStart;
  Duration timelineEnd;
  
  // Source Trimming (Which part of the raw video is used)
  double sourceStart;
  double sourceEnd;

  // Audio & Speed
  double volume;
  double speed;
  bool isMuted;

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

  VideoOverlayModel({
    required this.id,
    required this.videoPath,
    this.position = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.animationIn,
    this.animationOut,
    this.animationInDuration = 0.5,
    this.animationOutDuration = 0.5,
    this.timelineStart = Duration.zero,
    this.timelineEnd = const Duration(seconds: 5), // default 5 seconds
    this.sourceStart = 0.0,
    this.sourceEnd = 5.0, // default 5 seconds
    this.volume = 1.0,
    this.speed = 1.0,
    this.isMuted = false,
    this.laneIndex = 0,
    this.mask = ClipMask.none,
    this.chromaKey = ChromaKey.none,
  });

  VideoOverlayModel copyWith({
    String? id,
    String? videoPath,
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
    Duration? timelineStart,
    Duration? timelineEnd,
    double? sourceStart,
    double? sourceEnd,
    double? volume,
    double? speed,
    bool? isMuted,
    int? laneIndex,
    ClipMask? mask,
    ChromaKey? chromaKey,
  }) {
    return VideoOverlayModel(
      id: id ?? this.id,
      videoPath: videoPath ?? this.videoPath,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      animationIn: clearAnimationIn ? null : (animationIn ?? this.animationIn),
      animationOut: clearAnimationOut ? null : (animationOut ?? this.animationOut),
      animationInDuration: animationInDuration ?? this.animationInDuration,
      animationOutDuration: animationOutDuration ?? this.animationOutDuration,
      timelineStart: timelineStart ?? this.timelineStart,
      timelineEnd: timelineEnd ?? this.timelineEnd,
      sourceStart: sourceStart ?? this.sourceStart,
      sourceEnd: sourceEnd ?? this.sourceEnd,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      isMuted: isMuted ?? this.isMuted,
      laneIndex: laneIndex ?? this.laneIndex,
      mask: mask ?? this.mask,
      chromaKey: chromaKey ?? this.chromaKey,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'videoPath': videoPath,
      'positionX': position.dx,
      'positionY': position.dy,
      'scale': scale,
      'rotation': rotation,
      'opacity': opacity,
      'animationIn': animationIn,
      'animationOut': animationOut,
      'animationInDuration': animationInDuration,
      'animationOutDuration': animationOutDuration,
      'timelineStartMs': timelineStart.inMilliseconds,
      'timelineEndMs': timelineEnd.inMilliseconds,
      'sourceStart': sourceStart,
      'sourceEnd': sourceEnd,
      'volume': volume,
      'speed': speed,
      'isMuted': isMuted,
      'laneIndex': laneIndex,
      // Omitted while unset, as on the image overlay.
      if (!mask.isNone) 'mask': mask.toJson(),
      if (!chromaKey.isNone) 'chromaKey': chromaKey.toJson(),
    };
  }

  factory VideoOverlayModel.fromJson(Map<String, dynamic> json) {
    return VideoOverlayModel(
      id: json['id'] as String,
      videoPath: json['videoPath'] as String,
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
      timelineStart: Duration(milliseconds: json['timelineStartMs'] as int? ?? 0),
      timelineEnd: Duration(milliseconds: json['timelineEndMs'] as int? ?? 5000),
      sourceStart: (json['sourceStart'] as num?)?.toDouble() ?? 0.0,
      sourceEnd: (json['sourceEnd'] as num?)?.toDouble() ?? 5.0,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      isMuted: json['isMuted'] as bool? ?? false,
      laneIndex: json['laneIndex'] as int? ?? 0,
      // Absent in every overlay saved before shapes existed.
      mask: ClipMask.fromJson(json['mask']),
      chromaKey: ChromaKey.fromJson(json['chromaKey']),
    );
  }
}
