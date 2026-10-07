/// The short labels the compress screens put on a file.
library;

import '../providers/compression_provider.dart';
import 'compression_presets.dart';

const _kb = 1024;
const _mb = 1024 * 1024;
const _gb = 1024 * 1024 * 1024;

(int, String) _unitFor(int bytes) => bytes >= _gb
    ? (_gb, 'GB')
    : bytes >= _mb
        ? (_mb, 'MB')
        : (_kb, 'KB');

String _number(double value, {required double decimalsBelow}) {
  if (value >= decimalsBelow) return value.round().toString();
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

/// "48.2 MB", "312 MB", "950 KB": a decimal only where it says something.
String compactSize(int bytes) {
  final (unit, name) = _unitFor(bytes);
  return '${_number(bytes / unit, decimalsBelow: 100)} $name';
}

/// "1080p · 0:42": what the video is, before it is compressed.
String videoInfoLabel(VideoMetadata metadata) {
  final seconds = metadata.durationSecs.round();
  if (seconds <= 0) return metadata.resolutionTier;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  final clock = h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  return '${metadata.resolutionTier} · $clock';
}

/// A file format as people write it: "MP4", "WebM", "WebP".
String formatName(String extension) => switch (extension.toLowerCase()) {
      'webm' => 'WebM',
      'webp' => 'WebP',
      final other => other.toUpperCase(),
    };

/// How the result was made, for the result screen's Details: a quick
/// preset's name, a target size, or the quality chosen. Null when none.
String? resultQualityLabel(CompressionState state, {required bool isVideo}) {
  final outputId = state.selectedOutputPresetId;
  if (outputId != null) {
    final presets = isVideo
        ? CompressionPresets.videoOutputPresets
        : CompressionPresets.imageOutputPresets;
    for (final preset in presets) {
      if (preset.id == outputId) return preset.name;
    }
  }
  if (state.compressionMode == CompressionMode.targetSize) return 'Target size';
  return state.selectedPreset?.name;
}
