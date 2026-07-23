import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

enum CompressionType { video, image }

enum CompressionMode { preset, targetSize }

class CompressionPreset {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final double quality; // 0.0 - 1.0 (for images)
  final String ffmpegPreset; // for video (ultrafast, veryfast, medium, slow)
  final int targetBitrate; // for video in bps
  final String expectedCompression;
  final bool isPro;

  const CompressionPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.expectedCompression,
    this.quality = 0.8,
    this.ffmpegPreset = 'medium',
    this.targetBitrate = 3000000,
    this.isPro = false,
  });
}

class OutputPreset {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final CompressionType type;
  final String presetId;
  final String? targetFormat;
  final int? targetSizeBytes;
  final bool removeMetadata;
  final bool whatsAppOptimize;

  const OutputPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.type,
    required this.presetId,
    this.targetFormat,
    this.targetSizeBytes,
    this.removeMetadata = true,
    this.whatsAppOptimize = false,
  });
}

/// Video metadata extracted via ffprobe before compression.
class VideoMetadata {
  final int width;
  final int height;
  final int bitrateKbps; // in kbps
  final String codec; // e.g. "h264", "hevc"
  final double durationSecs;

  const VideoMetadata({
    required this.width,
    required this.height,
    required this.bitrateKbps,
    required this.codec,
    required this.durationSecs,
  });

  /// Classify resolution tier.
  String get resolutionTier {
    final maxDim = width > height ? width : height;
    if (maxDim >= 3840) return '4K';
    if (maxDim >= 1920) return '1080p';
    if (maxDim >= 1280) return '720p';
    return 'SD';
  }

  /// Check if the video is already well-optimized
  /// (HEVC codec OR bitrate below the threshold for its resolution).
  bool get isAlreadyOptimized {
    if (codec.toLowerCase().contains('hevc') ||
        codec.toLowerCase().contains('h265') ||
        codec.toLowerCase().contains('hev1')) {
      return true;
    }
    if (bitrateKbps == 0) return false;
    return bitrateKbps < _bitrateThreshold;
  }

  int get _bitrateThreshold {
    switch (resolutionTier) {
      case '4K':
        return 8000;
      case '1080p':
        return 3000;
      case '720p':
        return 1800;
      default:
        return 1200;
    }
  }
}

class CompressionPresets {
  static const List<int> targetImageSizes = [
    500 * 1024,
    1 * 1024 * 1024,
    2 * 1024 * 1024,
    5 * 1024 * 1024,
  ];

  static const List<int> targetVideoSizes = [
    5 * 1024 * 1024,
    10 * 1024 * 1024,
    16 * 1024 * 1024,
    25 * 1024 * 1024,
  ];

  static const List<OutputPreset> imageOutputPresets = [
    OutputPreset(
      id: 'form_upload',
      name: 'Form Upload',
      description: 'JPG under 1 MB',
      icon: LucideIcons.fileText,
      type: CompressionType.image,
      presetId: 'smart',
      targetFormat: 'jpg',
      targetSizeBytes: 1 * 1024 * 1024,
    ),
    OutputPreset(
      id: 'email',
      name: 'Email',
      description: 'JPG under 2 MB',
      icon: LucideIcons.mail,
      type: CompressionType.image,
      presetId: 'smart',
      targetFormat: 'jpg',
      targetSizeBytes: 2 * 1024 * 1024,
    ),
    OutputPreset(
      id: 'profile_photo',
      name: 'Profile',
      description: 'WebP under 500 KB',
      icon: LucideIcons.user,
      type: CompressionType.image,
      presetId: 'smallest',
      targetFormat: 'webp',
      targetSizeBytes: 500 * 1024,
    ),
    OutputPreset(
      id: 'privacy_share',
      name: 'Privacy Share',
      description: 'Clean metadata, balanced JPG',
      icon: LucideIcons.shieldCheck,
      type: CompressionType.image,
      presetId: 'smart',
      targetFormat: 'jpg',
    ),
    OutputPreset(
      id: 'save_storage',
      name: 'Save Storage',
      description: 'Smallest JPG output',
      icon: LucideIcons.hardDrive,
      type: CompressionType.image,
      presetId: 'smallest',
      targetFormat: 'jpg',
    ),
  ];

