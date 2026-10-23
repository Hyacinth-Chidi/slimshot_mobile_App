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

  /// `r_frame_rate` — the stream's nominal rate; 0 when unknown.
  final double frameRate;

  /// `avg_frame_rate` — frames over duration; 0 when unknown. Far from
  /// [frameRate] means a variable rate (screen recordings).
  final double avgFrameRate;

  /// Bits per sample, from the pixel format: 8, or 10 for `yuv420p10le`.
  final int bitDepth;

  /// `color_transfer` as ffprobe names it: `smpte2084` is PQ (HDR10),
  /// `arib-std-b67` HLG. Null when untagged.
  final String? colorTransfer;

  /// Clockwise degrees the picture is turned for display: 0, 90, 180 or
  /// 270. [width] and [height] are as stored.
  final int rotation;

  /// The first audio stream's codec; null when there is no sound.
  final String? audioCodec;
  final int audioChannels;

  const VideoMetadata({
    required this.width,
    required this.height,
    required this.bitrateKbps,
    required this.codec,
    required this.durationSecs,
    this.frameRate = 0,
    this.avgFrameRate = 0,
    this.bitDepth = 8,
    this.colorTransfer,
    this.rotation = 0,
    this.audioCodec,
    this.audioChannels = 0,
  });

  /// From ffprobe's JSON (`{streams: [...], format: {...}}`), as FFprobeKit's
  /// `getAllProperties` hands it over. Numbers arrive as numbers or strings.
  /// Width 0 when there is no video stream.
  factory VideoMetadata.fromProbe(Map<String, dynamic> json) {
    final streams = (json['streams'] as List?)?.whereType<Map>() ?? const <Map>[];
    final format = (json['format'] as Map?) ?? const {};
    Map? video;
    Map? audio;
    for (final s in streams) {
      if (video == null && s['codec_type'] == 'video') video = s;
      if (audio == null && s['codec_type'] == 'audio') audio = s;
    }
    final v = video ?? const {};
    final bitRate = _num(v['bit_rate']) ?? _num(format['bit_rate']) ?? 0;
    return VideoMetadata(
      width: (_num(v['width']) ?? 0).toInt(),
      height: (_num(v['height']) ?? 0).toInt(),
      bitrateKbps: bitRate ~/ 1000,
      codec: (v['codec_name'] as String?) ?? 'unknown',
      durationSecs: (_num(format['duration']) ?? _num(v['duration']) ?? 0).toDouble(),
      frameRate: _rate(v['r_frame_rate']),
      avgFrameRate: _rate(v['avg_frame_rate']),
      bitDepth: _bitDepth(v['pix_fmt'] as String?),
      colorTransfer: v['color_transfer'] as String?,
      rotation: _rotation(v),
      audioCodec: audio?['codec_name'] as String?,
      audioChannels: (_num(audio?['channels']) ?? 0).toInt(),
    );
  }

  static num? _num(Object? value) =>
      value is num ? value : (value is String ? num.tryParse(value) : null);

  /// "30000/1001" → 29.97; "0/0" or junk → 0.
  static double _rate(Object? value) {
    if (value is num) return value.toDouble();
    if (value is! String) return 0;
    final parts = value.split('/');
    final n = double.tryParse(parts[0]) ?? 0;
    final d = parts.length > 1 ? double.tryParse(parts[1]) ?? 0 : 1.0;
    return d == 0 ? 0 : n / d;
  }

  static int _bitDepth(String? pixFmt) {
    if (pixFmt == null) return 8;
    final m = RegExp(r'p(\d{2})(le|be)?$').firstMatch(pixFmt);
    return m == null ? 8 : int.parse(m.group(1)!);
  }

  /// The display matrix turns the picture back, so its angle is the
  /// opposite of the old `rotate` tag's; both come out clockwise here.
  static int _rotation(Map v) {
    final sideData = v['side_data_list'];
    if (sideData is List) {
      for (final d in sideData.whereType<Map>()) {
        final r = _num(d['rotation']);
        if (r != null) return ((-r.round()) % 360 + 360) % 360;
      }
    }
    final tags = v['tags'];
    final tag = tags is Map ? _num(tags['rotate']) : null;
    return tag == null ? 0 : (tag.round() % 360 + 360) % 360;
  }

  /// The picture's size as shown, after [rotation].
  int get displayWidth => rotation % 180 == 0 ? width : height;
  int get displayHeight => rotation % 180 == 0 ? height : width;

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
