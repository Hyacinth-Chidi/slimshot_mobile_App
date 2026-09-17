import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/chroma/chroma_key.dart';

/// A chroma key: which pixels of a clip are dropped for the background to show
/// through, decided by colour rather than by position.
///
/// [chromaCoverage] is the Dart twin of the shader's `chromaCoverage`. It
/// exists so the arithmetic can be tested at all — GLSL only runs on a device —
/// and so the UI can preview a key. If one changes the other must.
void main() {
  const green = ChromaKey(
    enabled: true,
    keyR: 0.0,
    keyG: 1.0,
    keyB: 0.0,
    similarity: 0.4,
    smoothness: 0.1,
    spill: 0.0,
  );

  group('coverage', () {
    test('a disabled key keeps every pixel, whatever its colour', () {
      const off = ChromaKey.none;
      for (final c in [
        [0.0, 1.0, 0.0],
        [1.0, 1.0, 1.0],
        [0.0, 0.0, 0.0],
      ]) {
        expect(chromaCoverage(c[0], c[1], c[2], off), 1.0);
      }
    });

    test('the key colour itself is dropped, and its opposite is kept', () {
      expect(chromaCoverage(0, 1, 0, green), 0.0);
      expect(chromaCoverage(1, 0, 1, green), 1.0);
    });

    test('coverage rises with distance from the key, and never leaves 0..1',
        () {
      var last = -1.0;
      for (var i = 0; i <= 20; i++) {
        // Walk from pure green toward pure magenta.
        final t = i / 20;
        final v = chromaCoverage(t, 1 - t, t, green);
        expect(v, inInclusiveRange(0.0, 1.0));
        expect(v, greaterThanOrEqualTo(last), reason: 'at $t');
        last = v;
      }
      expect(last, 1.0);
    });

    test('a wider similarity drops more of the neighbouring colours', () {
      const narrow = ChromaKey(
          enabled: true, keyR: 0, keyG: 1, keyB: 0, similarity: 0.1);
      const wide = ChromaKey(
          enabled: true, keyR: 0, keyG: 1, keyB: 0, similarity: 0.7);
      // A saturated yellow: a neighbouring hue, not the key itself. A narrow
      // key keeps it and a wide one takes it, which is what the slider is for.
      expect(chromaCoverage(0.8, 0.9, 0.1, narrow), 1.0);
      expect(chromaCoverage(0.8, 0.9, 0.1, wide), 0.0);
      // Widening never *keeps* something a narrower key dropped.
      for (var i = 0; i <= 20; i++) {
        final t = i / 20;
        expect(chromaCoverage(t, 1 - t, t * 0.5, wide),
            lessThanOrEqualTo(chromaCoverage(t, 1 - t, t * 0.5, narrow)),
            reason: 'at $t');
      }
    });

    test('smoothness softens the edge rather than moving it', () {
      const hard = ChromaKey(
          enabled: true,
          keyR: 0,
          keyG: 1,
          keyB: 0,
          similarity: 0.4,
          smoothness: 0.0);
      const soft = ChromaKey(
          enabled: true,
          keyR: 0,
          keyG: 1,
          keyB: 0,
          similarity: 0.4,
          smoothness: 0.3);
      // Both agree deep inside and far outside; they differ in the transition.
      expect(chromaCoverage(0, 1, 0, hard), 0.0);
      expect(chromaCoverage(0, 1, 0, soft), 0.0);
      expect(chromaCoverage(1, 0, 1, hard), 1.0);
      expect(chromaCoverage(1, 0, 1, soft), 1.0);
      // A hard key is binary everywhere; a soft one has a real gradient where
      // the picture desaturates out of the key — which is where a hair or a
      // motion-blurred edge lives, and the reason smoothness exists at all.
      var sawPartial = false;
      for (var i = 0; i <= 40; i++) {
        final t = i / 40;
        final c = chromaCoverage(t, 1 - t * 0.5, t, soft);
        expect(chromaCoverage(t, 1 - t * 0.5, t, hard), anyOf(0.0, 1.0));
        if (c > 0.0 && c < 1.0) sawPartial = true;
      }
      expect(sawPartial, isTrue);
    });

    test('a zero similarity still takes the key hue, and only that hue', () {
      // Zero narrows the *hue* window to nothing, but a fully saturated pixel
      // of the key's own hue is still the key — the saturation term carries it.
      // That is deliberate: a green screen keys at every slider position, and
      // similarity decides how far into the neighbouring hues it reaches.
      const exact =
          ChromaKey(enabled: true, keyR: 0, keyG: 1, keyB: 0, similarity: 0);
      expect(chromaCoverage(0, 1, 0, exact), 0.0);
      // A neighbouring hue is kept at zero, where a wide key would take it.
      expect(chromaCoverage(0.8, 0.9, 0.1, exact), 1.0);
    });

    test('brightness is ignored: a shadowed green screen keys like a lit one',
        () {
      // The reason the key is on hue rather than on RGB distance. A plain
      // distance puts a 45% green 0.46 away from a full green — as far as a
      // sensible similarity window reaches — so the shadowed corners of a
      // screen would survive the key. Measured before this was fixed.
      expect(chromaCoverage(0.0, 1.0, 0.0, green), 0.0);
      expect(chromaCoverage(0.0, 0.45, 0.0, green), 0.0);
      expect(chromaCoverage(0.0, 0.2, 0.0, green), 0.0);
    });

    test('a grey or near-black pixel is never keyed', () {
      // It has no hue to compare, and a black shadow on set is not the screen.
      for (final v in [0.02, 0.2, 0.5, 1.0]) {
        expect(chromaCoverage(v, v, v, green), 1.0, reason: 'grey $v');
      }
    });

    test('skin and the other colours a subject wears are kept', () {
      expect(chromaCoverage(0.85, 0.65, 0.50, green), 1.0);
      expect(chromaCoverage(1.0, 0.0, 1.0, green), 1.0);
      expect(chromaCoverage(0.2, 0.3, 0.9, green), 1.0);
    });
  });

  group('spill', () {
    test('with no spill the colour is returned untouched', () {
      final c = despill(0.4, 0.9, 0.3, green);
      expect(c.r, closeTo(0.4, 1e-9));
      expect(c.g, closeTo(0.9, 1e-9));
      expect(c.b, closeTo(0.3, 1e-9));
    });

    test('spill pulls a green fringe back toward neutral', () {
      const spilled = ChromaKey(
          enabled: true,
          keyR: 0,
          keyG: 1,
          keyB: 0,
          similarity: 0.4,
          spill: 1.0);
      final c = despill(0.4, 0.9, 0.3, spilled);
      expect(c.g, lessThan(0.9));
      // The other channels are left where they were.
      expect(c.r, closeTo(0.4, 1e-9));
      expect(c.b, closeTo(0.3, 1e-9));
    });

    test('a colour with no excess key channel is left alone', () {
      const spilled = ChromaKey(
          enabled: true, keyR: 0, keyG: 1, keyB: 0, spill: 1.0);
      final c = despill(0.8, 0.2, 0.7, spilled);
      expect(c.g, closeTo(0.2, 1e-9));
    });
  });

  group('model', () {
    test('none is disabled and serialises to nothing', () {
      expect(ChromaKey.none.enabled, isFalse);
      expect(ChromaKey.none.isNone, isTrue);
    });

    test('round-trips through JSON', () {
      final back = ChromaKey.fromJson(green.toJson());
      expect(back, green);
    });

    test('junk reads as no key, never a throw', () {
      expect(ChromaKey.fromJson(null), ChromaKey.none);
      expect(ChromaKey.fromJson('x'), ChromaKey.none);
      expect(ChromaKey.fromJson(<String, dynamic>{}), ChromaKey.none);
    });

    test('values out of range are clamped on read', () {
      final wild = ChromaKey.fromJson({
        'enabled': true,
        'r': 5.0,
        'g': -2.0,
        'b': 0.5,
        'similarity': 9.0,
        'smoothness': -1.0,
        'spill': 4.0,
      });
      expect(wild.keyR, 1.0);
      expect(wild.keyG, 0.0);
      expect(wild.similarity, inInclusiveRange(0.0, 1.0));
      expect(wild.smoothness, inInclusiveRange(0.0, 1.0));
      expect(wild.spill, inInclusiveRange(0.0, 1.0));
    });

    test('the uniform pair encodes in the order the shader reads', () {
      final u = green.uniforms();
      expect(u.length, 8);
      // (r, g, b, similarity) then (smoothness, spill, enabled, 0).
      expect(u.sublist(0, 4), [0.0, 1.0, 0.0, 0.4]);
      expect(u[4], closeTo(0.1, 1e-9));
      expect(u[5], 0.0);
      expect(u[6], 1.0);
      expect(u[7], 0.0);
      // Disabled writes a zero flag, which is what the shader tests.
      expect(ChromaKey.none.uniforms()[6], 0.0);
    });

    test('equality is structural', () {
      expect(green, const ChromaKey(
          enabled: true,
          keyR: 0,
          keyG: 1,
          keyB: 0,
          similarity: 0.4,
          smoothness: 0.1,
          spill: 0));
      expect(green, isNot(ChromaKey.none));
    });
  });
}
