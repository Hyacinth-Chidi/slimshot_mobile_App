import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

/// The word being spoken lights up: one catalog of what each style does.
void main() {
  // Three words: 0.1–0.4, 0.5–0.8, 0.9–1.2, in a caption 1.5s long.
  const words = [
    WordSpan(0.1, 0.4),
    WordSpan(0.5, 0.8),
    WordSpan(0.9, 1.2),
  ];
  const span = 1.5;

  WordHighlightState at(CaptionHighlightStyle style, double t, int i) =>
      wordHighlightStateAt(
        style: style,
        t: t,
        words: words,
        index: i,
        spanSeconds: span,
      );

  group('the model', () {
    test('none is the default, and writes nothing', () {
      final text = TextOverlayModel(id: 't', text: 'hi');
      expect(text.highlight, CaptionHighlight.none);
      expect(text.toJson().containsKey('highlight'), isFalse);
      expect(TextOverlayModel.fromJson(text.toJson()).highlight, CaptionHighlight.none);
    });

    test('a highlight round-trips on a text and on the settings', () {
      const h = CaptionHighlight(
        style: CaptionHighlightStyle.karaoke,
        color: Color(0xFFFFD60A),
      );
      final text = TextOverlayModel(id: 't', text: 'hi', highlight: h);
      expect(TextOverlayModel.fromJson(text.toJson()).highlight, h);
      const settings = CaptionSettings(setId: 's', highlight: h);
      expect(CaptionSettings.fromJson(settings.toJson()), settings);
      expect(const CaptionSettings(setId: 's').toJson().containsKey('highlight'), isFalse);
    });

    test('an unknown style or a missing colour reads as something drawable', () {
      expect(
        CaptionHighlight.fromJson({'style': 'sparkle', 'color': 0xFF00FF00}),
        CaptionHighlight.none,
      );
      expect(
        CaptionHighlight.fromJson({'style': 'colour'}),
        const CaptionHighlight(style: CaptionHighlightStyle.colour),
      );
      expect(CaptionHighlight.fromJson('junk'), CaptionHighlight.none);
    });

    test('every style but none is selectable, with a label', () {
      for (final s in CaptionHighlightStyle.values) {
        expect(captionHighlightLabel(s), isNotEmpty, reason: s.name);
      }
      expect(kSelectableHighlightStyles, isNot(contains(CaptionHighlightStyle.none)));
      expect(kSelectableHighlightStyles.length, CaptionHighlightStyle.values.length - 1);
    });
  });

  group('which word is active', () {
    test('from its start until the next word starts', () {
      expect(at(CaptionHighlightStyle.colour, 0.1, 0).highlighted, isTrue);
      expect(at(CaptionHighlightStyle.colour, 0.45, 0).highlighted, isTrue);
      expect(at(CaptionHighlightStyle.colour, 0.5, 0).highlighted, isFalse);
      expect(at(CaptionHighlightStyle.colour, 0.5, 1).highlighted, isTrue);
    });

    test('the last word stays lit to the end of the caption', () {
      expect(at(CaptionHighlightStyle.colour, 1.3, 2).highlighted, isTrue);
      expect(at(CaptionHighlightStyle.colour, 1.49, 2).highlighted, isTrue);
    });

    test('before the first word nothing is active', () {
      for (var i = 0; i < 3; i++) {
        expect(at(CaptionHighlightStyle.colour, 0.05, i).highlighted, isFalse);
      }
    });

    test('a word timed past the caption still ends with the caption', () {
      const late = [WordSpan(0.1, 0.4), WordSpan(1.4, 2.0)];
      final s = wordHighlightStateAt(
        style: CaptionHighlightStyle.colour,
        t: 1.49,
        words: late,
        index: 1,
        spanSeconds: span,
      );
      expect(s.highlighted, isTrue);
    });

    test('none highlights nothing and rests every channel', () {
      final s = at(CaptionHighlightStyle.none, 0.2, 0);
      expect(s, WordHighlightState.resting);
    });
  });

  group('pop', () {
    test('swells to 115% and settles back within 0.25s, about the word', () {
      expect(at(CaptionHighlightStyle.pop, 0.1, 0).scale, closeTo(1.0, 1e-9));
      expect(
        at(CaptionHighlightStyle.pop, 0.1 + kHighlightPopSeconds / 2, 0).scale,
        closeTo(kHighlightPopScale, 1e-9),
      );
      expect(at(CaptionHighlightStyle.pop, 0.4, 0).scale, closeTo(1.0, 1e-9));
      expect(at(CaptionHighlightStyle.pop, 0.2, 0).highlighted, isTrue);
      expect(at(CaptionHighlightStyle.pop, 0.2, 1).scale, 1.0);
    });
  });

  group('pill', () {
    test('a box behind the active word, fading in, and the text keeps its colour', () {
      expect(at(CaptionHighlightStyle.pill, 0.1, 0).pill, closeTo(0, 1e-9));
      expect(
        at(CaptionHighlightStyle.pill, 0.1 + kHighlightRampSeconds / 2, 0).pill,
        closeTo(0.5, 1e-9),
      );
      expect(at(CaptionHighlightStyle.pill, 0.3, 0).pill, 1.0);
      expect(at(CaptionHighlightStyle.pill, 0.3, 0).highlighted, isFalse);
      expect(at(CaptionHighlightStyle.pill, 0.3, 1).pill, 0.0);
    });
  });

  group('karaoke', () {
    test('sweeps through the word as it is spoken; spoken words stay lit', () {
      expect(at(CaptionHighlightStyle.karaoke, 0.1, 0).fill, 0.0);
      expect(at(CaptionHighlightStyle.karaoke, 0.25, 0).fill, closeTo(0.5, 1e-9));
      expect(at(CaptionHighlightStyle.karaoke, 0.4, 0).fill, 1.0);
      expect(at(CaptionHighlightStyle.karaoke, 0.45, 0).fill, 1.0);
      expect(at(CaptionHighlightStyle.karaoke, 0.7, 0).fill, 1.0);
      expect(at(CaptionHighlightStyle.karaoke, 0.7, 2).fill, 0.0);
    });

    test('a word of no length is lit the instant it starts', () {
      const instant = [WordSpan(0.5, 0.5)];
      final s = wordHighlightStateAt(
        style: CaptionHighlightStyle.karaoke,
        t: 0.5,
        words: instant,
        index: 0,
        spanSeconds: span,
      );
      expect(s.fill, 1.0);
    });
  });

  group('reveal', () {
    test('a word appears as it is spoken and stays', () {
      expect(at(CaptionHighlightStyle.reveal, 0.05, 0).opacity, 0.0);
      expect(
        at(CaptionHighlightStyle.reveal, 0.1 + kHighlightRampSeconds / 2, 0).opacity,
        closeTo(0.5, 1e-9),
      );
      expect(at(CaptionHighlightStyle.reveal, 0.7, 0).opacity, 1.0);
      expect(at(CaptionHighlightStyle.reveal, 0.7, 2).opacity, 0.0);
      expect(at(CaptionHighlightStyle.reveal, 0.7, 1).highlighted, isFalse);
    });
  });

  group('focus', () {
    test('words not being spoken are dimmed', () {
      expect(at(CaptionHighlightStyle.focus, 0.6, 1).opacity, 1.0);
      expect(at(CaptionHighlightStyle.focus, 0.6, 0).opacity, kHighlightFocusDim);
      expect(at(CaptionHighlightStyle.focus, 0.6, 2).opacity, kHighlightFocusDim);
    });
  });

  group('mapping glyphs to words', () {
    const captionWords = [
      CaptionWord(textStart: 0, textEnd: 5, start: Duration.zero, end: Duration(milliseconds: 300)),
      CaptionWord(textStart: 6, textEnd: 11, start: Duration(milliseconds: 400), end: Duration(milliseconds: 700)),
    ];

    test('a glyph belongs to the word whose range holds it', () {
      expect(wordIndexForChar(captionWords, 0), 0);
      expect(wordIndexForChar(captionWords, 4), 0);
      expect(wordIndexForChar(captionWords, 6), 1);
      expect(wordIndexForChar(captionWords, 10), 1);
    });

    test('a glyph between words belongs to none', () {
      expect(wordIndexForChar(captionWords, 5), -1);
      expect(wordIndexForChar(captionWords, 11), -1);
    });

    test('word spans are the words in seconds', () {
      expect(wordSpansOf(captionWords), const [WordSpan(0.0, 0.3), WordSpan(0.4, 0.7)]);
    });
  });

  group('the pill', () {
    test('wraps the word with room on every side, rounded', () {
      const ink = Rect.fromLTWH(10, 20, 60, 30);
      final pill = captionPillRect(ink, glyphHeight: 30);
      expect(pill.left, lessThan(ink.left));
      expect(pill.right, greaterThan(ink.right));
      expect(pill.top, lessThan(ink.top));
      expect(pill.bottom, greaterThan(ink.bottom));
      expect(pill.center, ink.center);
      expect(captionPillRadius(30), greaterThan(0));
      expect(captionPillRadius(30), lessThanOrEqualTo(pill.height / 2));
    });
  });
}
