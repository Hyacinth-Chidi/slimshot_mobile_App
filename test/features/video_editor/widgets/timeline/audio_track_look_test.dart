import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/core/theme/sound_effect_icon.dart';
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

  test('a lane of sound effects shows the sound effects icon', () {
    List<LaneGutterKind> icons(int lane, List<AudioTrackModel> audios) => laneGutterKinds(
          lane: lane,
          audios: audios,
          texts: const [],
          images: const [],
          videos: const [],
          effects: const [],
        );
    expect(icons(0, [music, effect]), [LaneGutterKind.music]);
    expect(icons(1, [music, effect]), [LaneGutterKind.soundEffect]);
    expect(
      icons(0, [music, effect.copyWith(laneIndex: 0)]),
      [LaneGutterKind.music, LaneGutterKind.soundEffect],
    );
  });

  testWidgets('a sound effects lane is marked with the tool glyph',
      (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        laneGutterGlyph(LaneGutterKind.soundEffect, size: 12, color: Colors.white),
        laneGutterGlyph(LaneGutterKind.music, size: 12, color: Colors.white),
      ]),
    ));
    expect(find.byType(SoundEffectIcon), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
  });

  group('a voice made by Text to speech', () {
    final voice = music.copyWith(
      id: 'v',
      isVoice: true,
      voiceForTextId: 't',
      laneIndex: 2,
    );

    test('draws in the voice colour, with the mic in the gutter', () {
      expect(AppColors.voiceTrack, const Color(0xFF10B981)); // Emerald 500
      expect(audioTrackColor(voice).withValues(alpha: 1), AppColors.voiceTrack);
      expect(audioTrackColor(voice, dragging: true), AppColors.voiceTrack);
      expect(audioTrackColor(voice), isNot(audioTrackColor(music)));
      expect(audioTrackColor(voice), isNot(audioTrackColor(effect)));

      List<LaneGutterKind> icons(int lane, List<AudioTrackModel> audios) =>
          laneGutterKinds(
            lane: lane,
            audios: audios,
            texts: const [],
            images: const [],
            videos: const [],
            effects: const [],
          );
      expect(icons(2, [music, effect, voice]), [LaneGutterKind.voice]);
      expect(
        icons(0, [music, voice.copyWith(laneIndex: 0)]),
        [LaneGutterKind.music, LaneGutterKind.voice],
      );
    });

    testWidgets("its lane is marked with the microphone", (tester) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: laneGutterGlyph(
          LaneGutterKind.voice,
          size: 12,
          color: Colors.white,
        ),
      ));
      expect(tester.widget<Icon>(find.byType(Icon)).icon, LucideIcons.mic);
    });
  });
}
