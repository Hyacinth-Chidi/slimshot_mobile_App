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

/// The effects sheet's contract with the catalog.
///
/// The load-bearing assertion is the **count**: tiles must equal
/// `effectsInCategory(category).length + 1`. That is the one check a new
/// catalog entry cannot slip past, and its absence is exactly what left the
/// text animation tab offering seven of thirty animations — the device
/// tester's report was "the new animations, I'm not seeing them".
///
/// The panel is pumped directly rather than through the editor screen's
/// `showModalBottomSheet`: it reads the editor provider and nothing else, so a
/// whole screen scaffolded around it would test the screen's menu routing, not
/// the panel. The same route `text_animation_panel_test.dart` takes.
void main() {
  VideoSegment clip(
    String id, {
    String? effectId,
    double effectIntensity = defaultEffectIntensity,
  }) {
    return VideoSegment(
      id: id,
      sourceStart: 0,
      sourceEnd: 5,
      effectId: effectId,
      effectIntensity: AnimatableDouble(baseValue: effectIntensity),
    );
  }

  VideoEditorNotifier notifierWith(
    List<VideoSegment> segments, {
    String? selectedSegmentId,
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: segments,
        selectedSegmentId: selectedSegmentId,
        isClipSelected: selectedSegmentId != null,
      );
  }

  var pumpSeq = 0;

  Future<void> pumpPanel(
    WidgetTester tester,
    VideoEditorNotifier notifier,
  ) async {
    // A phone-shaped surface, not the test harness's default 800×600. The
    // panel is a fraction of the screen height with a fixed-column grid, so on
    // a wide viewport each tile is ~190px across and, at the grid's aspect,
    // taller than the whole sheet — the labels then lay out below the panel
    // and cannot be tapped. That is a property of the test surface, not of the
    // panel, so the surface is what changes.
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A fresh key per pump so a test pumping twice gets a genuinely new panel
    // rather than the previous one's category and scroll offset carried over.
    pumpSeq++;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: EffectsPanel(key: ValueKey('panel-$pumpSeq')),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The category row is horizontally scrollable because five shelves do not
  /// fit a phone width, so a tab has to be brought fully on screen before it
  /// can be tapped — the same thing a user does with their thumb.
  ///
  /// `scrollUntilVisible` is no good here: it stops as soon as the finder
  /// *matches*, and a tab straddling the right edge matches while still being
  /// unhittable. So the row is dragged until the tab's rect actually sits
  /// inside the viewport.
  Future<void> openCategory(WidgetTester tester, EffectCategory c) async {
    final tab = find.text(effectCategoryLabel(c));
    final row = find.byType(Scrollable).first;

    for (var i = 0; i < 12; i++) {
      final rowRect = tester.getRect(row);
      if (tab.evaluate().isNotEmpty) {
        final rect = tester.getRect(tab);
        if (rect.left >= rowRect.left && rect.right <= rowRect.right) break;
      }
      await tester.drag(row, const Offset(-80, 0));
      await tester.pump();
    }

    await tester.tap(tab);
    await tester.pump();
  }

  /// What the grid *would* build, rather than what fits on screen.
  int gridItemCount(WidgetTester tester) {
    final grid = tester.widget<GridView>(find.byType(GridView));
    return (grid.childrenDelegate as SliverChildBuilderDelegate).childCount!;
  }

  EffectTile tileFor(WidgetTester tester, String label) =>
      tester.widget<EffectTile>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(EffectTile),
        ),
      );

  testWidgets('offers every category except none', (tester) async {
    await pumpPanel(tester, notifierWith([clip('a')], selectedSegmentId: 'a'));

    for (final category in EffectCategory.values) {
      final finder = find.text(effectCategoryLabel(category));
      if (category == EffectCategory.none) {
        // `none` holds no catalog entries, so a tab for it would be an empty
        // shelf — the absence is reached through the None *tile* instead.
        expect(
          kEffectPanelCategories,
          isNot(contains(category)),
          reason: 'none names the absence of an effect, not a shelf',
        );
      } else {
        await openCategory(tester, category);
        expect(finder, findsOneWidget);
      }
    }
  });

  testWidgets('lists every catalog effect in the active category',
      (tester) async {
    // **The assertion this panel exists to keep honest.** Counted against the
    // catalog rather than a fixed number, so a new entry cannot silently miss
    // the UI.
    for (final category in kEffectPanelCategories) {
      await pumpPanel(
        tester,
        notifierWith([clip('a')], selectedSegmentId: 'a'),
      );
      await openCategory(tester, category);

      final expected = effectsInCategory(category);
      expect(
        gridItemCount(tester),
        expected.length + 1,
        reason: '${category.name} must offer every catalog effect, plus None',
      );

      // None leads the grid, so it is on screen before anything scrolls.
      expect(find.text('None'), findsOneWidget);

      // And every entry really builds a tile with its own label, so the count
      // cannot be satisfied by padding the grid with blanks.
      for (final effect in expected) {
        await tester.scrollUntilVisible(
          find.text(effect.label),
          120,
          scrollable: find.byType(Scrollable).last,
        );
        expect(
          find.text(effect.label),
          findsOneWidget,
          reason: '${effect.id} is in the catalog but the panel omits it',
        );
      }
    }
  });

  testWidgets('switching category changes the tiles', (tester) async {
    await pumpPanel(tester, notifierWith([clip('a')], selectedSegmentId: 'a'));

    await openCategory(tester, EffectCategory.grade);
    expect(gridItemCount(tester), effectsInCategory(EffectCategory.grade).length + 1);
    expect(find.text('Vignette'), findsOneWidget);
    // A retro effect is not merely scrolled off — it is not built.
    expect(find.text('VHS Tape'), findsNothing);

    await openCategory(tester, EffectCategory.retro);
    expect(gridItemCount(tester), effectsInCategory(EffectCategory.retro).length + 1);
    expect(find.text('VHS Tape'), findsOneWidget);
    expect(find.text('Vignette'), findsNothing);
  });

  testWidgets('tapping a tile writes its id to the selected segment',
      (tester) async {
    final notifier = notifierWith(
      [clip('a'), clip('b')],
      selectedSegmentId: 'b',
    );
    await pumpPanel(tester, notifier);
    await openCategory(tester, EffectCategory.retro);

    await tester.tap(find.text('VHS Tape'));
    await tester.pump();

    expect(notifier.state.segments[1].effectId, 'vhs');
    // The unselected clip is untouched: an effect belongs to one clip.
    expect(notifier.state.segments[0].effectId, isNull);
    // One tap is the whole interaction — the catalog's default intensity is
    // applied, so the effect is visibly itself without touching the slider.
    expect(
      notifier.state.segments[1].effectIntensity.baseValue,
      videoEffectById('vhs')!.defaultIntensity,
    );
  });

  testWidgets('the None tile clears the effect', (tester) async {
    // A cleared effect must go through `clearEffectId`: `copyWith` ignores a
    // bare null for a nullable field by convention, so the old effect would
    // silently stay and None would read as a dead tile.
    final notifier = notifierWith(
      [clip('a', effectId: 'glitch')],
      selectedSegmentId: 'a',
    );
    await pumpPanel(tester, notifier);

    await tester.tap(find.text('None'));
    await tester.pump();

    expect(notifier.state.segments[0].effectId, isNull);
    expect(notifier.state.segments[0].effect, isNull);
  });

  testWidgets('a stored effect id shows its tile selected', (tester) async {
    final notifier = notifierWith(
      [clip('a', effectId: 'swirl')],
      selectedSegmentId: 'a',
    );
    await pumpPanel(tester, notifier);

    // The panel opens on the shelf the applied effect lives on, so reopening
    // the sheet shows what is applied rather than making the user hunt.
    expect(tileFor(tester, 'Swirl').isSelected, isTrue);
    expect(tileFor(tester, 'Ripple').isSelected, isFalse);
    expect(tileFor(tester, 'None').isSelected, isFalse);
  });

  testWidgets('no effect highlights None', (tester) async {
    await pumpPanel(tester, notifierWith([clip('a')], selectedSegmentId: 'a'));

    expect(tileFor(tester, 'None').isSelected, isTrue);
    for (final effect in effectsInCategory(kEffectPanelCategories.first)) {
      expect(tileFor(tester, effect.label).isSelected, isFalse);
    }
  });

  testWidgets('an unknown stored id highlights None rather than nothing',
      (tester) async {
    // A draft from a newer build, or an unmigrated rename. It must read as no
    // effect, not as a selection nothing draws.
    final notifier = notifierWith(
      [clip('a', effectId: 'from_the_future')],
      selectedSegmentId: 'a',
    );
    await pumpPanel(tester, notifier);

    expect(tileFor(tester, 'None').isSelected, isTrue);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('the slider is hidden until an effect is applied',
      (tester) async {
    await pumpPanel(tester, notifierWith([clip('a')], selectedSegmentId: 'a'));
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('Vignette'));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('the slider reads and writes intensity as a percentage',
      (tester) async {
    final notifier = notifierWith(
      [clip('a', effectId: 'blur', effectIntensity: 0.4)],
      selectedSegmentId: 'a',
    );
    await pumpPanel(tester, notifier);

    expect(find.text('40%'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, closeTo(0.4, 1e-9));
    // Normalised 0..1, never a pixel radius — a pixel parameter would render
    // differently in a ~400px preview and a 1080p export.
    expect(slider.min, 0.0);
    expect(slider.max, 1.0);

    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump();

    expect(notifier.state.segments[0].effectIntensity.baseValue, greaterThan(0.4));
    expect(notifier.state.segments[0].effectIntensity.baseValue, lessThanOrEqualTo(1.0));
    // The effect itself is unchanged: only its strength moved.
    expect(notifier.state.segments[0].effectId, 'blur');
  });

  testWidgets('the slider writes the base value and keeps the envelope',
      (tester) async {
    // **The rule that makes an enveloped intensity survive being retuned.** The
    // slider re-sends the strength on every frame of a drag, so a setter that
    // rebuilt the parameter from scratch would wipe the envelope on the first
    // pixel of movement — and the user would watch their pulsing glitch go flat
    // while adjusting its strength.
    //
    // No keyframes on this clip, so the edit rule writes the base. That is the
    // path every project takes until someone places a diamond.
    final notifier = notifierWith(
      [clip('a', effectId: 'blur', effectIntensity: 0.4)],
      selectedSegmentId: 'a',
    );
    notifier.state = notifier.state.copyWith(
      segments: [
        notifier.state.segments[0].copyWith(
          effectIntensity: const AnimatableDouble(
            baseValue: 0.4,
            envelope: 'pulse',
          ),
        ),
      ],
    );
    await pumpPanel(tester, notifier);

    // The slider shows the *base* value, not the parameter's value at some
    // playhead: a slider tracking the resolved value would wander while
    // playing and write back one frame of the curve when grabbed.
    expect(tester.widget<Slider>(find.byType(Slider)).value, closeTo(0.4, 1e-9));

    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump();

    final intensity = notifier.state.segments[0].effectIntensity;
    expect(intensity.baseValue, greaterThan(0.4));
    expect(intensity.envelope, 'pulse');
    expect(intensity.keyframes, isEmpty);
  });

  testWidgets('on a keyframed clip the slider writes the keyframe, not the base',
      (tester) async {
    // **The slider has no idea keyframes exist.** It calls one setter and the
    // edit rule decides; that is what lets the effects sheet carry no keyframe
    // control of its own, which is the whole correction this rebuild makes.
    final notifier = notifierWith(
      [clip('a', effectId: 'blur', effectIntensity: 0.4)],
      selectedSegmentId: 'a',
    );
    // A diamond exactly under the playhead, which is parked at 0.
    notifier.addKeyframeAtPlayhead();
    await pumpPanel(tester, notifier);

    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump();

    final intensity = notifier.state.segments[0].effectIntensity;
    expect(intensity.keyframes, hasLength(1));
    expect(intensity.keyframes.single.value, greaterThan(0.4));
    // The base is untouched: the user is editing a moment, not the clip.
    expect(intensity.baseValue, closeTo(0.4, 1e-9));
  });


  testWidgets('applying a different effect drops the old effect\'s shape',
      (tester) async {
    // An envelope belongs to the effect it was applied with — a glitch's pulse
    // means nothing on a vignette — so switching effects rebuilds the
    // parameter rather than inheriting a curve the new effect never asked for.
    final notifier = notifierWith(
      [clip('a', effectId: 'blur')],
      selectedSegmentId: 'a',
    );
    notifier.state = notifier.state.copyWith(
      segments: [
        notifier.state.segments[0].copyWith(
          effectIntensity: AnimatableDouble.sorted(
            baseValue: 0.4,
            envelope: 'throb',
            keyframes: const [Keyframe(progress: 0.5, value: 0.9)],
          ),
        ),
      ],
    );
    await pumpPanel(tester, notifier);
    await openCategory(tester, EffectCategory.grade);

    await tester.tap(find.text('Vignette'));
    await tester.pump();

    final intensity = notifier.state.segments[0].effectIntensity;
    expect(notifier.state.segments[0].effectId, 'vignette');
    expect(intensity.keyframes, isEmpty);
    // Whatever the new effect declares — today `vignette` is a static grade
    // and declares none.
    expect(intensity.envelope, videoEffectById('vignette')!.defaultEnvelope);
  });

  testWidgets('clearing the effect leaves a flat parameter', (tester) async {
    // A clip with no effect holding a pulse would put an envelope back the
    // moment any effect was applied, which the user never asked for.
    final notifier = notifierWith(
      [clip('a', effectId: 'blur')],
      selectedSegmentId: 'a',
    );
    notifier.state = notifier.state.copyWith(
      segments: [
        notifier.state.segments[0].copyWith(
          effectIntensity:
              const AnimatableDouble(baseValue: 0.4, envelope: 'pulse'),
        ),
      ],
    );
    await pumpPanel(tester, notifier);

    await tester.tap(find.text('None'));
    await tester.pump();

    expect(notifier.state.segments[0].effectId, isNull);
    expect(notifier.state.segments[0].effectIntensity.isAnimated, isFalse);
  });

  testWidgets('a whole slider drag is one undo step', (tester) async {
    // Going through the snapshotting setter per frame makes undo walk the drag
    // back a pixel at a time.
    final notifier = notifierWith(
      [clip('a', effectId: 'blur', effectIntensity: 0.4)],
      selectedSegmentId: 'a',
    );
    await pumpPanel(tester, notifier);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(notifier.state.segments[0].effectIntensity.baseValue, greaterThan(0.4));
    notifier.undo();
    expect(notifier.state.segments[0].effectIntensity.baseValue, closeTo(0.4, 1e-9));
  });

  testWidgets('a tap is its own undo step', (tester) async {
    final notifier = notifierWith([clip('a')], selectedSegmentId: 'a');
    await pumpPanel(tester, notifier);

    await tester.tap(find.text('Vignette'));
    await tester.pump();
    expect(notifier.state.segments[0].effectId, 'vignette');

    notifier.undo();
    expect(notifier.state.segments[0].effectId, isNull);
  });

  testWidgets('with no clip selected it offers nothing to apply to',
      (tester) async {
    // Rather than guessing at a target — an effect belongs to a clip.
    await pumpPanel(tester, notifierWith([clip('a')]));

    expect(find.byType(GridView), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.textContaining('Select a clip'), findsOneWidget);
  });
}
