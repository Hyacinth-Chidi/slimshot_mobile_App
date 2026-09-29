import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_placement.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/lane_gutter_icons.dart';

void main() {
  const hello = [
    CaptionWord(
      textStart: 0,
      textEnd: 5,
      start: Duration.zero,
      end: Duration(milliseconds: 300),
    ),
    CaptionWord(
      textStart: 6,
      textEnd: 11,
      start: Duration(milliseconds: 400),
      end: Duration(milliseconds: 700),
    ),
  ];
  const drafts = [
    CaptionDraft(
      text: 'Hello world',
      start: Duration(milliseconds: 1000),
      end: Duration(milliseconds: 2000),
      words: hello,
    ),
    CaptionDraft(
      text: 'Goodbye',
      start: Duration(milliseconds: 2000),
      end: Duration(milliseconds: 2600),
      words: [
        CaptionWord(
          textStart: 0,
          textEnd: 7,
          start: Duration.zero,
          end: Duration(milliseconds: 200),
        ),
      ],
    ),
  ];
  const settings = CaptionSettings(setId: 'captions_1');

  VideoEditorNotifier withTexts(List<TextOverlayModel> texts) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(textOverlays: texts);

  List<TextOverlayModel> captionsOf(VideoEditorNotifier n) =>
      n.state.textOverlays.where((t) => t.isCaption).toList();

  test('each caption is a text in the default look, on the given lane', () {
    final list = buildCaptionOverlays(
      drafts: drafts,
      setId: 'captions_1',
      lane: 2,
      canvasSize: const Size(360, 640),
    );
    expect(list.map((t) => t.text), ['Hello world', 'Goodbye']);
    expect(list.map((t) => t.id).toSet(), hasLength(2));

    final first = list.first;
    expect(
      (first.startTime, first.endTime),
      (drafts.first.start, drafts.first.end),
    );
    expect(first.captionSetId, 'captions_1');
    expect(first.captionWords, hello);
    expect(first.laneIndex, 2);
    expect(first.referenceCanvasSize, const Size(360, 640));
    expect(
      first.boxWidth,
      isNull,
      reason: 'a shared reference canvas already wraps them alike',
    );
    // The Subtitle look, less its fades: a half-second fade is most of a
    // one-second caption's life.
    expect(
      [first.inAnimation, first.outAnimation, first.loopAnimation],
      ['none', 'none', 'none'],
    );
    expect(
      captionDefaultTemplate.isAppliedTo(
        first.copyWith(
          inAnimation: captionDefaultTemplate.inAnimation,
          outAnimation: captionDefaultTemplate.outAnimation,
        ),
      ),
      isTrue,
    );
  });

  test('places the set on the first lane free across it, as one undo step', () {
    final n = withTexts([
      TextOverlayModel(
        id: 'title',
        text: 'Title',
        startTime: const Duration(milliseconds: 1500),
        endTime: const Duration(seconds: 4),
      ),
    ]);
    n.placeCaptions(drafts, settings);

    final captions = captionsOf(n);
    expect(captions, hasLength(2));
    expect(captions.every((t) => t.laneIndex == 1), isTrue);
    expect(n.state.captionSettings, settings);

    n.undo();
    expect(captionsOf(n), isEmpty);
    expect(n.state.captionSettings, isNull);
  });

  test(
      'regenerating replaces the set, keeps plain text, and reuses the freed lane',
      () {
    final n = withTexts([
      TextOverlayModel(
        id: 'title',
        text: 'Title',
        startTime: const Duration(milliseconds: 1500),
        endTime: const Duration(seconds: 4),
      ),
    ]);
    n.placeCaptions(drafts, settings);
    n.placeCaptions(
      const [
        CaptionDraft(
          text: 'Fresh',
          start: Duration(milliseconds: 1000),
          end: Duration(milliseconds: 1800),
          words: [
            CaptionWord(
              textStart: 0,
              textEnd: 5,
              start: Duration.zero,
              end: Duration(milliseconds: 300),
            ),
          ],
        ),
      ],
      const CaptionSettings(setId: 'captions_2'),
    );

    final captions = captionsOf(n);
    expect(captions.map((t) => t.text), ['Fresh']);
    expect(captions.single.captionSetId, 'captions_2');
    expect(captions.single.laneIndex, 1);
    expect(n.state.textOverlays.any((t) => t.id == 'title'), isTrue);
    expect(n.state.captionSettings?.setId, 'captions_2');
  });

  test('nothing to place changes nothing and takes no undo step', () {
    final n = withTexts(const []);
    n.placeCaptions(const [], settings);
    expect(n.state.canUndo, isFalse);
    expect(n.state.captionSettings, isNull);
  });

  test('a caption lane is marked as captions in the gutter', () {
    final caption = TextOverlayModel(
      id: 'c',
      text: 'Hi',
      captionSetId: 's',
      laneIndex: 1,
    );
    final plain = TextOverlayModel(id: 't', text: 'Hi');
    List<IconData> icons(int lane, List<TextOverlayModel> texts) =>
        laneGutterIcons(
          lane: lane,
          audios: const [],
          texts: texts,
          images: const [],
          videos: const [],
        );
    expect(icons(1, [caption, plain]), [LucideIcons.subtitles]);
    expect(icons(0, [caption, plain]), [LucideIcons.type]);
    expect(
      icons(0, [plain, caption.copyWith(laneIndex: 0)]),
      [LucideIcons.type, LucideIcons.subtitles],
    );
  });
}
