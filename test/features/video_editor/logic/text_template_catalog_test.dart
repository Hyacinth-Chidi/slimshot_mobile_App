import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_animation_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/logic/text_template_catalog.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/utils/font_utils.dart';

/// Text templates: a complete starting look for a new text, one tap.
///
/// Every rule here is one a template could break silently — a font the app
/// cannot load, an animation the user could not have picked themselves, a
/// look the export cannot reproduce — so each is pinned across the whole
/// catalog, and a template added later inherits the checks.
void main() {
  test('the catalog is not empty and every id is unique', () {
    expect(kTextTemplates, isNotEmpty);
    final ids = kTextTemplates.map((t) => t.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('every template has a name and sample words for its tile', () {
    for (final t in kTextTemplates) {
      expect(t.name.trim(), isNotEmpty, reason: t.id);
      expect(t.sampleText.trim(), isNotEmpty, reason: t.id);
    }
  });

  test('every font is one the app can load', () {
    // A family outside `allFonts` resolves through `GoogleFonts.getFont`,
    // which throws for a name it does not know.
    for (final t in kTextTemplates) {
      expect(allFonts, contains(t.fontFamily), reason: t.id);
    }
  });

  test('every animation is one the user could pick, in its own slot', () {
    // An id resolved in the wrong slot is refused by `resolveTextAnimation`,
    // and a template would ship a still text with nothing explaining why. An
    // unselectable one (colour fill, colour cycle) would animate to nothing.
    void check(String id, TextAnimationCategory slot, String templateId) {
      if (id == 'none') return;
      final resolved = resolveTextAnimation(id, slot);
      expect(resolved, isNotNull, reason: '$templateId: $id in $slot');
      expect(resolved!.isSelectable, isTrue, reason: '$templateId: $id');
    }

    for (final t in kTextTemplates) {
      check(t.inAnimation, TextAnimationCategory.inAnim, t.id);
      check(t.outAnimation, TextAnimationCategory.outAnim, t.id);
      check(t.loopAnimation, TextAnimationCategory.loop, t.id);
    }
  });

  test('a boxed template animates as a whole block, never per character', () {
    // Per-character animation cannot run over a background box: the glyph
    // pass draws letters only, so export falls back to the flat raster and
    // warns. A boxed template with a per-glyph animation would raise that
    // warning on every export it was used in.
    for (final t in kTextTemplates) {
      if (t.backgroundColor == Colors.transparent) continue;
      for (final (id, slot) in [
        (t.inAnimation, TextAnimationCategory.inAnim),
        (t.outAnimation, TextAnimationCategory.outAnim),
        (t.loopAnimation, TextAnimationCategory.loop),
      ]) {
        final anim = resolveTextAnimation(id, slot);
        expect(
          anim?.isPerGlyph ?? false,
          isFalse,
          reason: '${t.id} is boxed, so $id must not be per-glyph',
        );
      }
    }
  });

  test('every template sits on the canvas, at a size the pinch allows', () {
    for (final t in kTextTemplates) {
      expect(t.placement.dx.abs(), lessThanOrEqualTo(0.5), reason: t.id);
      expect(t.placement.dy.abs(), lessThanOrEqualTo(0.5), reason: t.id);
      expect(t.scale, inInclusiveRange(kMinTextScale, kMaxTextScale),
          reason: t.id);
    }
  });

  group('applying a template', () {
    final template = kTextTemplates.first;
    const canvas = Size(400, 700);

    TextOverlayModel applied({Size? canvasSize = canvas}) => template.apply(
          id: 'new',
          startTime: const Duration(seconds: 3),
          endTime: const Duration(seconds: 6),
          canvasSize: canvasSize,
        );

    test('makes an EMPTY text — the sample words are only the tile\'s', () {
      // Text is created empty so that one left empty is deleted when the
      // editor closes: no placeholder words reach an export. A template that
      // inserted its sample would be exactly the ghost that rule prevents.
      expect(applied().text, isEmpty);
    });

    test('carries the whole look', () {
      final o = applied();
      expect(o.fontFamily, template.fontFamily);
      expect(o.color, template.color);
      expect(o.strokeColor, template.strokeColor);
      expect(o.strokeWidth, template.strokeWidth);
      expect(o.backgroundColor, template.backgroundColor);
      expect(o.shadowColor, template.shadowColor);
      expect(o.textAlign, template.textAlign);
      expect(o.scale, template.scale);
      expect(o.inAnimation, template.inAnimation);
      expect(o.outAnimation, template.outAnimation);
      expect(o.loopAnimation, template.loopAnimation);
      expect(o.startTime, const Duration(seconds: 3));
      expect(o.endTime, const Duration(seconds: 6));
      expect(o.id, 'new');
    });

    test('places it by canvas fractions, so it lands alike on any device', () {
      final o = applied();
      expect(o.referenceCanvasSize, canvas);
      expect(o.position.dx, closeTo(template.placement.dx * canvas.width, 1e-9));
      expect(o.position.dy, closeTo(template.placement.dy * canvas.height, 1e-9));
    });

    test('centres it when the canvas is not known yet', () {
      expect(applied(canvasSize: null).position, Offset.zero);
    });

    test('blurs a shadow exactly as the editor does, and no other way', () {
      // The atlas reassembly tests are calibrated for the one blur the editor
      // can emit; a template choosing its own would leave that measured
      // territory.
      for (final t in kTextTemplates) {
        final o = t.apply(
          id: 'x',
          startTime: Duration.zero,
          endTime: const Duration(seconds: 3),
        );
        expect(
          o.shadowBlurRadius,
          t.shadowColor == Colors.transparent ? 0.0 : kTextShadowBlurRadius,
          reason: t.id,
        );
      }
    });
  });
}
