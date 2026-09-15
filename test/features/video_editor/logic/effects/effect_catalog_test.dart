import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
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
    test('the effects this batch added are present', () {
      // Same contract as the planned set below: these ids are persisted into
      // drafts and sent over the channel, so a rename is a migration.
      const added = [
        // intros
        'cinema_zoom', 'zoom_in', 'super_zoom', 'pulse_zoom', 'bounce',
        'spin', 'roll', 'tilt', 'blur_in', 'pixel_in', 'hue_shift',
        'bw_fade', 'steady_in',
        // reveals
        'shutter', 'horizontal_open', 'circle_in', 'grid', 'grid_collage',
        'roulette',
        // continuous
        'camera_pan', 'handheld', 'super_shake',
      ];
      final ids = kVideoEffects.map((e) => e.id).toSet();
      for (final id in added) {
        expect(ids, contains(id), reason: id);
      }
    });

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

    /// The categories whose entries play over a window at the clip's opening
    /// and then settle.
    ///
    /// A reveal is timed exactly as an intro is — same clock, same settle rule
    /// — and is a separate shelf only because a person browsing knows whether
    /// they want the picture to *arrive* or to *move*.
    const timedCategories = {EffectCategory.intro, EffectCategory.reveal};

    test('a timed effect declares its window; everything else declares none',
        () {
      // The two states are what the renderer branches on, and conflating them
      // is the bug this pins: a static look with a window would be told its
      // progress runs out part-way through the clip, and an intro without one
      // would stretch its animation across a 90s clip.
      for (final effect in kVideoEffects) {
        if (timedCategories.contains(effect.category)) {
          expect(effect.introSeconds, isNotNull,
              reason: '${effect.id} is timed but declares no window');
          expect(effect.introSeconds, greaterThan(0),
              reason: '${effect.id} has a window that ends before it starts');
          expect(effect.isTimed, isTrue, reason: effect.id);
        } else {
          expect(effect.introSeconds, isNull,
              reason: '${effect.id} must measure progress across the clip');
          expect(effect.isTimed, isFalse, reason: effect.id);
        }
      }
    });

    test('a continuous look declares no window, so it never settles', () {
      // The distinction the `motionLoop` category exists for: these animate for
      // the whole clip, so `uProgress` must run across its whole length. One of
      // them declaring a window would settle part-way through and stop dead,
      // which is an intro, not a continuous look.
      final continuous = effectsInCategory(EffectCategory.motionLoop);
      expect(continuous, isNotEmpty);
      for (final effect in continuous) {
        expect(effect.introSeconds, isNull, reason: effect.id);
        expect(effect.isTimed, isFalse, reason: effect.id);
      }
    });

    test('an intro window is short enough to be an opening', () {
      // A window is the clip's *opening*, not its length. Past a couple of
      // seconds the effect stops reading as an intro and starts competing with
      // the footage — and on a short-form clip it would never settle at all.
      for (final effect in kVideoEffects.where((e) => e.isTimed)) {
        expect(effect.introSeconds, lessThanOrEqualTo(2.0), reason: effect.id);
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

  group('the Kotlin registry matches the catalog', () {
    // **This is the drift the whole two-file design is exposed to.** The
    // catalog says what effects exist; `EffectShaders.passesFor` says how each
    // is drawn, and an id in one and not the other is invisible until a device
    // run: an unregistered id silently renders the unprocessed frame, which
    // reads as "I tapped the tile and nothing happened".
    //
    // Reading the Kotlin source is crude but it is the only check available
    // from a Dart test, and the alternative — noticing on a device — is what
    // this exists to replace. It greps for the `when` branches' string
    // literals, so a new effect is registered or this fails.
    final registry = File(
      'android/app/src/main/kotlin/com/techfamz/slimshotai/'
      'nativepreview/gl/effects/EffectShaders.kt',
    );

    /// Every id `passesFor` has a branch for.
    Set<String> registeredIds() {
      final source = registry.readAsStringSync();
      // The branches are the only place a bare quoted id appears at the start
      // of a `when` arm.
      final matches = RegExp(r'''^\s*"([a-z][a-z0-9_]*)"\s*->''', multiLine: true)
          .allMatches(source);
      return matches.map((m) => m.group(1)!).toSet();
    }

    test('the registry file is where the test thinks it is', () {
      // A moved file would make every assertion below vacuously pass, which is
      // worse than the drift they are checking for.
      expect(registry.existsSync(), isTrue,
          reason: 'EffectShaders.kt not found at ${registry.path}');
      expect(registeredIds(), isNotEmpty);
    });

    test('every effect with a shader is one the catalog offers', () {
      // The direction that would ship a shader the panel can never reach — and
      // more importantly, catches a typo in a branch id, which otherwise looks
      // exactly like an effect that was never registered.
      final catalogIds = kVideoEffects.map((e) => e.id).toSet();
      for (final id in registeredIds()) {
        if (id == 'none') continue;
        expect(catalogIds, contains(id),
            reason: '$id has a shader but no catalog entry');
      }
    });

    test('every timed effect the catalog offers has a shader', () {
      // Deliberately not *every* effect: the catalog carries thirteen static
      // looks whose shaders are not written yet, and those degrade correctly to
      // the unprocessed frame. A **timed** effect degrading that way is
      // different — it is an animation the user picked that never plays.
      final registered = registeredIds();
      final timed = kVideoEffects.where(
        (e) => e.isTimed || e.category == EffectCategory.motionLoop,
      );
      expect(timed, isNotEmpty);
      for (final effect in timed) {
        expect(registered, contains(effect.id),
            reason: '${effect.id} animates but has no shader registered');
      }
    });
  });

  group('default envelopes', () {
    test('every declared envelope is one the evaluator knows', () {
      // An unknown name degrades silently to the base value — on screen that
      // is a preset that does nothing, which is worse than a build failure.
      for (final effect in kVideoEffects) {
        final envelope = effect.defaultEnvelope;
        if (envelope == null) continue;
        expect(
          kEnvelopeNames,
          contains(envelope),
          reason: '${effect.id} declares an envelope nothing resolves',
        );
      }
    });

    test('nothing timed declares an envelope', () {
      // **An intro or a reveal already animates through `uProgress` across its
      // own window.** An envelope on top is a second animation fighting the
      // first — a fade rising from black while its strength pulses is not a
      // fade. This is the rule most likely to be broken by someone adding an
      // entry, because a timed effect is exactly the kind that *looks* like it
      // wants a curve.
      for (final effect in kVideoEffects.where((e) => e.isTimed)) {
        expect(
          effect.defaultEnvelope,
          isNull,
          reason: '${effect.id} is timed and must not also carry an envelope',
        );
      }
    });

    test('no continuous effect declares an envelope', () {
      // `motionLoop` entries read `uProgress` across the whole clip and are
      // still moving at the last frame. Same reason as the timed ones.
      for (final effect in kVideoEffects
          .where((e) => e.category == EffectCategory.motionLoop)) {
        expect(
          effect.defaultEnvelope,
          isNull,
          reason: '${effect.id} already animates for the whole clip',
        );
      }
    });

    test('no static grade declares an envelope', () {
      // A pulsing vignette or a throbbing duotone is a gimmick, not a look —
      // the user would have to go and switch it off.
      for (final effect
          in kVideoEffects.where((e) => e.category == EffectCategory.grade)) {
        expect(
          effect.defaultEnvelope,
          isNull,
          reason: '${effect.id} is a static grade and must stay flat',
        );
      }
    });

    test('the set of enveloped effects is exactly what was intended', () {
      // **Deliberately a hardcoded list.** Most of this catalog has never run
      // on hardware, so an envelope arriving by accident — a copy-pasted entry,
      // a default that drifted — would change how an effect draws with nothing
      // saying so, and the report would be filed against the shader. Adding one
      // has to be a decision someone makes here, on purpose, after watching it.
      final enveloped = kVideoEffects
          .where((e) => e.defaultEnvelope != null)
          .map((e) => e.id)
          .toSet();
      expect(enveloped, {'blur', 'glow'});
    });

    test('an effect with no envelope resolves flat at its default intensity',
        () {
      // **The hard gate.** 37 of the 39 entries declare nothing, and each of
      // them must apply exactly as it did before this model existed: one
      // strength, the same at every progress.
      for (final effect in kVideoEffects) {
        if (effect.defaultEnvelope != null) continue;
        final parameter = AnimatableDouble(
          baseValue: effect.defaultIntensity,
          envelope: effect.defaultEnvelope,
        );
        expect(parameter.isAnimated, isFalse, reason: effect.id);
        for (final p in [0.0, 0.3, 0.5, 0.8, 1.0]) {
          expect(
            parameter.resolveAt(p),
            effect.defaultIntensity,
            reason: '${effect.id} at p=$p',
          );
        }
      }
    });

    test('an enveloped effect still rests at full strength on the last frame',
        () {
      // The endpoint rule, checked where it actually matters: the last frame an
      // envelope draws is the clip's own unmodulated intensity, so the handover
      // to whatever follows the cut is continuous and nothing pops.
      for (final effect in kVideoEffects) {
        final envelope = effect.defaultEnvelope;
        if (envelope == null) continue;
        final parameter = AnimatableDouble(
          baseValue: effect.defaultIntensity,
          envelope: envelope,
        );
        expect(
          parameter.resolveAt(1.0),
          closeTo(effect.defaultIntensity, 1e-9),
          reason: '${effect.id} must hand over at its own intensity',
        );
        // And it never exceeds what the slider set — an envelope shapes an
        // intensity, it does not exceed one.
        for (var i = 0; i <= 20; i++) {
          expect(
            parameter.resolveAt(i / 20),
            lessThanOrEqualTo(effect.defaultIntensity + 1e-9),
            reason: '${effect.id} at p=${i / 20}',
          );
        }
      }
    });
  });
}
