import 'package:flutter/material.dart';
import '../../../core/theme/lucide_icons.dart';

class CompressionPreset {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final double quality; // 0.0 - 1.0 (for images)
  final String ffmpegPreset; // for video (ultrafast, veryfast, medium, slow)
  final int targetBitrate; // for video in bps
  final bool isPro;

  const CompressionPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.quality = 0.8,
    this.ffmpegPreset = 'medium',
    this.targetBitrate = 3000000,
    this.isPro = false,
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
  // One short line each: the Compress video screen lists them as rows, and
  // Smart wears a "Recommended" tag there rather than saying so in words.
  static const List<CompressionPreset> videoPresets = [
    CompressionPreset(
      id: 'best_quality',
      name: 'Best quality',
      description: 'Looks like the original',
      icon: LucideIcons.award,
      targetBitrate: 0, // dynamic/CRF
      ffmpegPreset: 'fast',
      isPro: true,
    ),
    CompressionPreset(
      id: 'smart',
      name: 'Smart',
      description: 'Much smaller, still sharp',
      icon: LucideIcons.sparkles,
      targetBitrate: 2500000,
      ffmpegPreset: 'superfast',
    ),
    CompressionPreset(
      id: 'smallest',
      name: 'Smallest',
      description: 'Smallest file, fastest',
      icon: LucideIcons.minimize2,
      targetBitrate: 1000000,
      ffmpegPreset: 'ultrafast',
    ),
  ];

  static const List<CompressionPreset> imagePresets = [
    CompressionPreset(
      id: 'best_quality',
      name: 'Best quality',
      description: 'Full resolution, looks the same',
      icon: LucideIcons.award,
      quality: 0.90,
      isPro: true,
    ),
    CompressionPreset(
      id: 'smart',
      name: 'Smart',
      description: 'Much smaller, still sharp',
      icon: LucideIcons.sparkles,
      quality: 0.80,
    ),
    CompressionPreset(
      id: 'smallest',
      name: 'Smallest',
      description: 'Smallest file, lower resolution',
      icon: LucideIcons.minimize2,
      quality: 0.60,
    ),
  ];
}
