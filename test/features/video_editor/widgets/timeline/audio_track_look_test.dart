import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/audio_track_color.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/lane_gutter_icons.dart';

/// A sound effect is told apart from music on the timeline by its colour,
/// and its lane by its icon.
void main() {
  const music = AudioTrackModel(
    id: 'm',
    filePath: '/m.mp3',
    sourceDuration: 30,
    sourceStart: 0,
    sourceEnd: 30,
    timelineStart: 0,
  );
  final effect = music.copyWith(id: 'e', isSoundEffect: true, laneIndex: 1);

  test('a sound effect wears its own colour', () {
    expect(audioTrackColor(effect).withValues(alpha: 1), AppColors.soundEffect);
    expect(audioTrackColor(effect), isNot(audioTrackColor(music)));
  });

  test('a carried sound effect stays its own colour', () {
    expect(
      audioTrackColor(effect, dragging: true),
      isNot(audioTrackColor(music, dragging: true)),
    );
  });

  test('a lane of sound effects shows the effects icon', () {
    List<IconData> icons(int lane, List<AudioTrackModel> audios) => laneGutterIcons(
          lane: lane,
          audios: audios,
          texts: const [],
          images: const [],
          videos: const [],
        );
    expect(icons(0, [music, effect]), [LucideIcons.music]);
    expect(icons(1, [music, effect]), [LucideIcons.sparkles]);
    expect(
      icons(0, [music, effect.copyWith(laneIndex: 0)]),
      [LucideIcons.music, LucideIcons.sparkles],
    );
  });
}
