import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';

void main() {
  group('catalog shape', () {
    test('ids are unique', () {
      final ids = kVideoEffects.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('an unknown id resolves to null rather than throwing', () {
      expect(videoEffectById('no_such_effect'), isNull);
      expect(videoEffectById(null), isNull);
    });

    test('every category offers at least one effect', () {
      for (final category in EffectCategory.values) {
        if (category == EffectCategory.none) continue;
        expect(effectsInCategory(category), isNotEmpty, reason: '$category');
      }
    });

    test('intensities are normalised', () {
      for (final effect in kVideoEffects) {
        expect(effect.defaultIntensity, inInclusiveRange(0, 1),
            reason: '${effect.id} must be 0..1, never pixels');
      }
    });

    test('pass counts are sane and match the multi-pass flag', () {
      for (final effect in kVideoEffects) {
        expect(effect.passCount, greaterThanOrEqualTo(1), reason: effect.id);
        expect(effect.passCount, lessThanOrEqualTo(4),
            reason: '${effect.id} exceeds MAX_EFFECT_PASSES');
        expect(effect.isMultiPass, effect.passCount > 1, reason: effect.id);
      }
    });

    test('the catalogue covers both tiers', () {
      expect(kVideoEffects.any((e) => e.isMultiPass), isTrue);
      expect(kVideoEffects.any((e) => !e.isMultiPass), isTrue);
      expect(kVideoEffects.length, greaterThanOrEqualTo(15));
    });
  });

  group('lookup', () {
    test('resolves every catalog id back to its own entry', () {
      for (final effect in kVideoEffects) {
        expect(videoEffectById(effect.id), same(effect), reason: effect.id);
      }
    });

    test('the empty string and "none" mean no effect, not an unknown one', () {
      // A cleared selection may reach persistence as either, and neither is a
      // stale id worth warning about — both simply mean the clip is unaffected.
      expect(videoEffectById(''), isNull);
      expect(videoEffectById('none'), isNull);
    });

    test('effectsInCategory(none) is empty', () {
      // `none` is the absence of an effect, so no entry may claim it — a tile
      // list built from it would offer an effect that does nothing.
      expect(effectsInCategory(EffectCategory.none), isEmpty);
    });

    test('every entry is reachable through exactly one category query', () {
      final listed = <String>[];
      for (final category in EffectCategory.values) {
        listed.addAll(effectsInCategory(category).map((e) => e.id));
      }
      expect(listed..sort(), (kVideoEffects.map((e) => e.id).toList()..sort()));
    });
  });

  group('ids and labels', () {
    test('the planned shader set is present', () {
      // These ids are persisted into drafts, so this list is a contract: a
      // rename needs a migration, not an edit here.
      const planned = [
        'vignette', 'grain', 'vhs', 'rgb_split', 'glitch', 'chromatic',
        'scanlines', 'fisheye', 'ripple', 'swirl', 'mirror', 'sharpen',
        'duotone', 'light_leak', 'blur', 'glow',
      ];
      final ids = kVideoEffects.map((e) => e.id).toSet();
      for (final id in planned) {
        expect(ids, contains(id), reason: id);
      }
    });

    test('an intro declares its window; a static look declares none', () {
      // The two states are what the renderer branches on, and conflating them
      // is the bug this pins: a static look with a window would be told its
      // progress runs out part-way through the clip, and an intro without one
      // would stretch its animation across a 90s clip.
      for (final effect in kVideoEffects) {
        if (effect.category == EffectCategory.intro) {
          expect(effect.introSeconds, isNotNull,
              reason: '${effect.id} is an intro with no window');
          expect(effect.introSeconds, greaterThan(0),
              reason: '${effect.id} has a window that ends before it starts');
          expect(effect.isTimed, isTrue, reason: effect.id);
        } else {
          expect(effect.introSeconds, isNull,
              reason: '${effect.id} is a static look and must ignore the clock');
          expect(effect.isTimed, isFalse, reason: effect.id);
        }
      }
    });

    test('fade_in is the timed effect the clock is proven with', () {
      final fade = videoEffectById('fade_in');
      expect(fade, isNotNull);
      expect(fade!.category, EffectCategory.intro);
      expect(fade.introSeconds, isNotNull);
      // One pass: the whole point of it is that there is nowhere for a bug to
      // hide between the clock and the picture.
      expect(fade.passCount, 1);
      expect(effectIntroSecondsFor('fade_in'), fade.introSeconds);
    });

    test('the intro window is only ever asked for through the catalog', () {
      // Null for a static look and for an id this build does not know, which
      // are the same answer to a renderer: measure progress across the clip.
      expect(effectIntroSecondsFor('vignette'), isNull);
      expect(effectIntroSecondsFor('no_such_effect'), isNull);
      expect(effectIntroSecondsFor(null), isNull);
      expect(effectIntroSecondsFor('none'), isNull);
    });

    test('blur and glow declare the pass counts the chain will run', () {
      expect(videoEffectById('blur')!.passCount, 2);
      expect(videoEffectById('glow')!.passCount, 3);
    });

    test('ids are lower_snake_case', () {
      // The id is the wire value and the draft key; a stray capital or space
      // would be invisible here and a migration later.
      for (final effect in kVideoEffects) {
        expect(effect.id, matches(RegExp(r'^[a-z][a-z0-9_]*$')),
            reason: effect.id);
      }
    });

    test('labels are user-facing, unique and short enough for a tile', () {
      final labels = kVideoEffects.map((e) => e.label).toList();
      expect(labels.toSet().length, labels.length);
      for (final effect in kVideoEffects) {
        expect(effect.label, isNotEmpty, reason: effect.id);
        expect(effect.label.length, lessThanOrEqualTo(14),
            reason: '${effect.id}: "${effect.label}" will not fit a tile');
        expect(effect.label, isNot(equals(effect.id)), reason: effect.id);
      }
    });
  });
}
