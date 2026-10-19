import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/audio_track_model.dart';

/// An audio clip's fill on the timeline: purple for music and the user's
/// own sound, orange for a sound effect. The fill does not change with
/// selection — that is the border's job — only while the clip is carried.
Color audioTrackColor(AudioTrackModel audio, {bool dragging = false}) {
  if (audio.isSoundEffect) {
    return dragging
        ? AppColors.soundEffect
        : AppColors.soundEffect.withValues(alpha: 0.5);
  }
  return dragging
      ? Colors.purpleAccent.shade400
      : Colors.purple.withValues(alpha: 0.5);
}
