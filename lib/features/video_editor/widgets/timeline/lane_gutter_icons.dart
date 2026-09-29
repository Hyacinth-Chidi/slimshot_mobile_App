import 'package:flutter/widgets.dart';

import '../../../../core/theme/lucide_icons.dart';
import '../../models/audio_track_model.dart';
import '../../models/image_overlay_model.dart';
import '../../models/text_overlay_model.dart';
import '../../models/video_overlay_model.dart';

/// One icon per kind of thing [lane] holds, for the gutter before 00:00.
/// Captions are text, but a lane of them reads as captions.
List<IconData> laneGutterIcons({
  required int lane,
  required List<AudioTrackModel> audios,
  required List<TextOverlayModel> texts,
  required List<ImageOverlayModel> images,
  required List<VideoOverlayModel> videos,
}) {
  return [
    if (audios.any((a) => a.laneIndex == lane)) LucideIcons.music,
    if (texts.any((t) => t.laneIndex == lane && !t.isCaption))
      LucideIcons.type,
    if (texts.any((t) => t.laneIndex == lane && t.isCaption))
      LucideIcons.subtitles,
    if (images.any((i) => i.laneIndex == lane)) LucideIcons.image,
    if (videos.any((v) => v.laneIndex == lane)) LucideIcons.video,
  ];
}