  static const List<OutputPreset> videoOutputPresets = [
    OutputPreset(
      id: 'whatsapp_chat',
      name: 'WhatsApp',
      description: 'MP4 under 16 MB',
      icon: LucideIcons.messageCircle,
      type: CompressionType.video,
      presetId: 'smart',
      targetFormat: 'mp4',
      targetSizeBytes: 16 * 1024 * 1024,
      whatsAppOptimize: true,
    ),
    OutputPreset(
      id: 'whatsapp_status',
      name: 'Status',
      description: 'MP4 under 10 MB',
      icon: LucideIcons.smartphone,
      type: CompressionType.video,
      presetId: 'smart',
      targetFormat: 'mp4',
      targetSizeBytes: 10 * 1024 * 1024,
      whatsAppOptimize: true,
    ),
    OutputPreset(
      id: 'email',
      name: 'Email',
      description: 'MP4 under 25 MB',
      icon: LucideIcons.mail,
      type: CompressionType.video,
      presetId: 'smart',
      targetFormat: 'mp4',
      targetSizeBytes: 25 * 1024 * 1024,
    ),
    OutputPreset(
      id: 'save_storage',
      name: 'Save Storage',
      description: 'Smallest MP4 output',
      icon: LucideIcons.hardDrive,
      type: CompressionType.video,
      presetId: 'smallest',
      targetFormat: 'mp4',
    ),
    OutputPreset(
      id: 'best_share',
      name: 'Best Share',
      description: 'Quality MP4, metadata removed',
      icon: LucideIcons.sparkles,
      type: CompressionType.video,
      presetId: 'best_quality',
      targetFormat: 'mp4',
    ),
  ];

  static const List<CompressionPreset> videoPresets = [
    CompressionPreset(
      id: 'best_quality',
      name: 'Best Quality',
      description: 'Preserve visual quality. Skips if already optimized.',
      icon: LucideIcons.sparkles,
      expectedCompression: '30-50%',
      targetBitrate: 0, // dynamic/CRF
      ffmpegPreset: 'fast',
      isPro: true,
    ),
    CompressionPreset(
      id: 'smart',
      name: 'Smart Compress',
      description: 'Recommended. Best balance of speed & quality.',
      icon: LucideIcons.brain,
      expectedCompression: '50-80%',
      targetBitrate: 2500000,
      ffmpegPreset: 'superfast',
    ),
    CompressionPreset(
      id: 'smallest',
      name: 'Smallest Size',
      description: 'Maximum reduction. Lightning fast.',
      icon: LucideIcons.minimize2,
      expectedCompression: '70-90%',
      targetBitrate: 1000000,
      ffmpegPreset: 'ultrafast',
    ),
  ];

  static const List<CompressionPreset> imagePresets = [
    CompressionPreset(
      id: 'best_quality',
      name: 'Best Quality',
      description: 'Original resolution, optimized.',
      icon: LucideIcons.sparkles,
      expectedCompression: '30-50%',
      quality: 0.90,
      isPro: true,
    ),
    CompressionPreset(
      id: 'smart',
      name: 'Smart Compress',
      description: 'Balanced. Standard resolution.',
      icon: LucideIcons.brain,
      expectedCompression: '60-80%',
      quality: 0.80,
    ),
    CompressionPreset(
      id: 'smallest',
      name: 'Smallest Size',
      description: 'Maximum reduction. Smaller resolution.',
      icon: LucideIcons.minimize2,
      expectedCompression: '80-95%',
      quality: 0.60,
    ),
  ];

  static CompressionPreset presetById(CompressionType type, String id) {
    final presets = type == CompressionType.video ? videoPresets : imagePresets;
    return presets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => presets[1],
    );
  }
}
