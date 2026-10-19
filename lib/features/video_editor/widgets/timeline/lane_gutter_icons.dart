import 'package:flutter/widgets.dart';

import '../../../../core/theme/lucide_icons.dart';
import '../../../../core/theme/sound_effect_icon.dart';
import '../../models/audio_track_model.dart';
import '../../models/image_overlay_model.dart';
import '../../models/text_overlay_model.dart';
import '../../models/video_overlay_model.dart';

/// A kind of thing a lane can hold, as the gutter before 00:00 marks it.
enum LaneGutterKind { music, soundEffect, text, caption, image, video }

/// One mark per kind of thing [lane] holds, for the gutter before 00:00.
/// Captions are text, but a lane of them reads as captions; sound effects
/// are audio, but are told apart from music on the timeline.
List<LaneGutterKind> laneGutterKinds({
  required int lane,
  required List<AudioTrackModel> audios,
  required List<TextOverlayModel> texts,
  required List<ImageOverlayModel> images,
  required List<VideoOverlayModel> videos,
}) {
  return [
    if (audios.any((a) => a.laneIndex == lane && !a.isSoundEffect))
      LaneGutterKind.music,
    if (audios.any((a) => a.laneIndex == lane && a.isSoundEffect))
      LaneGutterKind.soundEffect,
    if (texts.any((t) => t.laneIndex == lane && !t.isCaption))
      LaneGutterKind.text,
    if (texts.any((t) => t.laneIndex == lane && t.isCaption))
      LaneGutterKind.caption,
    if (images.any((i) => i.laneIndex == lane)) LaneGutterKind.image,
    if (videos.any((v) => v.laneIndex == lane)) LaneGutterKind.video,
  ];
}

/// The mark itself: the same glyph the kind's tool wears in the toolbar.
Widget laneGutterGlyph(
  LaneGutterKind kind, {
  required double size,
  required Color color,
}) {
  final IconData icon;
  switch (kind) {
    case LaneGutterKind.soundEffect:
      return SoundEffectIcon(size: size, color: color);
    case LaneGutterKind.music:
      icon = LucideIcons.music;
    case LaneGutterKind.text:
      icon = LucideIcons.type;
    case LaneGutterKind.caption:
      icon = LucideIcons.subtitles;
    case LaneGutterKind.image:
      icon = LucideIcons.image;
    case LaneGutterKind.video:
      icon = LucideIcons.video;
  }
  return Icon(icon, size: size, color: color);
}
