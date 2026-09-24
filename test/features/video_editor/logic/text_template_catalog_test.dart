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

    test('carries the whole shadow, not just its colour', () {
      final o = applied();
      expect(o.shadowOpacity, template.shadowOpacity);
      expect(o.shadowBlurRadius, template.shadowBlur);
      expect(o.shadowDistance, template.shadowDistance);
      expect(o.shadowAngle, template.shadowAngle);
    });
  });

  test("every template's shadow is one the controls could have set", () {
    // A template's shadow is tuned like any other, so it must sit inside the
    // Style tab's own ranges — or reopening a draft would clamp it into a
    // different look than the one the tile promised.
    for (final t in kTextTemplates) {
      expect(t.shadowOpacity, inInclusiveRange(0, 1), reason: t.id);
      expect(t.shadowBlur, inInclusiveRange(0, kTextShadowMaxBlur),
          reason: t.id);
      expect(t.shadowDistance, inInclusiveRange(0, kTextShadowMaxDistance),
          reason: t.id);
      expect(t.shadowAngle, inInclusiveRange(0, 360), reason: t.id);
      final o = t.apply(
        id: 'x',
        startTime: Duration.zero,
        endTime: const Duration(seconds: 3),
      );
      expect(TextOverlayModel.fromJson(o.toJson()).toJson(), o.toJson(),
          reason: '${t.id} survives a draft unchanged');
    }
  });

  group('restyling a text that already exists — type, then choose', () {
    // Everything a user did that is not the look.
    TextOverlayModel typed() => TextOverlayModel(
          id: 'mine',
          text: 'Hello there',
          fontFamily: 'Lato',
          color: const Color(0xFF123456),
          strokeColor: const Color(0xFF00FF00),
          strokeWidth: 7,
          backgroundColor: const Color(0xFF654321),
          shadowColor: const Color(0xFFFF00FF),
          shadowDistance: 17,
          position: const Offset(30, -40),
          rotation: 0.4,
          boxWidth: 180,
          startTime: const Duration(seconds: 2),
          endTime: const Duration(seconds: 9),
          laneIndex: 2,
          referenceCanvasSize: const Size(400, 700),
          inAnimation: 'spin_in',
          animationInDuration: 2.5,
          animationOutDuration: 2.5,
        );

    test('keeps the words, the timing and the place', () {
      for (final t in kTextTemplates) {
        final o = t.restyle(typed());
        final mine = typed();
        expect(o.id, mine.id, reason: t.id);
        expect(o.text, mine.text, reason: t.id);
        expect(o.startTime, mine.startTime, reason: t.id);
        expect(o.endTime, mine.endTime, reason: t.id);
        expect(o.position, mine.position, reason: t.id);
        expect(o.rotation, mine.rotation, reason: t.id);
        expect(o.boxWidth, mine.boxWidth, reason: t.id);
        expect(o.laneIndex, mine.laneIndex, reason: t.id);
        expect(o.referenceCanvasSize, mine.referenceCanvasSize, reason: t.id);
      }
    });

    test('takes the whole look', () {
      for (final t in kTextTemplates) {
        final o = t.restyle(typed());
        expect(o.fontFamily, t.fontFamily, reason: t.id);
        expect(o.color, t.color, reason: t.id);
        expect(o.strokeColor, t.strokeColor, reason: t.id);
        expect(o.strokeWidth, t.strokeWidth, reason: t.id);
        expect(o.backgroundColor, t.backgroundColor, reason: t.id);
        expect(o.borderRadius, t.borderRadius, reason: t.id);
        expect(o.backgroundPadding, t.backgroundPadding, reason: t.id);
        expect(o.shadowColor, t.shadowColor, reason: t.id);
        expect(o.shadowOpacity, t.shadowOpacity, reason: t.id);
        expect(o.shadowBlurRadius, t.shadowBlur, reason: t.id);
        expect(o.shadowDistance, t.shadowDistance, reason: t.id);
        expect(o.shadowAngle, t.shadowAngle, reason: t.id);
        expect(o.textAlign, t.textAlign, reason: t.id);
        expect(o.scale, t.scale, reason: t.id);
        expect(o.inAnimation, t.inAnimation, reason: t.id);
        expect(o.outAnimation, t.outAnimation, reason: t.id);
        expect(o.loopAnimation, t.loopAnimation, reason: t.id);
        // The template's animations at their own pace, not the old speed.
        expect(o.animationInDuration, kTextAnimationNaturalSpeed, reason: t.id);
        expect(o.animationOutDuration, kTextAnimationNaturalSpeed,
            reason: t.id);
        expect(o.loopSpeed, kTextAnimationNaturalSpeed, reason: t.id);
      }
    });

    test('changing templates leaves nothing of the one before', () {
      // Every pair, both orders: an outline, a box or a shadow the first
      // template brought must not survive into the second's look.
      for (final a in kTextTemplates) {
        for (final b in kTextTemplates) {
          expect(
            b.restyle(a.restyle(typed())).toJson(),
            b.restyle(typed()).toJson(),
            reason: '${a.id} then ${b.id}',
          );
        }
      }
    });

    test('a template knows a text wearing it — and no other does', () {
      // What the Templates tab highlights. It also means no two templates
      // are the same look under different names.
      for (final t in kTextTemplates) {
        final worn = t.restyle(typed());
        for (final u in kTextTemplates) {
          expect(u.isAppliedTo(worn), u.id == t.id,
              reason: '${u.id} on a text wearing ${t.id}');
        }
      }
    });

    test('still recognised after a resize — size is placement, not look', () {
      final t = kTextTemplates.first;
      expect(t.isAppliedTo(t.restyle(typed()).copyWith(scale: 3.3)), isTrue);
    });

    test('a hand edit to the look makes it no template', () {
      final t = kTextTemplates.first;
      final edited = t.restyle(typed()).copyWith(
            color: const Color(0xFF010203),
          );
      expect(t.isAppliedTo(edited), isFalse);
    });

    test('a new text is the same thing: an empty text, restyled', () {
      // One definition of what a template does to a text, whichever way in.
      for (final t in kTextTemplates) {
        final made = t.apply(
          id: 'n',
          startTime: Duration.zero,
          endTime: const Duration(seconds: 3),
          canvasSize: const Size(400, 700),
        );
        expect(t.isAppliedTo(made), isTrue, reason: t.id);
      }
    });
  });
}
