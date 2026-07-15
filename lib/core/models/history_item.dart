class HistoryItem {
  final String id;
  final String title;
  final String operation;
  final String mediaType;
  final List<String> outputPaths;
  final int originalSize;
  final int outputSize;
  final String detail;
  final DateTime createdAt;

  const HistoryItem({
    required this.id,
    required this.title,
    required this.operation,
    required this.mediaType,
    required this.outputPaths,
    required this.originalSize,
    required this.outputSize,
    required this.detail,
    required this.createdAt,
  });

  double get savedPercent {
    if (originalSize <= 0) return 0;
    return (1 - (outputSize / originalSize)) * 100;
  }

  bool get savedSpace => outputSize < originalSize;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'operation': operation,
      'mediaType': mediaType,
      'outputPaths': outputPaths,
      'originalSize': originalSize,
      'outputSize': outputSize,
      'detail': detail,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: json['id'] as String,
      title: json['title'] as String,
      operation: json['operation'] as String,
      mediaType: json['mediaType'] as String,
      outputPaths: List<String>.from(json['outputPaths'] as List),
      originalSize: json['originalSize'] as int,
      outputSize: json['outputSize'] as int,
      detail: json['detail'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
