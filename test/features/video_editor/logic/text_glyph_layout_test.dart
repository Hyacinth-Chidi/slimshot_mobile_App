// Explicit: this test iterates grapheme clusters itself. `material.dart`
// happens to re-export `characters`, but relying on that would make the test
// depend on a Flutter implementation detail.
// ignore: unnecessary_import
import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_glyph_layout.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

import '../../../support/test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A bundled font, not a Google one — see test/support/test_fonts.dart.
  // Metrics differ from any particular user font, so these tests assert on
  // relationships (ordering, containment, proportion), never on absolute
  // pixel widths.
  TextOverlayModel overlayWith(String text) => TextOverlayModel(
        id: 't',
        text: text,
        fontFamily: kTestFontFamily,
        referenceCanvasSize: const Size(400, 700),
      );

  group('layoutTextGlyphs', () {
    test('returns one box per character, in order', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.length, 3);
      expect(glyphs.map((g) => g.charIndex), [0, 1, 2]);
    });

    test('lays characters out left to right without overlapping', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs[0].inkRect.left, lessThan(glyphs[1].inkRect.left));
      expect(glyphs[1].inkRect.left, lessThan(glyphs[2].inkRect.left));
      // Adjacent glyphs may touch but must not overlap.
      expect(glyphs[0].inkRect.right, lessThanOrEqualTo(glyphs[1].inkRect.left + 0.01));
    });

    test('skips whitespace, which has no ink to draw', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('a b'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.map((g) => g.charIndex), [0, 2]);
    });

    test('a second line sits below the first', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('a\nb'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.length, 2);
      expect(glyphs[1].inkRect.top, greaterThan(glyphs[0].inkRect.bottom - 0.01));
    });

    test('padded rect grows by the shadow padding on every side', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('a'),
        canvasSize: const Size(400, 700),
        shadowPadding: 4,
      );
      final g = glyphs.single;
      expect(g.paddedRect.left, closeTo(g.inkRect.left - 4, 1e-9));
      expect(g.paddedRect.top, closeTo(g.inkRect.top - 4, 1e-9));
      expect(g.paddedRect.right, closeTo(g.inkRect.right + 4, 1e-9));
      expect(g.paddedRect.bottom, closeTo(g.inkRect.bottom + 4, 1e-9));
    });

    test('glyph boxes sit inside the measured text box', () {
      const canvas = Size(400, 700);
      final overlay = overlayWith('hello');
      final glyphs = layoutTextGlyphs(
        overlay: overlay,
        canvasSize: canvas,
        shadowPadding: 0,
      );
      for (final g in glyphs) {
        expect(g.inkRect.left, greaterThanOrEqualTo(-0.01));
        expect(g.inkRect.top, greaterThanOrEqualTo(-0.01));
      }
    });

    test('empty text produces no glyphs', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith(''),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs, isEmpty);
    });
  });

  // Iterating UTF-16 code units selects half a surrogate pair, and
  // `getBoxesForSelection` returns nothing for half a character — so an emoji
  // silently vanished from the exported atlas. These pin cluster iteration.
  group('layoutTextGlyphs — grapheme clusters', () {
    test('an emoji is one glyph, not two halves and not none', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('Hello 👍'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      // Five letters plus the emoji; the space is skipped as whitespace.
      expect(glyphs.length, 6);
      // The emoji's cluster starts at code unit 6, after "Hello ".
      expect(glyphs.last.charIndex, 6);
    });

    test('the emoji glyph has real width', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('Hello 👍'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.last.inkRect.width, greaterThan(0));
      expect(glyphs.last.inkRect.height, greaterThan(0));
    });

    test('charIndex values are strictly increasing and never overlap', () {
      // A skin-tone modifier, a flag (two regional indicators) and a combining
      // accent are each one cluster spanning several code units.
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('a👍🏽b🇬🇧éc'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.length, greaterThan(1));
      for (var i = 1; i < glyphs.length; i++) {
        expect(
          glyphs[i].charIndex,
          greaterThan(glyphs[i - 1].charIndex),
          reason: 'charIndex must advance by whole clusters',
        );
      }
      // Every charIndex must be the *start* of a cluster in the source text:
      // splitting a cluster would land an index mid-pair.
      final clusterStarts = <int>[];
      var offset = 0;
      for (final cluster in 'a👍🏽b🇬🇧éc'.characters) {
        clusterStarts.add(offset);
        offset += cluster.length;
      }
      for (final g in glyphs) {
        expect(clusterStarts, contains(g.charIndex));
      }
    });

    test('a skin-tone modifier stays one glyph', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('👍🏽'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.length, 1);
      expect(glyphs.single.charIndex, 0);
    });
  });
}
