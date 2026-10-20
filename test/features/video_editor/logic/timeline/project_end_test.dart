import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/project_end.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

/// Where the project ends: the last video frame, or whatever on the lanes
/// outlasts it. One definition, read by the composer, the editor's duration
/// and the timeline's width.
void main() {
  Duration sec(num s) => Duration(milliseconds: (s * 1000).round());
  final clip = VideoSegment(id: 'c', assetId: 'a', sourceStart: 0, sourceEnd: 5);

  double end({
    List<AudioTrackModel> audios = const [],
    List<TextOverlayModel> texts = const [],
    List<ImageOverlayModel> images = const [],
    List<VideoOverlayModel> videos = const [],
    List<EffectBarModel> effects = const [],
  }) =>
      projectEndSeconds(
        segments: [clip],
        audios: audios,
        texts: texts,
        images: images,
        videos: videos,
        effects: effects,
      );

  test('the video alone', () => expect(end(), 5.0));

  test('an effect bar past the last clip moves the end', () {
    expect(
      end(effects: const [
        EffectBarModel(id: 'e', effectId: 'blur', start: 6, end: 9),
      ]),
      9.0,
    );
  });

  test('every other lane item still counts', () {
    expect(
      end(audios: const [
        AudioTrackModel(
          id: 'a',
          filePath: '/a.m4a',
          sourceDuration: 10,
          sourceStart: 0,
          sourceEnd: 7,
          timelineStart: 0,
        ),
      ]),
      7.0,
    );
    expect(end(texts: [
      TextOverlayModel(id: 't', text: 't', startTime: sec(1), endTime: sec(8)),
    ]), 8.0);
    expect(end(images: [
      ImageOverlayModel(
          id: 'i', imagePath: '/i.png', startTime: sec(1), endTime: sec(6.5)),
    ]), 6.5);
    expect(end(videos: [
      VideoOverlayModel(
        id: 'v',
        videoPath: '/v.mp4',
        timelineStart: sec(2),
        timelineEnd: sec(11),
        sourceStart: 0,
        sourceEnd: 9,
      ),
    ]), 11.0);
  });
}
