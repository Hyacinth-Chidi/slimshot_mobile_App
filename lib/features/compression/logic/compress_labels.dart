/// The short labels the compress screens put on a file.
library;

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
      'jpeg' => 'JPG',
      'webp' => 'WebP',
      final other => other.toUpperCase(),
    };

/// "HEIC · 12 MP": what a photo is, before it is compressed. Either half
/// drops out when it is not known.
String photoInfoLabel(String path, int? width, int? height) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  final format = dot > 0 ? formatName(name.substring(dot + 1)) : null;
  final pixels = width != null && height != null && width > 0 && height > 0
      ? '${_number(width * height / 1e6, decimalsBelow: 10)} MP'
      : null;
  return [?format, ?pixels].join(' · ');
}
