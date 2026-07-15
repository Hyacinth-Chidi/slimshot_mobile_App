class VideoSegment {
  final String id;
  final double sourceStart;
  final double sourceEnd;
  final double volume;
  final double speed;
  final String? transitionType;
  final double? transitionDuration;
  final String? overrideVideoPath;
  final bool isReversed;

  VideoSegment({
    required this.id,
    required this.sourceStart,
    required this.sourceEnd,
    this.volume = 1.0,
    this.speed = 1.0,
    this.transitionType,
    this.transitionDuration,
    this.overrideVideoPath,
    this.isReversed = false,
  });

  double get duration => (sourceEnd - sourceStart) / speed;

  VideoSegment copyWith({
    String? id,
    double? sourceStart,
    double? sourceEnd,
    double? volume,
    double? speed,
    String? transitionType,
    bool clearTransitionType = false,
    double? transitionDuration,
    bool clearTransitionDuration = false,
    String? overrideVideoPath,
    bool clearOverrideVideoPath = false,
    bool? isReversed,
  }) {
    return VideoSegment(
      id: id ?? this.id,
      sourceStart: sourceStart ?? this.sourceStart,
      sourceEnd: sourceEnd ?? this.sourceEnd,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      transitionType: clearTransitionType ? null : (transitionType ?? this.transitionType),
      transitionDuration: clearTransitionDuration ? null : (transitionDuration ?? this.transitionDuration),
      overrideVideoPath: clearOverrideVideoPath ? null : (overrideVideoPath ?? this.overrideVideoPath),
      isReversed: isReversed ?? this.isReversed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceStart': sourceStart,
      'sourceEnd': sourceEnd,
      'volume': volume,
      'speed': speed,
      'transitionType': transitionType,
      'transitionDuration': transitionDuration,
      'overrideVideoPath': overrideVideoPath,
      'isReversed': isReversed,
    };
  }

  factory VideoSegment.fromJson(Map<String, dynamic> json) {
    return VideoSegment(
      id: json['id'] as String,
      sourceStart: (json['sourceStart'] as num).toDouble(),
      sourceEnd: (json['sourceEnd'] as num).toDouble(),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      transitionType: json['transitionType'] as String?,
      transitionDuration: (json['transitionDuration'] as num?)?.toDouble(),
      overrideVideoPath: json['overrideVideoPath'] as String?,
      isReversed: json['isReversed'] as bool? ?? false,
    );
  }
}
