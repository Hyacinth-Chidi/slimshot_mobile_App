import 'dart:convert';

class DraftProject {
  final String id;
  final String sourceVideoPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double durationSeconds;
  final String? thumbnailPath;
  
  // Serialized editor state
  final List<Map<String, dynamic>> segments;
  final List<Map<String, dynamic>> textOverlays;
  final List<Map<String, dynamic>> imageOverlays;
  final List<Map<String, dynamic>> videoOverlays;
  final List<Map<String, dynamic>> audioTracks;
  
  // Crop & filter
  final String selectedRatioName;
  final List<double> customCropRect; // [l, t, w, h]
  final double videoScale;
  final double videoPanX;
  final double videoPanY;
  final String? filterName;
  final double filterIntensity;
  
  // Background
  final String backgroundType;
  final int backgroundColorValue;
  final double backgroundBlurIntensity;
  
  final bool isMuted;

  const DraftProject({
    required this.id,
    required this.sourceVideoPath,
    required this.createdAt,
    required this.updatedAt,
    required this.durationSeconds,
    this.thumbnailPath,
    required this.segments,
    required this.textOverlays,
    required this.imageOverlays,
    required this.videoOverlays,
    required this.audioTracks,
    required this.selectedRatioName,
    required this.customCropRect,
    required this.videoScale,
    required this.videoPanX,
    required this.videoPanY,
    this.filterName,
    required this.filterIntensity,
    required this.backgroundType,
    required this.backgroundColorValue,
    required this.backgroundBlurIntensity,
    required this.isMuted,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceVideoPath': sourceVideoPath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'durationSeconds': durationSeconds,
      'thumbnailPath': thumbnailPath,
      'segments': segments,
      'textOverlays': textOverlays,
      'imageOverlays': imageOverlays,
      'videoOverlays': videoOverlays,
      'audioTracks': audioTracks,
      'selectedRatioName': selectedRatioName,
      'customCropRect': customCropRect,
      'videoScale': videoScale,
      'videoPanX': videoPanX,
      'videoPanY': videoPanY,
      'filterName': filterName,
      'filterIntensity': filterIntensity,
      'backgroundType': backgroundType,
      'backgroundColorValue': backgroundColorValue,
      'backgroundBlurIntensity': backgroundBlurIntensity,
      'isMuted': isMuted,
    };
  }

  factory DraftProject.fromJson(Map<String, dynamic> json) {
    return DraftProject(
      id: json['id'] as String,
      sourceVideoPath: json['sourceVideoPath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      thumbnailPath: json['thumbnailPath'] as String?,
      segments: List<Map<String, dynamic>>.from(json['segments'] as List? ?? []),
      textOverlays: List<Map<String, dynamic>>.from(json['textOverlays'] as List? ?? []),
      imageOverlays: List<Map<String, dynamic>>.from(json['imageOverlays'] as List? ?? []),
      videoOverlays: List<Map<String, dynamic>>.from(json['videoOverlays'] as List? ?? []),
      audioTracks: List<Map<String, dynamic>>.from(json['audioTracks'] as List? ?? []),
      selectedRatioName: json['selectedRatioName'] as String? ?? 'custom',
      customCropRect: (json['customCropRect'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0, 1.0, 1.0],
      videoScale: (json['videoScale'] as num?)?.toDouble() ?? 1.0,
      videoPanX: (json['videoPanX'] as num?)?.toDouble() ?? 0.0,
      videoPanY: (json['videoPanY'] as num?)?.toDouble() ?? 0.0,
      filterName: json['filterName'] as String?,
      filterIntensity: (json['filterIntensity'] as num?)?.toDouble() ?? 1.0,
      backgroundType: json['backgroundType'] as String? ?? 'black',
      backgroundColorValue: json['backgroundColorValue'] as int? ?? 0xFF000000,
      backgroundBlurIntensity: (json['backgroundBlurIntensity'] as num?)?.toDouble() ?? 20.0,
      isMuted: json['isMuted'] as bool? ?? false,
    );
  }
}
