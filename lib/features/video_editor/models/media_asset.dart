import 'dart:ui';

/// What kind of media an asset holds.
///
/// The distinction matters mostly for duration: a video has a fixed source
/// length a clip cannot exceed, while a photo can be held on screen for as
/// long as the user likes.
enum MediaAssetType { video, image }

/// One imported file, shared by every clip cut from it.
///
/// Clips reference an asset by [id] rather than carrying a path, so splitting a
/// video produces two clips over one asset, and a project can mix several
/// videos and photos without any of them being "the" source.
class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.path,
    required this.type,
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.hasAudio,
  });

  final String id;
  final String path;
  final MediaAssetType type;

  /// Source length in seconds. Zero for a photo, which has no inherent length.
  final double durationSeconds;

  final double width;
  final double height;

  /// False for photos and for videos with no audio track. Used to skip audio
  /// handling that would otherwise fight a silent stream.
  final bool hasAudio;

  bool get isImage => type == MediaAssetType.image;

  /// Falls back to 16:9 rather than dividing by zero when dimensions are
  /// unknown — a probe can fail on an unusual file without breaking layout.
  double get aspectRatio {
    if (width <= 0 || height <= 0) return 16 / 9;
    return width / height;
  }

  Size get size => Size(width, height);

  /// How long a clip cut from this asset may run.
  ///
  /// A photo is unbounded: there is no source to run out of.
  double get maxClipDuration =>
      isImage ? double.infinity : durationSeconds;

  MediaAsset copyWith({
    String? id,
    String? path,
    MediaAssetType? type,
    double? durationSeconds,
    double? width,
    double? height,
    bool? hasAudio,
  }) {
    return MediaAsset(
      id: id ?? this.id,
      path: path ?? this.path,
      type: type ?? this.type,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      width: width ?? this.width,
      height: height ?? this.height,
      hasAudio: hasAudio ?? this.hasAudio,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'type': type.name,
      'durationSeconds': durationSeconds,
      'width': width,
      'height': height,
      'hasAudio': hasAudio,
    };
  }

  factory MediaAsset.fromJson(Map<String, dynamic> json) {
    return MediaAsset(
      id: json['id'] as String,
      path: json['path'] as String,
      type: MediaAssetType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => MediaAssetType.video,
      ),
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? 0.0,
      height: (json['height'] as num?)?.toDouble() ?? 0.0,
      hasAudio: json['hasAudio'] as bool? ?? true,
    );
  }
}

/// Default length a photo occupies when first added to the timeline.
const double kDefaultPhotoDurationSeconds = 3.0;

/// Shortest a clip may be trimmed to.
const double kMinClipDurationSeconds = 0.2;

/// Longest side the preview canvas is rendered at.
///
/// The preview does not need source resolution — a 4K clip previewed at 4K
/// costs fill rate for pixels nobody can see on a phone. Export picks its own
/// resolution independently.
const double kMaxPreviewCanvasPx = 1280.0;

/// Shape of a new project: 9:16, the vertical format short-form video is
/// published in.
///
/// Deliberately **not** derived from the imported media. Deriving it meant the
/// canvas changed shape as assets were probed and as clips were added or
/// removed, and each change resized the preview texture and rebuilt the EGL
/// surface — visible as a flash. A fixed default also makes a project's shape
/// predictable and portable: the same edit renders the same way whatever order
/// the media happened to be imported in.
///
/// The user overrides it from the ratio/crop tool, which is the one place a
/// canvas change is expected and understood.
const double kDefaultCanvasAspectRatio = 9 / 16;

/// Height a project renders at when its canvas is taller than it is wide.
const double kDefaultCanvasHeightPx = 1280.0;

/// Range a clip's pinch scale on the canvas may take.
///
/// Wide on purpose: shrinking a clip small over a coloured background and
/// blowing one up well past fill are both legitimate compositions. The floor
/// only stops a clip vanishing into an unrecoverable dot.
const double kMinClipCanvasScale = 0.1;
const double kMaxClipCanvasScale = 8.0;

/// Folds any angle into `(-180, 180]`.
///
/// So a clip dragged round twice reads as its actual orientation rather than
/// 725, and two clips at the same visual angle compare equal for the merge
/// rule. `180` rather than `-180` for the seam, so a straight flip reads as the
/// positive half-turn the ruler shows.
double normaliseDegrees(double degrees) {
  if (degrees.isNaN || degrees.isInfinite) return 0.0;
  var d = degrees % 360.0;
  if (d > 180.0) d -= 360.0;
  if (d <= -180.0) d += 360.0;
  return d;
}
