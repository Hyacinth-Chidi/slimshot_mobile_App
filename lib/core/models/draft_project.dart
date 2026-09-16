import 'dart:convert';
import '../../features/video_editor/logic/color/color_adjustments.dart';

class DraftProject {
  final String id;
  final String sourceVideoPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double durationSeconds;
  final String? thumbnailPath;
  
  /// Every imported file in the project.
  ///
  /// Empty for drafts written before projects could hold more than one file;
  /// those are migrated on load from [sourceVideoPath] and [durationSeconds].
  final List<Map<String, dynamic>> assets;

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

  /// The project's copy of a background photo; absent from the JSON when none.
  final String? backgroundImagePath;

  /// The project-level Adjust; absent from the JSON while untouched.
  final ColorAdjustments adjustments;
  
  final bool isMuted;

  const DraftProject({
    required this.id,
    required this.sourceVideoPath,
    required this.createdAt,
    required this.updatedAt,
    required this.durationSeconds,
    this.thumbnailPath,
    this.assets = const [],
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
    this.backgroundImagePath,
    this.adjustments = ColorAdjustments.none,
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
      'assets': assets,
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
      if (backgroundImagePath != null) 'backgroundImagePath': backgroundImagePath,
      if (!adjustments.isIdentity) 'adjustments': adjustments.toJson(),
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
      assets: List<Map<String, dynamic>>.from(json['assets'] as List? ?? []),
      segments: List<Map<String, dynamic>>.from(json['segments'] as List? ?? []),
      textOverlays: List<Map<String, dynamic>>.from(json['textOverlays'] as List? ?? []),
      imageOverlays: List<Map<String, dynamic>>.from(json['imageOverlays'] as List? ?? []),
      videoOverlays: List<Map<String, dynamic>>.from(json['videoOverlays'] as List? ?? []),
      audioTracks: List<Map<String, dynamic>>.from(json['audioTracks'] as List? ?? []),
      // A draft predating the ratio feature never had a crop, so it reopens on
      // the 9:16 default rather than the freeform custom path.
      selectedRatioName: json['selectedRatioName'] as String? ?? 'ratio9x16',
      customCropRect: (json['customCropRect'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0, 1.0, 1.0],
      videoScale: (json['videoScale'] as num?)?.toDouble() ?? 1.0,
      videoPanX: (json['videoPanX'] as num?)?.toDouble() ?? 0.0,
      videoPanY: (json['videoPanY'] as num?)?.toDouble() ?? 0.0,
      filterName: json['filterName'] as String?,
      filterIntensity: (json['filterIntensity'] as num?)?.toDouble() ?? 1.0,
      backgroundType: json['backgroundType'] as String? ?? 'black',
      backgroundColorValue: json['backgroundColorValue'] as int? ?? 0xFF000000,
      backgroundBlurIntensity: (json['backgroundBlurIntensity'] as num?)?.toDouble() ?? 20.0,
      backgroundImagePath: json['backgroundImagePath'] as String?,
      adjustments: ColorAdjustments.fromJson(json['adjustments']),
      isMuted: json['isMuted'] as bool? ?? false,
    );
  }
}
