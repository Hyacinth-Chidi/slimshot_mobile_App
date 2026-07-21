import 'package:flutter/material.dart';

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
  
  // Animation: 'none', 'fade', 'slide_left', 'slide_right', 'slide_up', 'slide_down', 'scale'
  String inAnimation;
  String outAnimation;
  double animationInDuration;
  double animationOutDuration;
  
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
    this.animationInDuration = 0.5,
    this.animationOutDuration = 0.5,
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
    double? animationInDuration,
    double? animationOutDuration,
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
      animationInDuration: animationInDuration ?? this.animationInDuration,
      animationOutDuration: animationOutDuration ?? this.animationOutDuration,
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
      'animationInDuration': animationInDuration,
      'animationOutDuration': animationOutDuration,
      'laneIndex': laneIndex,
      'refWidth': referenceCanvasSize?.width,
      'refHeight': referenceCanvasSize?.height,
    };
  }

  factory TextOverlayModel.fromJson(Map<String, dynamic> json) {
    Size? refSize;
    if (json['refWidth'] != null && json['refHeight'] != null) {
      refSize = Size((json['refWidth'] as num).toDouble(), (json['refHeight'] as num).toDouble());
    }
    
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
      animationInDuration: (json['animationInDuration'] as num?)?.toDouble() ?? 0.5,
      animationOutDuration: (json['animationOutDuration'] as num?)?.toDouble() ?? 0.5,
      laneIndex: json['laneIndex'] as int? ?? 0,
      referenceCanvasSize: refSize,
    );
  }
}

