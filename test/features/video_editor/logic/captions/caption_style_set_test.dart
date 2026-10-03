import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/logic/text_look.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A caption set's look is the set's: a style restyles every caption, and a
/// look edit on one caption reaches the rest unless the user says otherwise.
void main() {
  const drafts = [
    CaptionDraft(
      text: 'Hello there',
      start: Duration(milliseconds: 1000),
      end: Duration(milliseconds: 2000),
      words: [
        CaptionWord(textStart: 0, textEnd: 5, start: Duration.zero, end: Duration(milliseconds: 300)),
      ],
    ),
    CaptionDraft(
      text: 'Bye',
      start: Duration(milliseconds: 2000),
      end: Duration(milliseconds: 2600),
      words: [
        CaptionWord(textStart: 0, textEnd: 3, start: Duration.zero, end: Duration(milliseconds: 200)),
      ],
    ),
  ];
  const neon = TextLook(fontFamily: 'Righteous', color: Color(0xFF0A84FF));
  const pop = CaptionHighlight(style: CaptionHighlightStyle.pop, color: Color(0xFF30D158));

  final plain = TextOverlayModel(
    id: 'title',
    text: 'Title',
    startTime: Duration.zero,
    endTime: const Duration(seconds: 4),
  );

  /// A project holding [plain] and a two-caption set, with nothing to undo.
  VideoEditorNotifier withSet() {
    final made = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(textOverlays: [plain])
      ..placeCaptions(drafts, const CaptionSettings(setId: 's'), canvasSize: const Size(360, 640));
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        textOverlays: made.state.textOverlays,
        captionSettings: made.state.captionSettings,
      );
  }

  List<TextOverlayModel> captionsOf(VideoEditorNotifier n) =>
      n.state.textOverlays.where((t) => t.isCaption).toList();
  TextOverlayModel titleOf(VideoEditorNotifier n) =>
      n.state.textOverlays.firstWhere((t) => t.id == 'title');

  group('a style', () {
    test('restyles every caption, look and highlight, as one undo step', () {
      final n = withSet();
      final before = captionsOf(n);
      n.restyleCaptions(neon, pop);

      final after = captionsOf(n);
      expect(after.map(TextLook.of), everyElement(neon));
      expect(after.map((c) => c.highlight), everyElement(pop));
      expect(n.state.captionSettings?.highlight, pop);
      // Only the look: words, timing, place and size are the set's own.
      for (var i = 0; i < after.length; i++) {
        expect(after[i].text, before[i].text);
        expect(after[i].captionWords, before[i].captionWords);
        expect(after[i].startTime, before[i].startTime);
        expect(after[i].position, before[i].position);
        expect(after[i].scale, before[i].scale);
      }
      expect(TextLook.of(titleOf(n)), TextLook.of(plain));

      n.undo();
      expect(captionsOf(n).map(TextLook.of), everyElement(TextLook.of(before.first)));
      expect(n.state.canUndo, isFalse);
    });

    test('the style the set already wears takes no undo step', () {
      final n = withSet();
      final current = captionsOf(n).first;
      n.restyleCaptions(TextLook.of(current), current.highlight);
      expect(n.state.canUndo, isFalse);
    });

    test('with no captions there is nothing to restyle', () {
      final n = VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(textOverlays: [plain])
        ..restyleCaptions(neon, pop);
      expect(n.state.canUndo, isFalse);
      expect(TextLook.of(titleOf(n)), TextLook.of(plain));
    });
  });

  group('apply to all captions', () {
    test('is on until the user turns it off', () {
      expect(withSet().state.captionLookToAll, isTrue);
    });

    test('a look edit on one caption reaches its set, in the same undo step', () {
      final n = withSet();
      final first = captionsOf(n).first;
      n.updateTextOverlay(first.id, (c) => c.copyWith(color: Colors.red, strokeWidth: 6));

      expect(captionsOf(n).map((c) => c.color), everyElement(Colors.red));
      expect(captionsOf(n).map((c) => c.strokeWidth), everyElement(6.0));
      expect(titleOf(n).color, plain.color);
      // The words are each caption's own.
      expect(captionsOf(n).map((c) => c.text), ['Hello there', 'Bye']);

      n.undo();
      expect(captionsOf(n).map((c) => c.color), everyElement(first.color));
      expect(n.state.canUndo, isFalse);
    });

    test('turned off, the edit stays on the caption it was made on', () {
      final n = withSet()..setCaptionLookToAll(false);
      final first = captionsOf(n).first;
      n.updateTextOverlay(first.id, (c) => c.copyWith(color: Colors.red));
      expect(captionsOf(n).map((c) => c.color), [Colors.red, first.color]);
    });

    test('a move is not a look, and is not broadcast by it', () {
      final n = withSet();
      final [first, second] = captionsOf(n);
      n.updateTextOverlayLive(first.id, (c) => c.copyWith(position: const Offset(5, 5), text: 'Hi there'));
      expect(captionsOf(n)[1].position, second.position);
      expect(captionsOf(n)[1].text, second.text);
    });
  });
}
