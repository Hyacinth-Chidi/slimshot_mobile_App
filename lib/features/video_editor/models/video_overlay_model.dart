import 'package:flutter/material.dart';

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
    );
  }
}
