class UpdateInfo {
  final String latestVersion;
  final int latestBuildNumber;
  final bool forceUpdate;
  final String title;
  final List<String> releaseNotes;
  final String updateUrl;
  final String minSupportedVersion;

  const UpdateInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.forceUpdate,
    required this.title,
    required this.releaseNotes,
    required this.updateUrl,
    required this.minSupportedVersion,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      latestVersion: json['latestVersion'] as String,
      latestBuildNumber: json['latestBuildNumber'] as int,
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      title: json['title'] as String,
      releaseNotes: List<String>.from(json['releaseNotes'] as List),
      updateUrl: json['updateUrl'] as String,
      minSupportedVersion: json['minSupportedVersion'] as String? ?? '1.0.0',
    );
  }
}
