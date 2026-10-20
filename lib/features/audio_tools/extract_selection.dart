import 'package:uuid/uuid.dart';

import '../video_editor/models/audio_track_model.dart';
import '../video_editor/models/media_asset.dart';
import 'audio_tools_service.dart';

/// The part of an extracted sound the Extract sheet's two handles enclose.
///
/// The handles do not cut the file: the whole sound is kept and these become
/// the track's trim, so the user can still drag its edges out on the timeline.
/// They never cross and never close to less than [kMinClipDurationSeconds] —
/// the timeline's own minimum, so the sheet cannot make a track it would
/// refuse. A sound shorter than that stays whole.
class ExtractSelection {
  const ExtractSelection._(this.durationSeconds, this.start, this.end);

  factory ExtractSelection.whole(double durationSeconds) {
    final d = durationSeconds < 0 ? 0.0 : durationSeconds;
    return ExtractSelection._(d, 0.0, d);
  }

  final double durationSeconds;
  final double start;
  final double end;

  bool get _tooShortToTrim => durationSeconds <= kMinClipDurationSeconds;

  ExtractSelection withStart(double seconds) {
    if (_tooShortToTrim) return this;
    final upper = end - kMinClipDurationSeconds;
    return ExtractSelection._(durationSeconds, seconds.clamp(0.0, upper), end);
  }

  ExtractSelection withEnd(double seconds) {
    if (_tooShortToTrim) return this;
    final lower = start + kMinClipDurationSeconds;
    return ExtractSelection._(
      durationSeconds,
      start,
      seconds.clamp(lower, durationSeconds),
    );
  }
}

/// The track Done puts on the timeline: the whole sound, trimmed to the
/// selection, starting at [playhead]. Ordinary audio, not a sound effect.
AudioTrackModel extractedTrack({
  String? id,
  required ExtractedSound sound,
  required ExtractSelection selection,
  required double playhead,
}) {
  return AudioTrackModel(
    id: id ?? const Uuid().v4(),
    filePath: sound.path,
    sourceDuration: sound.durationSeconds,
    sourceStart: selection.start,
    sourceEnd: selection.end,
    timelineStart: playhead,
  );
}
