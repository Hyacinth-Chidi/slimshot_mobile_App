import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_placement.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_preset_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/text_animation_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/text_look.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/utils/font_utils.dart';

/// Caption presets: a whole look and a highlight, one tap. Every rule a preset
/// could break silently is pinned across the catalog, so one added later
/// inherits the checks.
void main() {
  test('the catalog is not empty and every id is unique', () {
    expect(kCaptionPresets.length, greaterThanOrEqualTo(6));
    final ids = kCaptionPresets.map((p) => p.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('the first preset is the default style: Bubble, a purple pill', () {
    // What a project's first set is generated in, and the first tile of the
    // grid, so "the first one" and "what I got" are the same thing.
    final first = kCaptionPresets.first;
    expect(first, same(kDefaultCaptionPreset));
    expect(first.id, 'bubble');
    expect(first.highlight.style, CaptionHighlightStyle.pill);
    expect(first.highlight.color, const Color(0xFFBF5AF2));
    // A set built with nothing said wears it.
    final made = buildCaptionOverlays(
      drafts: const [
        CaptionDraft(text: 'Hello', start: Duration.zero, end: Duration(seconds: 1), words: []),
      ],
      setId: 's',
      lane: 0,
      canvasSize: const Size(400, 700),
    ).single;
    expect(first.isAppliedTo(made), isTrue);
  });

  test('Classic is still offered: the look the first device run approved', () {
    final classic = kCaptionPresets.firstWhere((p) => p.id == 'classic');
    expect(classic.look, kCaptionClassicLook);
    expect(classic.highlight, CaptionHighlight.none);
    expect(classic.look.strokeWidth, greaterThan(0));
  });

  group('the style a new set is generated in', () {
    TextOverlayModel caption(String id, int startMs, TextLook look, CaptionHighlight highlight) =>
        look.applyTo(TextOverlayModel(
          id: id,
          text: id,
          startTime: Duration(milliseconds: startMs),
          endTime: Duration(milliseconds: startMs + 500),
          captionSetId: 's',
          highlight: highlight,
        ));
    const karaoke = CaptionHighlight(style: CaptionHighlightStyle.karaoke);
    const tuned = TextLook(fontFamily: 'Poppins', color: Color(0xFF30D158));

    test("a project's first set wears the default style", () {
      final style = captionStyleForNewSet([
        TextOverlayModel(id: 'title', text: 'Title'),
      ]);
      expect(style.look, kDefaultCaptionLook);
      expect(style.highlight, kDefaultCaptionHighlight);
    });

    test("a regeneration keeps the set's style, hand tuning and all", () {
      // Regenerating for a better transcript must not undo the styling.
      final style = captionStyleForNewSet([
        TextOverlayModel(id: 'title', text: 'Title'),
        caption('a', 0, tuned, karaoke),
      ]);
      expect(style.look, tuned);
      expect(style.highlight, karaoke);
    });

    test('read from the earliest caption, not the first in the list', () {
      // Splits and merges reorder the list; time does not move.
      final style = captionStyleForNewSet([
        caption('later', 2000, kCaptionClassicLook, CaptionHighlight.none),
        caption('earliest', 0, tuned, karaoke),
      ]);
      expect(style.look, tuned);
      expect(style.highlight, karaoke);
    });
  });

  test('every font is one the app can load', () {
    for (final p in kCaptionPresets) {
      expect(allFonts, contains(p.look.fontFamily), reason: p.id);
    }
  });

  test('every animation resolves in its own slot and can be picked', () {
    for (final p in kCaptionPresets) {
      for (final (id, slot) in [
        (p.look.inAnimation, TextAnimationCategory.inAnim),
        (p.look.outAnimation, TextAnimationCategory.outAnim),
        (p.look.loopAnimation, TextAnimationCategory.loop),
      ]) {
        if (id == 'none') continue;
        final anim = resolveTextAnimation(id, slot);
        expect(anim, isNotNull, reason: '${p.id} $id');
        expect(anim!.isSelectable, isTrue, reason: '${p.id} $id');
      }
    }
  });

  test("every shadow is inside the Style tab's own ranges", () {
    for (final p in kCaptionPresets) {
      final l = p.look;
      expect(l.shadowOpacity, inInclusiveRange(0, 1), reason: p.id);
      expect(l.shadowBlur, inInclusiveRange(0, kTextShadowMaxBlur), reason: p.id);
      expect(l.shadowDistance, inInclusiveRange(0, kTextShadowMaxDistance), reason: p.id);
      expect(l.shadowAngle, greaterThanOrEqualTo(0), reason: p.id);
      expect(l.shadowAngle, lessThan(360), reason: p.id);
    }
  });

  test('a highlight that lights in a colour is never the text\'s own colour', () {
    // A word lit in the colour it already wears does not light at all — and a
    // pill the colour of its letters swallows them.
    for (final p in kCaptionPresets) {
      if (!captionHighlightUsesColor(p.highlight.style)) continue;
      expect(p.highlight.color, isNot(p.look.color), reason: p.id);
      expect(p.highlight.color.a, 1.0, reason: p.id);
    }
  });

  test('a lit word is never the colour of its own glow', () {
    // Neon shipped lighting its word in exactly the glow colour: the fill's
    // edges melted into the halo around it and the letterforms vanished.
    for (final p in kCaptionPresets) {
      if (!captionHighlightUsesColor(p.highlight.style)) continue;
      final glows = p.look.shadowColor.a > 0 &&
          p.look.shadowDistance == 0 &&
          p.look.shadowBlur > 0;
      if (!glows) continue;
      expect(p.highlight.color, isNot(p.look.shadowColor), reason: p.id);
    }
  });

  test('a word lit in a colour is lit, not dimmed', () {
    // The lit word sits beside white neighbours; a dark fill reads as the
    // word going out. Karaoke's yellow is 0.84, white 1.0 — Neon's old blue
    // was 0.45, the darkest thing on its line. Only the styles that recolour
    // the **fill**: a pill's colour is a box behind white text, and a box
    // may be dark — Bubble's purple is.
    const fillStyles = {
      CaptionHighlightStyle.colour,
      CaptionHighlightStyle.pop,
      CaptionHighlightStyle.karaoke,
    };
    for (final p in kCaptionPresets) {
      if (!fillStyles.contains(p.highlight.style)) continue;
      final c = p.highlight.color;
      final luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
      expect(luminance, greaterThan(0.55), reason: '${p.id}: $c');
    }
  });

  test('no two presets are the same look under different names', () {
    for (var i = 0; i < kCaptionPresets.length; i++) {
      for (var j = i + 1; j < kCaptionPresets.length; j++) {
        final a = kCaptionPresets[i];
        final b = kCaptionPresets[j];
        expect(
          a.look.sameLookAs(b.look) && a.highlight == b.highlight,
          isFalse,
          reason: '${a.id} / ${b.id}',
        );
      }
    }
  });

  test('a preset knows a caption wearing it, and only that one', () {
    final caption = TextOverlayModel(id: 'c', text: 'Hi', captionSetId: 's');
    for (final p in kCaptionPresets) {
      final worn = p.look.applyTo(caption).copyWith(highlight: p.highlight);
      for (final q in kCaptionPresets) {
        expect(q.isAppliedTo(worn), q.id == p.id, reason: '${q.id} on ${p.id}');
      }
    }
  });

  test('every sample has words to light', () {
    for (final p in kCaptionPresets) {
      expect(p.sampleText.trim().split(RegExp(r'\s+')).length, greaterThanOrEqualTo(2),
          reason: p.id);
    }
  });
}
