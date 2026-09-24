import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_animation_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';

import '../../../support/test_fonts.dart';

/// What the preview painter resolves and what the export's Kotlin
/// `TextAnimationTiming` resolves have to be the same thing. These tests hold
/// the Dart end of that: the painter must return the **catalog's** own state
/// for a playhead, and it must resolve ids **by slot** — the two ways this
/// could silently drift into animating differently from the file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A bundled font, not a Google one — see test/support/test_fonts.dart.
  const canvas = Size(400, 700);

  TextOverlayModel textWith({
    String text = 'abc',
    String inAnimation = 'none',
    String outAnimation = 'none',
    String loopAnimation = 'none',
    double speed = 1.0,
    double loopSpeed = 1.0,
    Duration start = Duration.zero,
    Duration end = const Duration(seconds: 5),
    bool shadow = false,
  }) {
    return TextOverlayModel(
      id: 't',
      text: text,
      fontFamily: kTestFontFamily,
      referenceCanvasSize: canvas,
      // A shadow is what makes the bleed padding non-zero, which is the only
      // thing that separates a glyph's padded cell from its ink rect.
      shadowColor: shadow ? const Color(0xFF000000) : Colors.transparent,
      shadowBlurRadius: shadow ? 8.0 : 0.0,
      inAnimation: inAnimation,
      outAnimation: outAnimation,
      loopAnimation: loopAnimation,
      animationInDuration: speed,
      animationOutDuration: speed,
      loopSpeed: loopSpeed,
      startTime: start,
      endTime: end,
    );
  }

  int glyphCountOf(TextOverlayModel overlay) =>
      TextOverlayPainter.glyphBoxesFor(overlay, canvas).length;

  group('timing resolution', () {
    test('an unanimated overlay resolves no live window', () {
      final overlay = textWith();
      final timing = TextOverlayPainter.timingFor(
        overlay,
        glyphCountOf(overlay),
      );
      expect(timing.isActive, isFalse);
      // Nothing live means the painter takes its static path, which is the
      // regression bar: text with no animation must draw as it always did.
      expect(timing.stateAt(1.0, 0, 3).opacity, 1.0);
      expect(timing.stateAt(1.0, 0, 3).scale, 1.0);
    });

    test('the painter returns the catalog\'s own state for a playhead', () {
      final overlay = textWith(
        inAnimation: 'typing',
        end: const Duration(seconds: 5),
      );
      final glyphCount = glyphCountOf(overlay);
      final timing = TextOverlayPainter.timingFor(overlay, glyphCount);

      final anim = resolveTextAnimation('typing', TextAnimationCategory.inAnim)!;
      final windowSeconds = anim.naturalDuration(glyphCount);
      expect(timing.inSeconds, closeTo(windowSeconds, 1e-9));

      // A third of the way through the in-window, every glyph must match what
      // the catalog says at that same `p`. If the painter ever grew its own
      // idea of progress — a different clock, a different window — this is
      // what catches it.
      final t = windowSeconds / 3;
      for (var i = 0; i < glyphCount; i++) {
        final expected = anim.stateAt(t / windowSeconds, i, glyphCount);
        final actual = timing.stateAt(t, i, glyphCount);
        expect(actual.opacity, closeTo(expected.opacity, 1e-9), reason: 'i=$i');
        expect(actual.offsetY, closeTo(expected.offsetY, 1e-9), reason: 'i=$i');
        expect(actual.scale, closeTo(expected.scale, 1e-9), reason: 'i=$i');
      }
    });

    test('speed divides the window, so 2x halves it', () {
      final normal = textWith(inAnimation: 'fade_in');
      final fast = textWith(inAnimation: 'fade_in', speed: 2.0);
      final slow = TextOverlayPainter.timingFor(normal, glyphCountOf(normal));
      final quick = TextOverlayPainter.timingFor(fast, glyphCountOf(fast));
      expect(quick.inSeconds, closeTo(slow.inSeconds / 2, 1e-9));
    });

    test('in and out compress proportionally when they do not fit', () {
      // A span far shorter than the two windows together.
      final overlay = textWith(
        inAnimation: 'fade_in',
        outAnimation: 'fade_out',
        end: const Duration(milliseconds: 200),
      );
      final timing = TextOverlayPainter.timingFor(
        overlay,
        glyphCountOf(overlay),
      );
      expect(timing.inSeconds + timing.outSeconds, closeTo(0.2, 1e-9));
      // Neither is dropped — an export that lost one would differ from the
      // preview with nothing on screen to explain it.
      expect(timing.inSeconds, greaterThan(0));
      expect(timing.outSeconds, greaterThan(0));
    });

    test('a loop runs on its own phase, wrapped by one cycle', () {
      final overlay = textWith(loopAnimation: 'pulse_loop');
      final glyphCount = glyphCountOf(overlay);
      final timing = TextOverlayPainter.timingFor(overlay, glyphCount);
      expect(timing.loopPeriod, greaterThan(0));
      expect(timing.isActive, isTrue);
      // One period apart is the same instant of the motion, or the wrap is a
      // visible jump once a cycle.
      final a = timing.stateAt(0.25, 0, glyphCount);
      final b = timing.stateAt(0.25 + timing.loopPeriod, 0, glyphCount);
      expect(b.scale, closeTo(a.scale, 1e-9));
    });

    test('loopSpeed scales the period, not the in/out windows', () {
      final normal = textWith(inAnimation: 'fade_in', loopAnimation: 'pulse_loop');
      final fast = textWith(
        inAnimation: 'fade_in',
        loopAnimation: 'pulse_loop',
        loopSpeed: 2.0,
      );
      final a = TextOverlayPainter.timingFor(normal, glyphCountOf(normal));
      final b = TextOverlayPainter.timingFor(fast, glyphCountOf(fast));
      expect(b.loopPeriod, closeTo(a.loopPeriod / 2, 1e-9));
      expect(b.inSeconds, closeTo(a.inSeconds, 1e-9));
    });
  });

  group('slot resolution', () {
    // The old widget layer's out-slot switch handled only the `_out`-suffixed
    // names, so a bare `slide_up` sitting in `outAnimation` played nothing.
    // Resolving it by id alone would find the in-variant and *add* an exit
    // animation to a project that never had one.
    test('a bare in-only id in the out slot does not animate', () {
      final overlay = textWith(outAnimation: 'slide_up');
      final timing = TextOverlayPainter.timingFor(
        overlay,
        glyphCountOf(overlay),
      );
      expect(timing.outAnim, isNull);
      expect(timing.outSeconds, 0.0);
      expect(timing.isActive, isFalse);
    });

    // 'fade' meant fadeIn in the in-slot and fadeOut in the out-slot. Taking
    // the in-variant in both would play a saved project's exit backwards.
    test('legacy "fade" resolves per slot, not by name', () {
      final asIn = textWith(inAnimation: 'fade');
      final asOut = textWith(outAnimation: 'fade');
      expect(
        TextOverlayPainter.timingFor(asIn, glyphCountOf(asIn)).inAnim?.id,
        'fade_in',
      );
      expect(
        TextOverlayPainter.timingFor(asOut, glyphCountOf(asOut)).outAnim?.id,
        'fade_out',
      );
    });

    test('legacy "scale" resolves to shrink-away in the out slot', () {
      final overlay = textWith(outAnimation: 'scale');
      final timing = TextOverlayPainter.timingFor(
        overlay,
        glyphCountOf(overlay),
      );
      expect(timing.outAnim?.id, 'zoom_in_out');
    });

    test('an unknown id degrades to no animation rather than throwing', () {
      final overlay = textWith(inAnimation: 'circleOpen');
      final timing = TextOverlayPainter.timingFor(
        overlay,
        glyphCountOf(overlay),
      );
      expect(timing.inAnim, isNull);
      expect(timing.isActive, isFalse);
    });
  });

  group('glyph count', () {
    // The stagger's length comes from the *inked* glyph count, which is what
    // the atlas packs and what the export passes as `n`. Counting the raw
    // string would make every space lengthen the preview but not the file.
    test('whitespace does not count toward the stagger', () {
      final spaced = textWith(text: 'a b');
      final tight = textWith(text: 'ab');
      expect(glyphCountOf(spaced), glyphCountOf(tight));
    });
  });

  TextOverlayPainter painterFor(TextOverlayModel overlay, double t) {
    return TextOverlayPainter(
      overlay: overlay,
      layout: TextOverlayLayout.measure(overlay, canvas),
      canvasSize: canvas,
      positionSeconds: t,
    );
  }

  group('painting', () {
    /// Paints into a recorder and returns how many pixels carry ink.
    ///
    /// Not a golden — the count is compared against another run of the same
    /// painter, never against a stored image, so it says nothing about which
    /// font the machine has.
    Future<int> inkedPixels(TextOverlayPainter painter, Size size) async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final image = await recorder
          .endRecording()
          .toImage(size.width.ceil(), size.height.ceil());
      final bytes = await image.toByteData();
      image.dispose();
      var inked = 0;
      for (var i = 3; i < bytes!.lengthInBytes; i += 4) {
        if (bytes.getUint8(i) > 8) inked++;
      }
      return inked;
    }

    /// Paints into a canvas [pad] pixels larger on every side than the box,
    /// so a glyph displaced outside its resting box is still captured.
    ///
    /// Returns the ink's bounding box in **box coordinates** (the pad is
    /// subtracted back off), or null when nothing was drawn at all.
    Future<Rect?> inkBounds(
      TextOverlayPainter painter,
      Size box, {
      double pad = 120,
    }) async {
      final width = (box.width + pad * 2).ceil();
      final height = (box.height + pad * 2).ceil();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.translate(pad, pad);
      painter.paint(canvas, box);
      final image = await recorder.endRecording().toImage(width, height);
      final bytes = (await image.toByteData())!;
      image.dispose();

      double? left, top, right, bottom;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          if (bytes.getUint8((y * width + x) * 4 + 3) <= 8) continue;
          final bx = x - pad;
          final by = y - pad;
          left = left == null ? bx : math.min(left, bx);
          right = right == null ? bx : math.max(right, bx);
          top = top == null ? by : math.min(top, by);
          bottom = bottom == null ? by : math.max(bottom, by);
        }
      }
      if (left == null) return null;
      return Rect.fromLTRB(left, top!, right! + 1, bottom! + 1);
    }

    // **The clip has to travel with the letter.** In GL the cell *is* the quad,
    // so the two cannot come apart; here they are two canvas calls, and
    // clipping in the resting position while the glyph moves through the clip
    // means the letter is cut away by its own clip. A slide travels 1.5 glyph
    // heights against a few pixels of bleed padding, so under that bug the
    // glyph is not merely cropped — nothing is drawn at all.
    //
    // `fade_in` past its window cannot expose this: offset and scale are both
    // at rest there, which is exactly the case where a resting clip is the
    // right clip.
    test('a mid-slide glyph is drawn, displaced, not clipped away', () async {
      final overlay = textWith(text: 'abcd', inAnimation: 'slide_down');
      final layout = TextOverlayLayout.measure(overlay, canvas);
      final timing = TextOverlayPainter.timingFor(
        overlay,
        glyphCountOf(overlay),
      );

      final resting = await inkBounds(painterFor(overlay, 4.0), layout.boxSize);
      // A quarter through the window: `slide_down` comes from above, so the
      // text is still well short of its resting place.
      final mid = await inkBounds(
        painterFor(overlay, timing.inSeconds * 0.25),
        layout.boxSize,
      );

      expect(resting, isNotNull);
      expect(mid, isNotNull, reason: 'the glyph was clipped away entirely');

      // It has actually moved — and upward, which is where `slide_down` starts.
      expect(mid!.top, lessThan(resting!.top - 1));
      // And it is the whole letter that moved, not a sliver surviving a stale
      // clip: the displaced ink is about as tall as the resting ink.
      expect(mid.height, closeTo(resting.height, resting.height * 0.25));
    });

    // Scale has the same failure with a different shape: a resting clip crops
    // a grown letter to its original box, so only the middle survives.
    test('a glyph scaled past its cell is not cropped to the cell', () async {
      final overlay = textWith(text: 'abcd', inAnimation: 'zoom_out');
      final layout = TextOverlayLayout.measure(overlay, canvas);
      final timing = TextOverlayPainter.timingFor(
        overlay,
        glyphCountOf(overlay),
      );

      final resting = await inkBounds(painterFor(overlay, 4.0), layout.boxSize);
      // `zoom_out` begins at 2x and settles to 1x, so early in the window every
      // glyph is larger than the cell that will hold it at rest.
      final big = await inkBounds(
        painterFor(overlay, timing.inSeconds * 0.05),
        layout.boxSize,
      );

      expect(resting, isNotNull);
      expect(big, isNotNull);
      expect(big!.height, greaterThan(resting!.height * 1.3));
    });

    test('a static text paints ink and does not throw', () async {
      final overlay = textWith();
      final layout = TextOverlayLayout.measure(overlay, canvas);
      expect(
        await inkedPixels(painterFor(overlay, 0.0), layout.boxSize),
        greaterThan(0),
      );
    });

    // Typing reveals glyphs one at a time, so early in the window fewer of
    // them are drawn than at the end. If the painter ignored the playhead — a
    // per-glyph pass that never read the state — these two would be equal.
    test('a typing text paints less ink early than at rest', () async {
      final overlay = textWith(text: 'abcdefgh', inAnimation: 'typing');
      final layout = TextOverlayLayout.measure(overlay, canvas);
      final timing = TextOverlayPainter.timingFor(
        overlay,
        glyphCountOf(overlay),
      );
      final early = await inkedPixels(
        painterFor(overlay, timing.inSeconds * 0.15),
        layout.boxSize,
      );
      final settled = await inkedPixels(
        painterFor(overlay, timing.inSeconds * 2),
        layout.boxSize,
      );
      expect(early, lessThan(settled));
      expect(settled, greaterThan(0));
    });

    // Once the in-window has passed, every curve rests — so the animated
    // painter and an unanimated one must draw the same picture. This is the
    // stage's regression bar expressed as pixels rather than as a promise.
    //
    // **The shadow is what gives it teeth.** Without one the bleed padding is
    // zero, a glyph's padded rect equals its ink rect, and clipping to the
    // wrong one of the two is undetectable — the same reason the atlas
    // measures its reassembly against a shadowed case.
    test('past its window an animated text matches an unanimated one', () async {
      final animated = textWith(
        text: 'abcdefgh',
        inAnimation: 'fade_in',
        shadow: true,
      );
      final plain = textWith(text: 'abcdefgh', shadow: true);
      final layout = TextOverlayLayout.measure(plain, canvas);
      final a = await inkedPixels(painterFor(animated, 4.0), layout.boxSize);
      final b = await inkedPixels(painterFor(plain, 4.0), layout.boxSize);
      // Not exact: the glyph pass clips each letter to its own padded cell,
      // so antialiased edges can land a pixel differently from one unclipped
      // run. A per-glyph fault — a lost letter, a clipped shadow — moves this
      // far more than a couple of percent.
      expect((a - b).abs(), lessThan(b * 0.02 + 4));
    });
  });

  group('shouldRepaint', () {

    test('a static text does not repaint as the playhead moves', () {
      final overlay = textWith();
      expect(
        painterFor(overlay, 1.0).shouldRepaint(painterFor(overlay, 0.0)),
        isFalse,
      );
    });

    test('an animating text repaints on every playhead change', () {
      final overlay = textWith(inAnimation: 'typing');
      expect(
        painterFor(overlay, 0.1).shouldRepaint(painterFor(overlay, 0.0)),
        isTrue,
      );
    });

    test('a content change repaints even at the same playhead', () {
      final before = textWith(text: 'abc');
      final after = textWith(text: 'abd');
      expect(
        painterFor(after, 0.0).shouldRepaint(painterFor(before, 0.0)),
        isTrue,
      );
    });

    test('retuning the shadow repaints', () {
      // shouldRepaint compares field by field; a control it does not list
      // would move nothing on the canvas until something else changed.
      final before = textWith(shadow: true);
      for (final after in [
        before.copyWith(shadowOpacity: 0.5),
        before.copyWith(shadowDistance: 15),
        before.copyWith(shadowAngle: 200),
        before.copyWith(shadowBlurRadius: 2),
      ]) {
        expect(
          painterFor(after, 0.0).shouldRepaint(painterFor(before, 0.0)),
          isTrue,
        );
      }
    });

    test('scale and rotation do not repaint — the transforms own them', () {
      final before = textWith();
      final after = textWith()
        ..scale = 2.0
        ..rotation = 0.5;
      expect(
        painterFor(after, 0.0).shouldRepaint(painterFor(before, 0.0)),
        isFalse,
      );
    });
  });
}
