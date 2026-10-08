/// The personal details a photo carries, as the native reader found them
/// (`PhotoMetadataReader`, Android's `ExifInterface`): where it was taken,
/// on what, when, and by whom. What the Privacy Strip screen shows before,
/// and what its report checks is gone after.
class PhotoMetadata {
  const PhotoMetadata({
    this.latitude,
    this.longitude,
    this.camera,
    this.taken,
    this.author,
  });

  factory PhotoMetadata.fromMap(Map<Object?, Object?> map) {
    double? number(Object? v) => v is num ? v.toDouble() : null;
    String? text(Object? v) {
      final s = v is String ? v.trim() : null;
      return s == null || s.isEmpty ? null : s;
    }

    var latitude = number(map['latitude']);
    var longitude = number(map['longitude']);
    // An empty GPS block reads as 0,0 — a point in the sea off Africa that
    // no photo is genuinely tagged with.
    if (latitude == 0 && longitude == 0) latitude = longitude = null;
    return PhotoMetadata(
      latitude: latitude,
      longitude: longitude,
      camera: cameraName(text(map['make']), text(map['model'])),
      taken: parseExifDate(text(map['dateTaken'])),
      author: text(map['artist']),
    );
  }

  final double? latitude;
  final double? longitude;
  final String? camera;
  final DateTime? taken;
  final String? author;

  bool get hasLocation => latitude != null && longitude != null;
  bool get hasCamera => camera != null;
  bool get hasTaken => taken != null;
  bool get hasAuthor => author != null;
  bool get isEmpty => !hasLocation && !hasCamera && !hasTaken && !hasAuthor;
}

/// "Infinix X6833", not "INFINIX Infinix X6833": a model usually already
/// carries its brand.
String? cameraName(String? make, String? model) {
  final m = make?.trim() ?? '';
  final d = model?.trim() ?? '';
  if (m.isEmpty && d.isEmpty) return null;
  if (m.isEmpty) return d;
  if (d.isEmpty) return m;
  return d.toLowerCase().startsWith(m.toLowerCase()) ? d : '$m $d';
}

/// EXIF's "2026:10:07 14:02:33". Null for blanks and the all-zero
/// placeholder some cameras write.
DateTime? parseExifDate(String? value) {
  final match = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?')
      .firstMatch(value ?? '');
  if (match == null) return null;
  final parts = [
    for (var g = 1; g <= 6; g++) int.tryParse(match[g] ?? '0') ?? 0,
  ];
  if (parts[0] == 0 || parts[1] == 0 || parts[2] == 0) return null;
  return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
}

/// "6.52° N, 3.37° E".
String formatCoordinates(double latitude, double longitude) {
  String part(double v, String positive, String negative) =>
      '${v.abs().toStringAsFixed(2)}° ${v >= 0 ? positive : negative}';
  return '${part(latitude, 'N', 'S')}, ${part(longitude, 'E', 'W')}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "7 Oct 2026, 14:02".
String formatTaken(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.day} ${_months[t.month - 1]} ${t.year}, ${two(t.hour)}:${two(t.minute)}';
}

/// "In 3 of 5".
String foundInLabel(int count, int total) => 'In $count of $total';

/// How many of several photos carry each kind of detail. A photo the reader
/// could not open ([PhotoMetadata] null) counts toward the total only.
class MetadataSummary {
  const MetadataSummary({
    required this.total,
    required this.location,
    required this.camera,
    required this.taken,
    required this.author,
  });

  factory MetadataSummary.of(List<PhotoMetadata?> photos) {
    int count(bool Function(PhotoMetadata) has) =>
        photos.where((p) => p != null && has(p)).length;
    return MetadataSummary(
      total: photos.length,
      location: count((p) => p.hasLocation),
      camera: count((p) => p.hasCamera),
      taken: count((p) => p.hasTaken),
      author: count((p) => p.hasAuthor),
    );
  }

  final int total;
  final int location;
  final int camera;
  final int taken;
  final int author;

  bool get isEmpty => location + camera + taken + author == 0;
}
