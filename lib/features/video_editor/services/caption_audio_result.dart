/// What the native caption audio pass produced.
class CaptionAudioResult {
  const CaptionAudioResult({
    required this.outputPath,
    required this.durationSeconds,
    required this.hasSound,
  });

  final String outputPath;
  final double durationSeconds;

  /// False when the chosen sources hold nothing audible: the file was not
  /// written, and nothing may be uploaded.
  final bool hasSound;

  factory CaptionAudioResult.fromMap(Map<String, dynamic> map) {
    return CaptionAudioResult(
      outputPath: map['outputPath'] as String? ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 0.0,
      hasSound: map['hasSound'] as bool? ?? false,
    );
  }
}

/// The native pass stopped because Cancel asked it to.
class CaptionAudioCancelled implements Exception {
  const CaptionAudioCancelled();
}
