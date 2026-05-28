import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

enum CompressionType { video, image }

class CompressionPreset {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final double quality; // 0.0 - 1.0 (for images)
  final String ffmpegPreset; // for video (ultrafast, veryfast, medium, slow)
  final int targetBitrate; // for video in bps
  final String expectedCompression;

  const CompressionPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.expectedCompression,
    this.quality = 0.8,
    this.ffmpegPreset = 'medium',
    this.targetBitrate = 3000000,
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
  static const List<CompressionPreset> videoPresets = [
    CompressionPreset(
      id: 'best_quality',
      name: 'Best Quality',
      description: 'Preserve visual quality. Skips if already optimized.',
      icon: LucideIcons.sparkles,
      expectedCompression: '30-50%',
      targetBitrate: 0, // dynamic/CRF
      ffmpegPreset: 'fast',
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
}
