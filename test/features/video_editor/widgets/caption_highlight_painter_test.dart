import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight_layout.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';

import '../../../support/test_fonts.dart';

/// The word being spoken lights up on the canvas — measured in pixels.
void main() {
  const canvas = Size(400, 700);
  const red = Color(0xFFFF0000);

  // "aaaa bbbb": the first word 0.0–0.5s, the second 0.5–1.0s.
  TextOverlayModel caption(CaptionHighlightStyle style) => TextOverlayModel(
        id: 'c',
        text: 'aaaa bbbb',
        fontFamily: kTestFontFamily,
        referenceCanvasSize: canvas,
        color: Colors.white,
        startTime: Duration.zero,
        endTime: const Duration(seconds: 2),
        captionSetId: 's',
        captionWords: const [
          CaptionWord(
            textStart: 0,
            textEnd: 4,
            start: Duration.zero,
            end: Duration(milliseconds: 500),
          ),
          CaptionWord(
            textStart: 5,
            textEnd: 9,
            start: Duration(milliseconds: 500),
            end: Duration(milliseconds: 1000),
          ),
        ],
        highlight: CaptionHighlight(style: style, color: red),
      );

  Future<({ByteData data, int width, int height})> paint(
    TextOverlayModel overlay,
    double seconds,
  ) async {
    final layout = TextOverlayLayout.measure(overlay, canvas);
    final recorder = ui.PictureRecorder();
    TextOverlayPainter(
      overlay: overlay,
      layout: layout,
      canvasSize: canvas,
      positionSeconds: seconds,
    ).paint(Canvas(recorder), layout.boxSize);
    final w = layout.boxSize.width.ceil();
    final h = layout.boxSize.height.ceil();
    final image = await recorder.endRecording().toImage(w, h);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    return (data: data, width: w, height: h);
  }

  CaptionHighlightLayout layoutOf(TextOverlayModel overlay) =>
      CaptionHighlightLayout.of(
        overlay,
        TextOverlayPainter.glyphBoxesFor(overlay, canvas),
      )!;

  /// Pixels in [area] that pass [test].
  int count(
    ({ByteData data, int width, int height}) img,
    Rect area,
    bool Function(int r, int g, int b, int a) test,
  ) {
    var n = 0;
    final l = area.left.floor().clamp(0, img.width - 1);
    final r = area.right.ceil().clamp(0, img.width);
    final t = area.top.floor().clamp(0, img.height - 1);
    final b = area.bottom.ceil().clamp(0, img.height);
    for (var y = t; y < b; y++) {
      for (var x = l; x < r; x++) {
        final o = (y * img.width + x) * 4;
        if (test(
          img.data.getUint8(o),
          img.data.getUint8(o + 1),
          img.data.getUint8(o + 2),
          img.data.getUint8(o + 3),
        )) {
          n++;
        }
      }
    }
    return n;
  }

  bool isRed(int r, int g, int b, int a) => a > 200 && r > 200 && g < 80 && b < 80;
  bool isWhite(int r, int g, int b, int a) => a > 200 && r > 200 && g > 200 && b > 200;
  bool isInk(int r, int g, int b, int a) => a > 40;

  group('the layout', () {
    test('maps each glyph to its word, and the space to none', () {
      final layout = layoutOf(caption(CaptionHighlightStyle.colour));
      expect(layout.glyphWord, [0, 0, 0, 0, 1, 1, 1, 1]);
      expect(layout.wordBoxes, hasLength(2));
      expect(layout.wordBoxes[0]!.right, lessThanOrEqualTo(layout.wordBoxes[1]!.left));
    });

    test('is nothing for a text with no highlight or no words', () {
      final plain = caption(CaptionHighlightStyle.colour).copyWith(
        highlight: CaptionHighlight.none,
      );
      expect(
        CaptionHighlightLayout.of(plain, TextOverlayPainter.glyphBoxesFor(plain, canvas)),
        isNull,
      );
      final wordless = caption(CaptionHighlightStyle.colour).copyWith(clearCaption: true);
      expect(
        CaptionHighlightLayout.of(wordless, TextOverlayPainter.glyphBoxesFor(wordless, canvas)),
        isNull,
      );
    });

    test('knows a right-to-left word', () {
      expect(isRightToLeftWord('שלום'), isTrue);
      expect(isRightToLeftWord('مرحبا'), isTrue);
      expect(isRightToLeftWord('hello'), isFalse);
      expect(isRightToLeftWord('123 שלום'), isTrue);
    });
  });

  group('on the canvas', () {
    test('colour: the word being spoken, and only it, is in the highlight colour', () async {
      final overlay = caption(CaptionHighlightStyle.colour);
      final words = layoutOf(overlay).wordBoxes;
      final first = await paint(overlay, 0.2);
      expect(count(first, words[0]!, isRed), greaterThan(20));
      expect(count(first, words[1]!, isRed), 0);
      expect(count(first, words[1]!, isWhite), greaterThan(20));

      final second = await paint(overlay, 0.7);
      expect(count(second, words[0]!, isRed), 0);
      expect(count(second, words[1]!, isRed), greaterThan(20));
    });

    test('none paints no highlight at all', () async {
      final overlay = caption(CaptionHighlightStyle.colour).copyWith(
        highlight: CaptionHighlight.none,
      );
      final img = await paint(overlay, 0.2);
      expect(
        count(img, Offset.zero & Size(img.width.toDouble(), img.height.toDouble()), isRed),
        0,
      );
    });

    test('karaoke: the sweep splits the word, lit behind it and plain ahead', () async {
      final overlay = caption(CaptionHighlightStyle.karaoke);
      final word = layoutOf(overlay).wordBoxes[0]!;
      final img = await paint(overlay, 0.25);
      final left = Rect.fromLTRB(word.left, word.top, word.left + word.width * 0.4, word.bottom);
      final right = Rect.fromLTRB(word.right - word.width * 0.4, word.top, word.right, word.bottom);
      expect(count(img, left, isRed), greaterThan(10));
      expect(count(img, right, isRed), 0);
      expect(count(img, right, isWhite), greaterThan(10));
    });

    test('pill: a box in the highlight colour behind the word, the text keeps its own', () async {
      // The test face is heavy and covers most of a word's own box, so the
      // pill is measured over its whole rect, margins included.
      final overlay = caption(CaptionHighlightStyle.pill);
      final layout = layoutOf(overlay);
      final img = await paint(overlay, 0.3);
      expect(count(img, layout.pillRect(0)!, isRed), greaterThan(100));
      expect(count(img, layout.wordBoxes[0]!, isWhite), greaterThan(20));
      expect(count(img, layout.pillRect(1)!, isRed), 0);
    });

    test('reveal: a word not yet spoken is not drawn', () async {
      final overlay = caption(CaptionHighlightStyle.reveal);
      final words = layoutOf(overlay).wordBoxes;
      final img = await paint(overlay, 0.2);
      expect(count(img, words[0]!, isInk), greaterThan(20));
      expect(count(img, words[1]!, isInk), 0);
    });

    test('pop: the word swells about its own centre', () async {
      final overlay = caption(CaptionHighlightStyle.pop);
      final words = layoutOf(overlay).wordBoxes;
      // Only the first word's side of the gap between the two words.
      final firstSide = Rect.fromLTRB(
        0,
        0,
        (words[0]!.right + words[1]!.left) / 2,
        words[0]!.bottom + 20,
      );

      double inkWidth(({ByteData data, int width, int height}) img) {
        var minX = img.width;
        var maxX = -1;
        for (var y = 0; y < img.height; y++) {
          for (var x = 0; x < firstSide.right.floor(); x++) {
            final o = (y * img.width + x) * 4;
            if (img.data.getUint8(o + 3) > 40) {
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
            }
          }
        }
        return (maxX - minX).toDouble();
      }

      final rest = inkWidth(await paint(overlay, 0.0));
      final peak = inkWidth(await paint(overlay, kHighlightPopSeconds / 2));
      expect(peak, greaterThan(rest * 1.08));
    });
  });

  group('repainting', () {
    TextOverlayPainter painterAt(TextOverlayModel overlay, double seconds) =>
        TextOverlayPainter(
          overlay: overlay,
          layout: TextOverlayLayout.measure(overlay, canvas),
          canvasSize: canvas,
          positionSeconds: seconds,
        );

    test('a highlighted caption repaints as the playhead moves', () {
      final overlay = caption(CaptionHighlightStyle.colour);
      expect(painterAt(overlay, 0.3).shouldRepaint(painterAt(overlay, 0.2)), isTrue);
    });

    test('a plain static text still does not', () {
      final overlay = caption(CaptionHighlightStyle.colour).copyWith(
        highlight: CaptionHighlight.none,
      );
      expect(painterAt(overlay, 0.3).shouldRepaint(painterAt(overlay, 0.2)), isFalse);
    });

    test('a changed highlight repaints', () {
      final a = caption(CaptionHighlightStyle.colour);
      final b = caption(CaptionHighlightStyle.pill);
      expect(painterAt(b, 0.2).shouldRepaint(painterAt(a, 0.2)), isTrue);
    });
  });
}
