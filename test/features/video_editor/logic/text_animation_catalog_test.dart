import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_animation_catalog.dart';

/// `(glyphIndex, glyphCount)` pairs the boundary tests sweep.
///
/// A single `(2, 5)` sample is not enough: the stagger's delay term scales with
/// `i/(n-1)`, so a boundary fault can hide at one index and show at another.
/// `n = 1` is the divide-by-zero guard's path and `n = 40` exercises the
/// smallest per-glyph delay.
const List<(int, int)> _glyphSamples = [
  (0, 1),
  (0, 2),
  (1, 2),
  (2, 5),
  (0, 7),
  (6, 7),
  (0, 40),
  (39, 40),
];

void main() {
  group('catalog shape', () {
    test('every animation has a unique id', () {
      final ids = kTextAnimations.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('lookup finds a known animation and misses an unknown one', () {
      expect(textAnimationById('typing')?.category, TextAnimationCategory.inAnim);
      expect(textAnimationById('no_such_animation'), isNull);
    });

    test('the seven legacy names still resolve', () {
      for (final id in [
        'fade_in', 'zoom_in', 'zoom_out',
        'slide_up', 'slide_down', 'slide_left', 'slide_right',
      ]) {
        expect(textAnimationById(id), isNotNull, reason: '$id must survive');
      }
    });
  });

  group('curve boundaries', () {
    // An in-animation must land exactly on the resting state, or the text
    // visibly jumps the frame after it finishes.
    test('every in-animation rests at p=1', () {
      for (final anim in kTextAnimations.where(
          (a) => a.category == TextAnimationCategory.inAnim)) {
        for (final (i, n) in _glyphSamples) {
          final s = anim.stateAt(1.0, i, n);
          final where = '${anim.id} i=$i n=$n';
          expect(s.opacity, closeTo(1, 1e-6), reason: '$where opacity');
          expect(s.scale, closeTo(1, 1e-6), reason: '$where scale');
          expect(s.offsetX, closeTo(0, 1e-6), reason: '$where offsetX');
          expect(s.offsetY, closeTo(0, 1e-6), reason: '$where offsetY');
          expect(s.rotation, closeTo(0, 1e-6), reason: '$where rotation');
          expect(s.fillProgress, closeTo(1, 1e-6), reason: '$where fill');
        }
      }
    });

    test('every out-animation starts from the resting state at p=0', () {
      for (final anim in kTextAnimations.where(
          (a) => a.category == TextAnimationCategory.outAnim)) {
        for (final (i, n) in _glyphSamples) {
          final s = anim.stateAt(0.0, i, n);
          final where = '${anim.id} i=$i n=$n';
          expect(s.opacity, closeTo(1, 1e-6), reason: '$where opacity');
          expect(s.scale, closeTo(1, 1e-6), reason: '$where scale');
          expect(s.offsetX, closeTo(0, 1e-6), reason: '$where offsetX');
          expect(s.offsetY, closeTo(0, 1e-6), reason: '$where offsetY');
          expect(s.rotation, closeTo(0, 1e-6), reason: '$where rotation');
          expect(s.fillProgress, closeTo(1, 1e-6), reason: '$where fill');
        }
      }
    });

    // All six channels, not just the three a sine-driven wave happens to use.
    // shake_loop moves in offsetX, wiggle_loop in rotation and
    // colour_cycle_loop in fillProgress — so checking only offsetY/scale/
    // opacity left every loop's *primary* channel untested, and a seam
    // discontinuity in exactly the thing the user would see passed silently.
    test('a loop animation is seamless: p=0 and p=1 agree', () {
      for (final anim in kTextAnimations.where(
          (a) => a.category == TextAnimationCategory.loop)) {
        for (final (i, n) in _glyphSamples) {
          final a0 = anim.stateAt(0.0, i, n);
          final a1 = anim.stateAt(1.0, i, n);
          final where = '${anim.id} i=$i n=$n';
          expect(a1.opacity, closeTo(a0.opacity, 1e-6), reason: '$where opacity seam');
          expect(a1.offsetX, closeTo(a0.offsetX, 1e-6), reason: '$where offsetX seam');
          expect(a1.offsetY, closeTo(a0.offsetY, 1e-6), reason: '$where offsetY seam');
          expect(a1.scale, closeTo(a0.scale, 1e-6), reason: '$where scale seam');
          expect(a1.rotation, closeTo(a0.rotation, 1e-6), reason: '$where rotation seam');
          expect(a1.fillProgress, closeTo(a0.fillProgress, 1e-6),
              reason: '$where fill seam');
        }
      }
    });

    test('each loop actually moves the channel it is named for', () {
      // Guards the test above from passing vacuously: a loop that did nothing
      // would have a perfect seam on every channel.
      double swing(TextAnimation a, double Function(TextGlyphState) channel) {
        var lo = double.infinity, hi = double.negativeInfinity;
        for (var s = 0; s <= 100; s++) {
          final v = channel(a.stateAt(s / 100, 2, 6));
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
        return hi - lo;
      }

      expect(swing(textAnimationById('wave_loop')!, (s) => s.offsetY),
          greaterThan(0.1), reason: 'wave_loop offsetY');
      expect(swing(textAnimationById('pulse_loop')!, (s) => s.scale),
          greaterThan(0.05), reason: 'pulse_loop scale');
      expect(swing(textAnimationById('shake_loop')!, (s) => s.offsetX),
          greaterThan(0.05), reason: 'shake_loop offsetX');
      expect(swing(textAnimationById('wiggle_loop')!, (s) => s.rotation),
          greaterThan(0.05), reason: 'wiggle_loop rotation');
      expect(swing(textAnimationById('colour_cycle_loop')!, (s) => s.fillProgress),
          greaterThan(0.5), reason: 'colour_cycle_loop fillProgress');
    });

    // Jitter from `Random()` would differ between the preview and the export,
    // and between two draws of the same frame.
    test('shake and wiggle are deterministic', () {
      for (final id in ['shake_loop', 'wiggle_loop']) {
        final anim = textAnimationById(id)!;
        for (final (i, n) in _glyphSamples) {
          for (final p in [0.0, 0.17, 0.5, 0.83, 1.0]) {
            final a = anim.stateAt(p, i, n);
            final b = anim.stateAt(p, i, n);
            final where = '$id p=$p i=$i n=$n';
            expect(b.opacity, a.opacity, reason: '$where opacity');
            expect(b.offsetX, a.offsetX, reason: '$where offsetX');
            expect(b.offsetY, a.offsetY, reason: '$where offsetY');
            expect(b.scale, a.scale, reason: '$where scale');
            expect(b.rotation, a.rotation, reason: '$where rotation');
            expect(b.fillProgress, a.fillProgress, reason: '$where fill');
          }
        }
      }
    });

    test('states stay in sane ranges across the whole curve', () {
      for (final anim in kTextAnimations) {
        for (var step = 0; step <= 20; step++) {
          final s = anim.stateAt(step / 20, 3, 7);
          expect(s.opacity, inInclusiveRange(0, 1), reason: '${anim.id} opacity');
          expect(s.scale, greaterThanOrEqualTo(0), reason: '${anim.id} scale');
          expect(s.fillProgress, inInclusiveRange(0, 1), reason: '${anim.id} fill');
          expect(s.offsetX.abs(), lessThan(10), reason: '${anim.id} offsetX runaway');
          expect(s.offsetY.abs(), lessThan(10), reason: '${anim.id} offsetY runaway');
        }
      }
    });
  });

  group('typing', () {
    final typing = textAnimationById('typing')!;

    test('is per-glyph', () => expect(typing.isPerGlyph, isTrue));

    test('reveals characters left to right', () {
      // A third of the way through 6 glyphs: early ones visible, late ones not.
      final first = typing.stateAt(0.34, 0, 6);
      final last = typing.stateAt(0.34, 5, 6);
      expect(first.opacity, greaterThan(last.opacity));
    });

    test('every glyph is visible by the end', () {
      for (var i = 0; i < 6; i++) {
        expect(typing.stateAt(1.0, i, 6).opacity, closeTo(1, 1e-6));
      }
    });

    test('a single glyph still animates rather than dividing by zero', () {
      expect(typing.stateAt(0.0, 0, 1).opacity, closeTo(0, 1e-6));
      expect(typing.stateAt(1.0, 0, 1).opacity, closeTo(1, 1e-6));
    });
  });

  group('wave', () {
    final wave = kTextAnimations.firstWhere((a) => a.id == 'wave_loop');

    test('neighbouring glyphs are out of phase', () {
      final a = wave.stateAt(0.25, 0, 8);
      final b = wave.stateAt(0.25, 4, 8);
      expect((a.offsetY - b.offsetY).abs(), greaterThan(0.05));
    });
  });

  group('natural duration', () {
    test('a flat animation ignores glyph count', () {
      final fade = textAnimationById('fade_in')!;
      expect(fade.naturalDuration(3), fade.naturalDuration(30));
    });

    test('typing takes longer for more characters, within bounds', () {
      final typing = textAnimationById('typing')!;
      expect(typing.naturalDuration(30), greaterThan(typing.naturalDuration(5)));
      expect(typing.naturalDuration(500), lessThanOrEqualTo(2.5));
      expect(typing.naturalDuration(1), greaterThanOrEqualTo(0.4));
    });
  });

  group('resolveTextAnimationDurations', () {
    final typing = textAnimationById('typing')!;
    final fadeOut = textAnimationById('fade_out')!;

    test('speed scales duration inversely', () {
      final slow = resolveTextAnimationDurations(
        spanSeconds: 100, inAnim: typing, outAnim: null, glyphCount: 10, speed: 1);
      final fast = resolveTextAnimationDurations(
        spanSeconds: 100, inAnim: typing, outAnim: null, glyphCount: 10, speed: 2);
      expect(fast.inSeconds, closeTo(slow.inSeconds / 2, 1e-9));
    });

    test('compresses proportionally when in+out exceed the span', () {
      // A dropped animation is a silent preview/export mismatch, so both are
      // squeezed instead.
      final r = resolveTextAnimationDurations(
        spanSeconds: 0.5, inAnim: typing, outAnim: fadeOut, glyphCount: 20, speed: 1);
      expect(r.inSeconds + r.outSeconds, closeTo(0.5, 1e-6));
      expect(r.inSeconds, greaterThan(0));
      expect(r.outSeconds, greaterThan(0));
    });

    test('leaves them alone when they fit', () {
      final r = resolveTextAnimationDurations(
        spanSeconds: 10, inAnim: typing, outAnim: fadeOut, glyphCount: 5, speed: 1);
      expect(r.inSeconds, closeTo(typing.naturalDuration(5), 1e-9));
      expect(r.outSeconds, closeTo(fadeOut.naturalDuration(5), 1e-9));
    });

    test('a null animation contributes nothing', () {
      final r = resolveTextAnimationDurations(
        spanSeconds: 10, inAnim: null, outAnim: null, glyphCount: 5, speed: 1);
      expect(r.inSeconds, 0);
      expect(r.outSeconds, 0);
    });

    test('a zero or negative span cannot produce negative durations', () {
      final r = resolveTextAnimationDurations(
        spanSeconds: 0, inAnim: typing, outAnim: fadeOut, glyphCount: 5, speed: 1);
      expect(r.inSeconds, greaterThanOrEqualTo(0));
      expect(r.outSeconds, greaterThanOrEqualTo(0));
    });
  });

  // Every case below is pinned against `_animated` in text_overlay_layer.dart,
  // the layer these drafts were written by. A saved project must keep playing
  // what its author saw.
  group('legacy ids resolve by slot', () {
    const inSlot = TextAnimationCategory.inAnim;
    const outSlot = TextAnimationCategory.outAnim;

    test("'fade' means fade-in in the in slot and fade-out in the out slot", () {
      // The old layer: `'fade_in' || 'fade' => anim.fadeIn()` in one switch,
      // `'fade_out' || 'fade' => anim.fadeOut()` in the other.
      expect(resolveTextAnimation('fade', inSlot)?.id, 'fade_in');
      expect(resolveTextAnimation('fade', outSlot)?.id, 'fade_out');
    });

    test("'scale' grows in and shrinks away out", () {
      // `'zoom_in' || 'scale' => scaleXY(begin: 0)` vs `'scale' => scaleXY(end: 0)`,
      // the latter identical to the layer's own 'zoom_in_out' arm.
      expect(resolveTextAnimation('scale', inSlot)?.id, 'zoom_in');
      expect(resolveTextAnimation('scale', outSlot)?.id, 'zoom_in_out');
    });

    test('a legacy id resolved by slot actually plays the right direction', () {
      // The regression this guards: resolving an out-slot 'fade' to fade_in
      // would make a saved project fade *in* as it left.
      final out = resolveTextAnimation('fade', outSlot)!;
      expect(out.stateAt(0, 0, 3).opacity, closeTo(1, 1e-9));
      expect(out.stateAt(1, 0, 3).opacity, closeTo(0, 1e-9));

      final inAnim = resolveTextAnimation('fade', inSlot)!;
      expect(inAnim.stateAt(0, 0, 3).opacity, closeTo(0, 1e-9));
      expect(inAnim.stateAt(1, 0, 3).opacity, closeTo(1, 1e-9));

      // 'scale' out must shrink to nothing, not grow.
      final scaleOut = resolveTextAnimation('scale', outSlot)!;
      expect(scaleOut.stateAt(1, 0, 3).scale, closeTo(0, 1e-9));
    });

    test('a bare in-only name in the out slot resolves to nothing', () {
      // The old out-slot switch handled only the _out-suffixed names, so these
      // fell through its default arm and played no out-animation. They are real
      // catalog ids, so a plain lookup would find the in-variant and *add* an
      // exit the user never had.
      for (final id in [
        'slide_up', 'slide_down', 'slide_left', 'slide_right',
        'zoom_in', 'zoom_out', 'fade_in',
      ]) {
        expect(resolveTextAnimation(id, outSlot), isNull,
            reason: '$id must not animate in the out slot');
        expect(resolveTextAnimation(id, inSlot), isNotNull,
            reason: '$id must still animate in the in slot');
      }
    });

    test('an out-only name in the in slot resolves to nothing', () {
      for (final id in ['fade_out', 'slide_up_out', 'zoom_in_out']) {
        expect(resolveTextAnimation(id, inSlot), isNull, reason: id);
        expect(resolveTextAnimation(id, outSlot), isNotNull, reason: id);
      }
    });

    test('the bare slide names keep their old in-slot direction', () {
      // slideY(begin: 1) started below and rose; +Y is down.
      expect(resolveTextAnimation('slide_up', inSlot)!.stateAt(0, 0, 3).offsetY,
          greaterThan(0.5));
      expect(resolveTextAnimation('slide_down', inSlot)!.stateAt(0, 0, 3).offsetY,
          lessThan(-0.5));
      expect(resolveTextAnimation('slide_left', inSlot)!.stateAt(0, 0, 3).offsetX,
          greaterThan(0.5));
      expect(resolveTextAnimation('slide_right', inSlot)!.stateAt(0, 0, 3).offsetX,
          lessThan(-0.5));
    });

    test('none, empty, null and unknown resolve to nothing in every slot', () {
      for (final slot in TextAnimationCategory.values) {
        expect(resolveTextAnimation(null, slot), isNull);
        expect(resolveTextAnimation('', slot), isNull);
        expect(resolveTextAnimation('none', slot), isNull);
        expect(resolveTextAnimation('circleOpen', slot), isNull);
      }
    });

    test('a loop id resolves in the loop slot and nowhere else', () {
      expect(resolveTextAnimation('wave_loop', TextAnimationCategory.loop)?.id,
          'wave_loop');
      expect(resolveTextAnimation('wave_loop', inSlot), isNull);
      expect(resolveTextAnimation('wave_loop', outSlot), isNull);
    });

    test('every catalog id resolves in its own slot', () {
      for (final a in kTextAnimations) {
        expect(resolveTextAnimation(a.id, a.category)?.id, a.id, reason: a.id);
      }
    });

    // The old arms were bare scaleXY / slideX / slideY with no fadeIn()/
    // fadeOut() beside them (text_overlay_layer.dart:248-253 and :263-269).
    // Adding a fade would change how an already-saved project looks — the same
    // regression class as resolving a legacy id to the wrong slot.
    test('legacy slides and zooms never touch opacity', () {
      const legacy = [
        'slide_up', 'slide_down', 'slide_left', 'slide_right',
        'slide_up_out', 'slide_down_out', 'slide_left_out', 'slide_right_out',
        'zoom_in', 'zoom_out', 'zoom_in_out', 'zoom_out_out',
      ];
      for (final id in legacy) {
        final anim = textAnimationById(id)!;
        for (var step = 0; step <= 40; step++) {
          for (final (i, n) in _glyphSamples) {
            expect(anim.stateAt(step / 40, i, n).opacity, 1.0,
                reason: '$id faded at p=${step / 40} i=$i n=$n');
          }
        }
      }
    });

    test('legacy slides and zooms still move or scale', () {
      // Guards the test above from being satisfied by a curve that does
      // nothing at all.
      expect(textAnimationById('slide_up')!.stateAt(0, 0, 3).offsetY.abs(),
          greaterThan(0.5));
      expect(textAnimationById('slide_up_out')!.stateAt(1, 0, 3).offsetY.abs(),
          greaterThan(0.5));
      expect(textAnimationById('zoom_in')!.stateAt(0, 0, 3).scale, closeTo(0, 1e-9));
      expect(textAnimationById('zoom_out')!.stateAt(0, 0, 3).scale, greaterThan(1.5));
      expect(textAnimationById('zoom_in_out')!.stateAt(1, 0, 3).scale, closeTo(0, 1e-9));
      expect(textAnimationById('zoom_out_out')!.stateAt(1, 0, 3).scale, closeTo(2, 1e-9));
    });
  });
}
