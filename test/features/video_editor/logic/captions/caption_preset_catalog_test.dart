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

  test('the first preset is the default look, with no highlight', () {
    // A set generated without touching the grid looks exactly as it did
    // before presets existed — the look the device run approved.
    final first = kCaptionPresets.first;
    expect(first.highlight, CaptionHighlight.none);
    final made = buildCaptionOverlays(
      drafts: const [
        CaptionDraft(text: 'Hello', start: Duration.zero, end: Duration(seconds: 1), words: []),
      ],
      setId: 's',
      lane: 0,
      canvasSize: const Size(400, 700),
    ).single;
    expect(first.look.sameLookAs(TextLook.of(made)), isTrue);
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
