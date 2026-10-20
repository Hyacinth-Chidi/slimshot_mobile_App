import 'dart:math' as math;

import '../../models/audio_track_model.dart';
import '../../models/effect_bar_model.dart';
import '../../models/image_overlay_model.dart';
import '../../models/text_overlay_model.dart';
import '../../models/video_overlay_model.dart';
import '../../models/video_segment.dart';
import 'timeline_geometry.dart';

/// Where the project actually ends: the last video frame, or the end of
/// whatever on the lanes outlasts it — audio, an overlay, an effect bar.
///
/// **One definition, three readers**: the composer's `durationSeconds` (what
/// the preview's tail and the export run to), `totalEditedDurationProvider`
/// (the editor's duration) and `ScrollableTimeline`'s width (where the last
/// thing can still be reached). They used to be three copies of this loop,
/// and a lane kind added to one and not the others is a bar the export cuts
/// off or the timeline draws outside the reach of a finger.
double projectEndSeconds({
  required List<VideoSegment> segments,
  required List<AudioTrackModel> audios,
  required List<TextOverlayModel> texts,
  required List<ImageOverlayModel> images,
  required List<VideoOverlayModel> videos,
  required List<EffectBarModel> effects,
}) {
  double seconds(Duration d) => d.inMilliseconds / 1000.0;
  // Through the shared geometry, never a sum: transitions overlap their clips.
  var end = videoTimelineDuration(segments);
  for (final track in audios) {
    end = math.max(end, track.timelineEnd);
  }
  for (final text in texts) {
    end = math.max(end, seconds(text.endTime));
  }
  for (final image in images) {
    end = math.max(end, seconds(image.endTime));
  }
  for (final video in videos) {
    end = math.max(end, seconds(video.timelineEnd));
  }
  for (final bar in effects) {
    end = math.max(end, bar.end);
  }
  return end;
}
