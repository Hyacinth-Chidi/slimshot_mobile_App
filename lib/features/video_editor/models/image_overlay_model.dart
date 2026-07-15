import 'package:flutter/material.dart';

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
    );
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
    );
  }
}
