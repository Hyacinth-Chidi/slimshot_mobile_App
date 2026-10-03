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

/// Device-reported: on a caption that wraps to two lines, the second line's
/// highlight painted over the first — a sweep left white holes in words
/// already spoken, and Pop dragged a scaled ghost of line 1 across it.
///
/// Each letter is drawn on its own, inside a cell padded for its outline and
/// shadow. That padding reached the other line, and every cell drew the
/// **whole** caption clipped to itself — so a line-2 cell repainted line-1
/// letters in line 2's state. A letter's cell may carry its own outline and
/// shadow, never another letter.
void main() {
  const canvas = Size(400, 700);
  const red = Color(0xFFFF0000);

  // "aaaa" on line 1 (0.0–0.5s), "bbbb" wrapped onto line 2 (0.5–1.0s), with
  // the outline and soft shadow a caption wears.
  TextOverlayModel caption(CaptionHighlightStyle style) => TextOverlayModel(
        id: 'c',
        text: 'aaaa bbbb',
        fontFamily: kTestFontFamily,
        referenceCanvasSize: canvas,
        color: Colors.white,
        boxWidth: 200,
        strokeColor: Colors.black,
        strokeWidth: 4,
        shadowColor: Colors.black,
        shadowOpacity: 0.6,
        shadowBlurRadius: 8,
        shadowDistance: 2,
        shadowAngle: 90,
        startTime: Duration.zero,
        endTime: const Duration(seconds: 2),
        captionSetId: 's',
        captionWords: const [
          CaptionWord(textStart: 0, textEnd: 4, start: Duration.zero, end: Duration(milliseconds: 500)),
          CaptionWord(
            textStart: 5,
            textEnd: 9,
            start: Duration(milliseconds: 500),
            end: Duration(milliseconds: 1000),
          ),
        ],
        highlight: CaptionHighlight(style: style, color: red),
      );

  Future<({ByteData data, int width})> paint(TextOverlayModel overlay, double seconds) async {
    final layout = TextOverlayLayout.measure(overlay, canvas);
    final recorder = ui.PictureRecorder();
    TextOverlayPainter(
      overlay: overlay,
      layout: layout,
      canvasSize: canvas,
      positionSeconds: seconds,
    ).paint(Canvas(recorder), layout.boxSize);
    final image = await recorder
        .endRecording()
        .toImage(layout.boxSize.width.ceil(), layout.boxSize.height.ceil());
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final width = image.width;
    image.dispose();
    return (data: data, width: width);
  }

  int count(({ByteData data, int width}) img, Rect area, bool Function(int r, int g, int b, int a) test) {
    var n = 0;
    for (var y = area.top.ceil(); y < area.bottom.floor(); y++) {
      for (var x = area.left.ceil(); x < area.right.floor(); x++) {
        final o = (y * img.width + x) * 4;
        if (test(img.data.getUint8(o), img.data.getUint8(o + 1), img.data.getUint8(o + 2),
            img.data.getUint8(o + 3))) {
          n++;
        }
      }
    }
    return n;
  }

  bool isRed(int r, int g, int b, int a) => a > 200 && r > 200 && g < 80 && b < 80;
  bool isWhite(int r, int g, int b, int a) => a > 200 && r > 200 && g > 200 && b > 200;

  /// Line 1's word, a little inside its own box.
  Rect lineOne(TextOverlayModel overlay) {
    final layout = CaptionHighlightLayout.of(
      overlay,
      TextOverlayPainter.glyphBoxesFor(overlay, canvas),
    )!;
    final first = layout.wordBoxes[0]!;
    final second = layout.wordBoxes[1]!;
    // The fixture must really wrap, or it proves nothing.
    expect(second.top, greaterThanOrEqualTo(first.bottom - 0.5));
    return first.deflate(3);
  }

  test('a sweep on line 2 leaves line 1, already spoken, wholly lit', () async {
    final overlay = caption(CaptionHighlightStyle.karaoke);
    final img = await paint(overlay, 0.75);
    final area = lineOne(overlay);
    expect(count(img, area, isRed), greaterThan(100));
    expect(count(img, area, isWhite), 0);
  });

  test('a word lit on line 2 does not light line 1', () async {
    final overlay = caption(CaptionHighlightStyle.colour);
    final img = await paint(overlay, 0.75);
    final area = lineOne(overlay);
    expect(count(img, area, isWhite), greaterThan(100));
    expect(count(img, area, isRed), 0);
  });

  test('a word popping on line 2 paints no copy of line 1', () async {
    // Line 2 at the peak of its swell. The word is bigger, so its own shadow
    // legitimately reaches a little further — but nothing of line 1 may be
    // drawn in line 2's colour.
    final overlay = caption(CaptionHighlightStyle.pop);
    final area = lineOne(overlay);
    final popping = await paint(overlay, 0.5 + kHighlightPopSeconds / 2);
    expect(count(popping, area, isWhite), greaterThan(100));
    expect(count(popping, area, isRed), 0);
  });

  test('with nothing lit, letter by letter draws what the whole caption draws',
      () async {
    // Drawn whole, every shadow lies under every letter. Drawn letter by
    // letter with each letter's shadow beside its ink, line 2's shadow was
    // painted over line 1's letters — a grey smudge, measured up to 60/255
    // on white, on every highlighted caption and every exported multi-line
    // text with a shadow.
    final overlay = caption(CaptionHighlightStyle.colour);
    final layout = TextOverlayLayout.measure(overlay, canvas);
    // Before the first word: the letter-by-letter path, nothing lit.
    final byLetter = await paint(overlay, -0.5);
    final flat = await paint(overlay.copyWith(highlight: CaptionHighlight.none), -0.5);
    var onLetters = 0;
    var worst = 0;
    for (var y = 0; y < layout.boxSize.height.floor(); y++) {
      for (var x = 0; x < layout.boxSize.width.floor(); x++) {
        final o = (y * flat.width + x) * 4;
        var d = 0;
        for (var c = 0; c < 4; c++) {
          final v = (byLetter.data.getUint8(o + c) - flat.data.getUint8(o + c)).abs();
          if (v > d) d = v;
        }
        if (d > worst) worst = d;
        // The letters themselves — white fill — must be untouched.
        final letter = flat.data.getUint8(o) > 200 && flat.data.getUint8(o + 3) > 200;
        if (letter && d > 12) onLetters++;
      }
    }
    expect(onLetters, 0);
    // What remains is the halo: each letter casts its own shadow, and
    // neighbouring shadows overlap at their soft edges — the residual the
    // atlas reassembly tests accept at the same bound.
    expect(worst, lessThanOrEqualTo(60));
  });
}
