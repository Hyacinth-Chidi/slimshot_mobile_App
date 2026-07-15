class AudioTrackModel {
  final String id;
  final String filePath;
  final double sourceDuration; // Total length of the audio file in seconds
  final double sourceStart;    // Start time of the trimmed audio in seconds
  final double sourceEnd;      // End time of the trimmed audio in seconds
  final double timelineStart;  // Start time on the video timeline in seconds
  final double volume;
  final int laneIndex;

  const AudioTrackModel({
    required this.id,
    required this.filePath,
    required this.sourceDuration,
    required this.sourceStart,
    required this.sourceEnd,
    required this.timelineStart,
    this.volume = 1.0,
    this.laneIndex = 0,
  });

  double get trimmedDuration => sourceEnd - sourceStart;
  double get timelineEnd => timelineStart + trimmedDuration;

  AudioTrackModel copyWith({
    String? id,
    String? filePath,
    double? sourceDuration,
    double? sourceStart,
    double? sourceEnd,
    double? timelineStart,
    double? volume,
    int? laneIndex,
  }) {
    return AudioTrackModel(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      sourceStart: sourceStart ?? this.sourceStart,
      sourceEnd: sourceEnd ?? this.sourceEnd,
      timelineStart: timelineStart ?? this.timelineStart,
      volume: volume ?? this.volume,
      laneIndex: laneIndex ?? this.laneIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filePath': filePath,
      'sourceDuration': sourceDuration,
      'sourceStart': sourceStart,
      'sourceEnd': sourceEnd,
      'timelineStart': timelineStart,
      'volume': volume,
      'laneIndex': laneIndex,
    };
  }

  factory AudioTrackModel.fromJson(Map<String, dynamic> json) {
    return AudioTrackModel(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      sourceDuration: (json['sourceDuration'] as num).toDouble(),
      sourceStart: (json['sourceStart'] as num).toDouble(),
      sourceEnd: (json['sourceEnd'] as num).toDouble(),
      timelineStart: (json['timelineStart'] as num).toDouble(),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      laneIndex: json['laneIndex'] as int? ?? 0,
    );
  }
}
