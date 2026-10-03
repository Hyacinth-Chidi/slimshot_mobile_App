import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A caption set's highlight is the set's: chosen once, worn by every caption.
void main() {
  const karaoke = CaptionHighlight(style: CaptionHighlightStyle.karaoke);
  const pill = CaptionHighlight(
    style: CaptionHighlightStyle.pill,
    color: Color(0xFF0A84FF),
  );

  const word = CaptionWord(
    textStart: 0,
    textEnd: 5,
    start: Duration.zero,
    end: Duration(milliseconds: 300),
  );
  const drafts = [
    CaptionDraft(
      text: 'Hello there',
      start: Duration(milliseconds: 1000),
      end: Duration(milliseconds: 2000),
      words: [
        word,
        CaptionWord(
          textStart: 6,
          textEnd: 11,
          start: Duration(milliseconds: 400),
          end: Duration(milliseconds: 700),
        ),
      ],
    ),
    CaptionDraft(
      text: 'Bye',
      start: Duration(milliseconds: 2000),
      end: Duration(milliseconds: 2600),
      words: [
        CaptionWord(
          textStart: 0,
          textEnd: 3,
          start: Duration.zero,
          end: Duration(milliseconds: 200),
        ),
      ],
    ),
  ];

  final plain = TextOverlayModel(
    id: 'title',
    text: 'Title',
    startTime: Duration.zero,
    endTime: const Duration(seconds: 4),
  );

  VideoEditorNotifier notifier() => VideoEditorNotifier(VideoEditorService())
    ..state = VideoEditorState(textOverlays: [plain]);

  List<TextOverlayModel> captionsOf(VideoEditorNotifier n) =>
      n.state.textOverlays.where((t) => t.isCaption).toList();

  /// A notifier already holding a set wearing [highlight], with nothing to
  /// undo.
  VideoEditorNotifier withSet(CaptionHighlight highlight) {
    final n = notifier()
      ..placeCaptions(
        drafts,
        CaptionSettings(setId: 's', highlight: highlight),
      );
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        textOverlays: n.state.textOverlays,
        captionSettings: n.state.captionSettings,
      );
  }

  test('a new set wears the highlight it was generated with', () {
    final n = notifier()
      ..placeCaptions(drafts, const CaptionSettings(setId: 's', highlight: karaoke));
    expect(captionsOf(n).map((c) => c.highlight), everyElement(karaoke));
    expect(n.state.captionSettings?.highlight, karaoke);
  });

  test('choosing a highlight restyles the whole set, as one undo step', () {
    final n = withSet(karaoke)..setCaptionHighlight(pill);

    expect(captionsOf(n), hasLength(2));
    expect(captionsOf(n).map((c) => c.highlight), everyElement(pill));
    expect(n.state.captionSettings?.highlight, pill);
    // Plain text is not part of the set.
    expect(
      n.state.textOverlays.firstWhere((t) => t.id == 'title').highlight,
      CaptionHighlight.none,
    );

    n.undo();
    expect(captionsOf(n).map((c) => c.highlight), everyElement(karaoke));
    expect(n.state.captionSettings?.highlight, karaoke);
    expect(n.state.canUndo, isFalse);
  });

  test('choosing the highlight the set already wears takes no undo step', () {
    final n = withSet(karaoke)..setCaptionHighlight(karaoke);
    expect(n.state.canUndo, isFalse);
  });

  test('with no captions there is nothing to restyle', () {
    final n = notifier()..setCaptionHighlight(pill);
    expect(n.state.canUndo, isFalse);
    expect(n.state.captionSettings, isNull);
    expect(n.state.textOverlays.single.highlight, CaptionHighlight.none);
  });

  test('re-cutting the set keeps its highlight', () {
    final n = withSet(pill)..recutCaptions(CaptionLength.word);
    expect(n.state.captionSettings?.length, CaptionLength.word);
    expect(n.state.captionSettings?.highlight, pill);
    expect(captionsOf(n), isNotEmpty);
    expect(captionsOf(n).map((c) => c.highlight), everyElement(pill));
  });

  test('a copy of a caption is ordinary text, so it sheds the highlight', () {
    final n = withSet(pill);
    final caption = captionsOf(n).first;
    n.duplicateTextOverlay(caption.id);
    final copy = n.state.textOverlays.firstWhere(
      (t) => !t.isCaption && t.id != 'title',
    );
    expect(copy.highlight, CaptionHighlight.none);
  });
}
