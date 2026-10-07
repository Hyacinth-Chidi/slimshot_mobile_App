import 'dart:math' as math;

import 'compression_presets.dart';

/// A span of file sizes, in bytes.
class SizeRange {
  const SizeRange(this.low, this.high);

  final int low;
  final int high;
}

/// Where a preset's expected reduction ("50-80%" smaller) puts the output.
///
/// A range, not one number, because that is what the preset promises: how
/// much a video shrinks depends on what is in it. Null with no original size
/// or a reduction that cannot be read.
SizeRange? estimateOutputRange(int originalBytes, String expectedCompression) {
  if (originalBytes <= 0) return null;
  final match = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(expectedCompression);
  if (match == null) return null;
  final a = int.parse(match[1]!).clamp(0, 100);
  final b = int.parse(match[2]!).clamp(0, 100);
  int keep(int percentSmaller) =>
      (originalBytes * (100 - percentSmaller) / 100).round();
  return SizeRange(keep(math.max(a, b)), keep(math.min(a, b)));
}

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

/// "≈ 9.6–24 MB": both ends in the larger end's unit, so the two numbers
/// compare at a glance.
String approxRange(SizeRange range) {
  final (unit, name) = _unitFor(range.high);
  String n(int bytes) => _number(bytes / unit, decimalsBelow: 10);
  return '≈ ${n(range.low)}–${n(range.high)} $name';
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
