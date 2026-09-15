import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/effects_panel.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/keyframe_row.dart';

/// The keyframe UI's contract, and the one rule it exists to keep:
///
/// > **A user who never taps "Keyframe" never sees a diamond.**
///
/// Two audiences share one feature. Someone who wants a good-looking clip taps
/// an effect and leaves — the catalog's own envelope already makes it feel
/// designed. Someone who wants a glitch that builds to a beat opts in. A row
/// that appeared unbidden would break the first path to serve the second, so
/// the tests below check the *absence* of the row as carefully as its
/// behaviour.
///
/// The row and the panel are pumped directly rather than through the editor
/// screen: both read the editor provider and nothing else, and a whole screen
/// scaffolded around them would test the screen's menu routing and its file
/// loading instead. The same route `effects_panel_test.dart` and
/// `text_animation_panel_test.dart` take.
void main() {
  VideoSegment clip(
    String id, {
    String? effectId,
    AnimatableDouble? intensity,
  }) {
    return VideoSegment(
      id: id,
      sourceStart: 0,
      sourceEnd: 10,
      effectId: effectId,
      effectIntensity: intensity ?? const AnimatableDouble(baseValue: 0.5),
    );
  }

  VideoEditorNotifier notifierWith(
    List<VideoSegment> segments, {
    String? selectedSegmentId,
    String? keyframeEditorSegmentId,
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: segments,
        selectedSegmentId: selectedSegmentId,
        isClipSelected: selectedSegmentId != null,
        keyframeEditorSegmentId: keyframeEditorSegmentId,
      );
  }

  Future<void> pumpPanel(
    WidgetTester tester,
    VideoEditorNotifier notifier,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: Scaffold(body: EffectsPanel())),
      ),
    );
    await tester.pump();
  }

  /// The row, at a known width so a progress maps to a predictable pixel.
  ///
  /// 400px wide starting at 0, so progress `p` sits at `400 * p` — which is
  /// what lets a drag assert on where the keyframe *landed* rather than merely
  /// that it moved.
  Future<void> pumpRow(
    WidgetTester tester,
    VideoEditorNotifier notifier, {
    double? playheadProgress,
    double? selectedProgress,
    void Function(double?)? onSelectionChanged,
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final segment = notifier.state.selectedSegment!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 400,
                  height: 26,
                  child: KeyframeRow(
                    segment: segment,
                    leftPx: 0,
                    widthPx: 400,
                    height: 26,
                    playheadProgress: playheadProgress,
                    selectedProgress: selectedProgress,
                    onSelectionChanged: onSelectionChanged ?? (_) {},
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: KeyframeRowControls(
                    segment: segment,
                    playheadProgress: playheadProgress,
                    selectedProgress: selectedProgress,
                    onSelectionChanged: onSelectionChanged ?? (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  AnimatableDouble intensityOf(VideoEditorNotifier notifier, [int index = 0]) =>
      notifier.state.segments[index].effectIntensity;

  group('the row does not exist until it is asked for', () {
    test('a clip with an effect and no ask shows no row', () {
      // **The casual path.** One tap on an effect tile, nothing else — and the
      // timeline has exactly the shape it had before keyframes existed.
      final notifier = notifierWith(
        [clip('a', effectId: 'vignette')],
        selectedSegmentId: 'a',
      );

      expect(notifier.state.keyframeEditorSegmentId, isNull);
      expect(notifier.state.showsKeyframeRowFor('a'), isFalse);
    });

    test('opening it names the clip that asked', () {
      final notifier = notifierWith(
        [clip('a', effectId: 'vignette'), clip('b', effectId: 'glitch')],
        selectedSegmentId: 'a',
      );

      notifier.openKeyframeEditor();

      expect(notifier.state.showsKeyframeRowFor('a'), isTrue);
      // Scoped to one clip: the other clip carries an effect too and still has
      // no row, and selecting it would close this one rather than carry a row
      // across to a clip that never asked for one.
      expect(notifier.state.showsKeyframeRowFor('b'), isFalse);
    });

    test('a clip with no effect cannot open one', () {
      // There is no parameter to keyframe, and a row over a value nothing
      // reads is exactly the unbidden control the design rules out.
      final notifier = notifierWith([clip('a')], selectedSegmentId: 'a');

      notifier.openKeyframeEditor();

      expect(notifier.state.keyframeEditorSegmentId, isNull);
      expect(notifier.state.showsKeyframeRowFor('a'), isFalse);
    });

    test('clearing the effect takes the row with it', () {
      // The row would already stop drawing — `showsKeyframeRowFor` needs an
      // effect — but a clip left *marked* as opted in would spring a diamond
      // row open again the moment any other effect was tapped.
      final notifier = notifierWith(
        [clip('a', effectId: 'vignette')],
        selectedSegmentId: 'a',
      );
      notifier.openKeyframeEditor();

      notifier.setClipEffect(null);

      expect(notifier.state.keyframeEditorSegmentId, isNull);

      notifier.setClipEffect('glitch');
      expect(notifier.state.showsKeyframeRowFor('a'), isFalse);
    });

    test('closing it keeps the keyframes', () {
      // Putting the tool away is not discarding the work.
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'vignette',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [Keyframe(progress: 0.5, value: 0.9)],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      notifier.openKeyframeEditor();

      notifier.closeKeyframeEditor();

      expect(notifier.state.keyframeEditorSegmentId, isNull);
      expect(intensityOf(notifier).keyframes, hasLength(1));
    });

    testWidgets('no Keyframe control until an effect is applied',
        (tester) async {
      final notifier = notifierWith([clip('a')], selectedSegmentId: 'a');
      await pumpPanel(tester, notifier);

      // It lives beside the intensity slider, which itself only exists once an
      // effect is applied.
      expect(find.byType(KeyframeToggleButton), findsNothing);

      await tester.tap(find.text('Vignette'));
      await tester.pump();

      expect(find.byType(KeyframeToggleButton), findsOneWidget);
      expect(
        tester.widget<KeyframeToggleButton>(find.byType(KeyframeToggleButton))
            .isOpen,
        isFalse,
        reason: 'the control is offered, but nothing is open until it is tapped',
      );
    });

    testWidgets('tapping it opens the row, and tapping again closes it',
        (tester) async {
      final notifier = notifierWith(
        [clip('a', effectId: 'vignette')],
        selectedSegmentId: 'a',
      );
      await pumpPanel(tester, notifier);

      await tester.tap(find.byType(KeyframeToggleButton));
      await tester.pump();

      expect(notifier.state.showsKeyframeRowFor('a'), isTrue);
      expect(
        tester.widget<KeyframeToggleButton>(find.byType(KeyframeToggleButton))
            .isOpen,
        isTrue,
      );

      // A toggle, not a one-way door: without a way back the row could never
      // be put away.
      await tester.tap(find.byType(KeyframeToggleButton));
      await tester.pump();
      expect(notifier.state.showsKeyframeRowFor('a'), isFalse);
    });

    testWidgets('opening the row is not an undo step', (tester) async {
      // Undo reverses a change to the project. An undo that closed a panel
      // instead would read as the button having failed.
      final notifier = notifierWith(
        [clip('a', effectId: 'vignette')],
        selectedSegmentId: 'a',
      );
      await pumpPanel(tester, notifier);

      await tester.tap(find.byType(KeyframeToggleButton));
      await tester.pump();

      expect(notifier.state.canUndo, isFalse);
    });
  });

  group('adding a keyframe never changes the picture', () {
    // **The most important property here.** Placing a keyframe switches the
    // parameter onto the keyframe path, where it stops following its envelope
    // — so if the first keyframe did not carry the envelope's own value at
    // that instant, the clip would visibly jump the moment Add was pressed.

    test('the first keyframe takes the envelope value at that instant', () {
      // `blur` ships with `ramp_out`, so this is a real fixture rather than a
      // constructed one.
      final effect = videoEffectById('blur')!;
      expect(
        effect.defaultEnvelope,
        isNotNull,
        reason: 'the fixture depends on blur carrying a default envelope',
      );

      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'blur',
            intensity: AnimatableDouble(
              baseValue: 0.8,
              envelope: effect.defaultEnvelope,
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );

      for (final at in [0.0, 0.17, 0.4, 0.62, 0.9, 1.0]) {
        final before = intensityOf(notifier).resolveAt(at);
        notifier.addEffectIntensityKeyframe(at);
        final after = intensityOf(notifier).resolveAt(at);

        expect(
          after,
          closeTo(before, 1e-9),
          reason: 'adding a keyframe at $at moved the value $before -> $after',
        );
      }
    });

    test('a later keyframe takes the interpolated value at that instant', () {
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'blur',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [
                Keyframe(progress: 0.0, value: 0.1),
                Keyframe(progress: 1.0, value: 0.9),
              ],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );

      final before = intensityOf(notifier).resolveAt(0.35);
      notifier.addEffectIntensityKeyframe(0.35);

      expect(intensityOf(notifier).keyframes, hasLength(3));
      expect(intensityOf(notifier).resolveAt(0.35), closeTo(before, 1e-9));
    });

    test('an explicit value is written when one is given', () {
      final notifier = notifierWith(
        [clip('a', effectId: 'vignette')],
        selectedSegmentId: 'a',
      );

      notifier.addEffectIntensityKeyframe(0.5, value: 0.25);

      expect(intensityOf(notifier).keyframes.single.value, 0.25);
    });

    test('adding twice at one instant replaces rather than stacks', () {
      // Two keyframes on one instant are legal in the model — a drag can put
      // them there — but pressing Add twice at a stationary playhead is
      // obviously one keyframe, and invisible duplicates under one diamond is
      // how a row starts lying about what it holds.
      final notifier = notifierWith(
        [clip('a', effectId: 'vignette')],
        selectedSegmentId: 'a',
      );

      notifier.addEffectIntensityKeyframe(0.5, value: 0.2);
      notifier.addEffectIntensityKeyframe(0.5, value: 0.7);

      expect(intensityOf(notifier).keyframes, hasLength(1));
      expect(intensityOf(notifier).keyframes.single.value, 0.7);
    });

    test('a clip with no effect cannot be keyframed', () {
      final notifier = notifierWith([clip('a')], selectedSegmentId: 'a');

      notifier.addEffectIntensityKeyframe(0.5);

      expect(intensityOf(notifier).keyframes, isEmpty);
    });

    testWidgets('Add places one at the playhead and never moves the value',
        (tester) async {
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'blur',
            intensity: AnimatableDouble(
              baseValue: 0.8,
              envelope: videoEffectById('blur')!.defaultEnvelope,
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      final before = intensityOf(notifier).resolveAt(0.25);

      await pumpRow(tester, notifier, playheadProgress: 0.25);
      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(intensityOf(notifier).keyframes, hasLength(1));
      expect(intensityOf(notifier).keyframes.single.progress, closeTo(0.25, 1e-9));
      expect(intensityOf(notifier).resolveAt(0.25), closeTo(before, 1e-9));
    });

    testWidgets('Add is disabled while the playhead is off the clip',
        (tester) async {
      // Rather than guessing at an instant the user is not looking at.
      final notifier = notifierWith(
        [clip('a', effectId: 'vignette')],
        selectedSegmentId: 'a',
      );
      await pumpRow(tester, notifier, playheadProgress: null);

      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(intensityOf(notifier).keyframes, isEmpty);
    });
  });

  group('keyframes override the envelope entirely', () {
    // The precedence lives once, in `AnimatableDouble.resolveAt`. Nothing in
    // the UI reimplements it — these tests assert the UI's edits reach that
    // rule rather than routing around it.

    test('one keyframe silences a pulsing envelope', () {
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'glow',
            intensity: AnimatableDouble(
              // `glow` ships with `throb`, so this is a real fixture.
              baseValue: 0.6,
              envelope: videoEffectById('glow')!.defaultEnvelope,
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      expect(intensityOf(notifier).envelope, isNotNull);

      // The envelope genuinely varies the value before anything is placed.
      final enveloped = [
        for (final p in [0.0, 0.25, 0.5, 0.75])
          intensityOf(notifier).resolveAt(p),
      ];
      expect(enveloped.toSet().length, greaterThan(1));

      notifier.addEffectIntensityKeyframe(0.5, value: 0.3);

      // One keyframe means "this value, for the whole clip" — it holds before
      // the first and after the last, with no envelope showing through.
      for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(
          intensityOf(notifier).resolveAt(p),
          closeTo(0.3, 1e-9),
          reason: 'the envelope still showed through at $p',
        );
      }
      // And the envelope is **kept on the parameter**, not stripped: deleting
      // the last keyframe hands the clip back the shape it was applied with.
      expect(intensityOf(notifier).envelope, isNotNull);
    });

    test('deleting the last keyframe restores the envelope', () {
      final envelope = videoEffectById('glow')!.defaultEnvelope;
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'glow',
            intensity: AnimatableDouble(baseValue: 0.6, envelope: envelope),
          ),
        ],
        selectedSegmentId: 'a',
      );
      final envelopedAtQuarter = intensityOf(notifier).resolveAt(0.25);

      notifier.addEffectIntensityKeyframe(0.5, value: 0.3);
      expect(intensityOf(notifier).resolveAt(0.25), closeTo(0.3, 1e-9));

      notifier.removeEffectIntensityKeyframe(0.5);

      expect(intensityOf(notifier).keyframes, isEmpty);
      expect(
        intensityOf(notifier).resolveAt(0.25),
        closeTo(envelopedAtQuarter, 1e-9),
      );
    });
  });

  group('editing the diamonds', () {
    testWidgets('a diamond is drawn per keyframe, at its own progress',
        (tester) async {
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'vignette',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [
                Keyframe(progress: 0.25, value: 0.2),
                Keyframe(progress: 0.75, value: 0.8),
              ],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      await pumpRow(tester, notifier);

      // The row is 400px wide and starts at 0, so 0.25 lands on 100 and 0.75
      // on 300 — a diamond that drifted from its own progress would be a row
      // telling a different story from the parameter under it.
      final diamonds = find.byType(KeyframeDiamond);
      expect(diamonds, findsNWidgets(2));

      final centres = tester
          .widgetList<KeyframeDiamond>(diamonds)
          .map((w) => tester.getCenter(find.byWidget(w)).dx)
          .toList()
        ..sort();
      expect(centres[0], closeTo(100, 1.0));
      expect(centres[1], closeTo(300, 1.0));
    });

    testWidgets('dragging a diamond moves its keyframe', (tester) async {
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'vignette',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [Keyframe(progress: 0.25, value: 0.4)],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      await pumpRow(tester, notifier);

      // From 100px (progress 0.25) to 300px (progress 0.75) across a 400px row.
      final gesture = await tester.startGesture(const Offset(100, 13));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      final moved = intensityOf(notifier).keyframes.single;
      expect(moved.progress, closeTo(0.75, 0.01));
      // The drag moves a keyframe in time. Its value and the way it travels
      // belong to the user, not to the gesture.
      expect(moved.value, 0.4);
      expect(moved.interpolation, KeyframeInterpolation.ease);
    });

    testWidgets('a whole drag is one undo step', (tester) async {
      // **The rule every drag in this codebase is written to.** A snapshot per
      // pointer move makes undo walk the drag back a pixel at a time.
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'vignette',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [Keyframe(progress: 0.25, value: 0.4)],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      await pumpRow(tester, notifier);

      final gesture = await tester.startGesture(const Offset(100, 13));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(intensityOf(notifier).keyframes.single.progress, closeTo(0.75, 0.01));

      notifier.undo();

      expect(
        intensityOf(notifier).keyframes.single.progress,
        closeTo(0.25, 1e-9),
        reason: 'one undo must return the whole gesture, not one frame of it',
      );
      expect(notifier.state.canUndo, isFalse);
    });

    testWidgets('a drag that overshoots the end stays on the finger',
        (tester) async {
      // Anchor-based, not a running sum of deltas: a delta dropped by the
      // clamp at the end is lost for good, and the diamond then sits offset
      // from the finger by however far it was pushed past the limit.
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'vignette',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [Keyframe(progress: 0.5, value: 0.4)],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      await pumpRow(tester, notifier);

      final gesture = await tester.startGesture(const Offset(200, 13));
      // Well past the right edge…
      await gesture.moveBy(const Offset(400, 0));
      await tester.pump();
      expect(intensityOf(notifier).keyframes.single.progress, closeTo(1.0, 1e-9));

      // …and back to exactly half the row's width from the anchor. With a
      // running sum the overshoot would have to be paid off first and the
      // keyframe would land short of 0.75.
      await gesture.moveBy(const Offset(-300, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        intensityOf(notifier).keyframes.single.progress,
        closeTo(0.75, 0.01),
        reason: 'the diamond drifted from the finger after hitting the clamp',
      );
    });

    testWidgets('tapping a diamond selects it', (tester) async {
      double? selected;
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'vignette',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [Keyframe(progress: 0.25, value: 0.4)],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      await pumpRow(
        tester,
        notifier,
        onSelectionChanged: (p) => selected = p,
      );

      await tester.tapAt(const Offset(100, 13));
      await tester.pump();

      expect(selected, closeTo(0.25, 1e-9));
    });

    testWidgets('Delete removes the selected keyframe', (tester) async {
      double? selected = 0.25;
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'vignette',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [
                Keyframe(progress: 0.25, value: 0.4),
                Keyframe(progress: 0.75, value: 0.9),
              ],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      await pumpRow(
        tester,
        notifier,
        selectedProgress: 0.25,
        onSelectionChanged: (p) => selected = p,
      );

      await tester.tap(find.text('Delete'));
      await tester.pump();

      expect(intensityOf(notifier).keyframes, hasLength(1));
      expect(intensityOf(notifier).keyframes.single.progress, 0.75);
      // The selection goes with it, or Delete would stay lit over nothing.
      expect(selected, isNull);
    });

    testWidgets('Delete does nothing while no diamond is selected',
        (tester) async {
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'vignette',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [Keyframe(progress: 0.25, value: 0.4)],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      await pumpRow(tester, notifier, selectedProgress: null);

      await tester.tap(find.text('Delete'));
      await tester.pump();

      expect(intensityOf(notifier).keyframes, hasLength(1));
    });

    testWidgets('the interpolation choice is written through', (tester) async {
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'vignette',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [
                Keyframe(progress: 0.0, value: 0.0),
                Keyframe(progress: 1.0, value: 1.0),
              ],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );
      await pumpRow(tester, notifier, selectedProgress: 0.0);

      await tester.tap(find.text('Hold'));
      await tester.pump();

      final first = intensityOf(notifier).keyframes.first;
      expect(first.interpolation, KeyframeInterpolation.hold);
      // The flag belongs to the segment that *starts* at this keyframe, which
      // is what makes Hold mean "stay here until the next one" — so the value
      // at the midpoint is the first keyframe's, not a blend.
      expect(intensityOf(notifier).resolveAt(0.5), closeTo(0.0, 1e-9));
      // Only the selected keyframe changed.
      expect(
        intensityOf(notifier).keyframes.last.interpolation,
        KeyframeInterpolation.ease,
      );

      await tester.tap(find.text('Linear'));
      await tester.pump();

      expect(
        intensityOf(notifier).keyframes.first.interpolation,
        KeyframeInterpolation.linear,
      );
      // Linear really is a straight line between the two.
      expect(intensityOf(notifier).resolveAt(0.5), closeTo(0.5, 1e-9));
    });

    test('moving a keyframe past another keeps hold of the right one', () {
      // Addressed by progress, not by index: the list is kept sorted, so
      // dragging one past another renumbers the rest.
      final notifier = notifierWith(
        [
          clip(
            'a',
            effectId: 'vignette',
            intensity: const AnimatableDouble(
              baseValue: 0.5,
              keyframes: [
                Keyframe(progress: 0.2, value: 0.1),
                Keyframe(progress: 0.6, value: 0.9),
              ],
            ),
          ),
        ],
        selectedSegmentId: 'a',
      );

      notifier.moveEffectIntensityKeyframe(0.2, 0.9);

      final keyframes = intensityOf(notifier).keyframes;
      expect(keyframes, hasLength(2));
      // Stored sorted, and the *values* travelled with their own keyframes.
      expect(keyframes[0].progress, closeTo(0.6, 1e-9));
      expect(keyframes[0].value, 0.9);
      expect(keyframes[1].progress, closeTo(0.9, 1e-9));
      expect(keyframes[1].value, 0.1);
    });
  });
}
