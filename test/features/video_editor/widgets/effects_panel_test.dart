import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_preview_atlases.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/effect_preview_provider.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/effect_preview_stage.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/effects_panel.dart';

/// The effects sheet works on effect bars: with no bar selected a tap adds
/// one at the playhead, with one selected a tap changes it.
///
/// The load-bearing assertion is the **count**: tiles must equal
/// `effectsInCategory(category).length`. That is the one check a new catalog
/// entry cannot slip past — its absence is what once left the text animation
/// tab offering seven of thirty animations.
///
/// The panel is pumped directly rather than through the editor screen: it
/// reads the editor provider and nothing else.
void main() {
  VideoEditorNotifier notifierWith({
    List<EffectBarModel> bars = const [],
    String? selectedEffectBarId,
    double playhead = 2,
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        assets: const [
          MediaAsset(
            id: 'asset',
            path: '/v.mp4',
            type: MediaAssetType.video,
            durationSeconds: 60,
            width: 1920,
            height: 1080,
            hasAudio: true,
          ),
        ],
        segments: [
          VideoSegment(id: 'c', assetId: 'asset', sourceStart: 0, sourceEnd: 20),
        ],
        currentPlaybackPosition: playhead,
        effectBars: bars,
        selectedEffectBarId: selectedEffectBarId,
        currentMenuId: selectedEffectBarId == null ? 'root' : 'effect_bar',
      );
  }

  EffectBarModel bar(String effect, {double intensity = 0.4}) => EffectBarModel(
        id: 'e',
        effectId: effect,
        start: 1,
        end: 6,
        intensity: AnimatableDouble(baseValue: intensity),
      );

  var pumpSeq = 0;

  Future<void> pumpPanel(
    WidgetTester tester,
    VideoEditorNotifier notifier,
  ) async {
    // A phone-shaped surface: on the harness's 800x600 each tile is taller
    // than the sheet and the labels lay out below it, untappable.
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    pumpSeq++;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoEditorProvider.overrideWith((ref) => notifier),
          // Answered at once, or every tile's ask would leave the cache's
          // timeout timer pending at the test's end. Failed keeps the icons,
          // which is what these tests lay out and tap.
          effectPreviewRendererProvider
              .overrideWithValue((_) async => const EffectPreviewFailed()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: EffectsPanel(key: ValueKey('panel-$pumpSeq')),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The category row scrolls; a tab is dragged fully into view before it is
  /// tapped, as a thumb would.
  Future<void> openCategory(WidgetTester tester, EffectCategory c) async {
    final tab = find.text(effectCategoryLabel(c));
    final row = find.byType(Scrollable).first;
    // From the row's start, so a tab left of the one last opened is reached
    // too — the walk below only ever moves forward.
    await tester.drag(row, const Offset(2000, 0));
    await tester.pump();
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

  int gridItemCount(WidgetTester tester) {
    final grid = tester.widget<GridView>(find.byType(GridView));
    return (grid.childrenDelegate as SliverChildBuilderDelegate).childCount!;
  }

  EffectTile tileFor(WidgetTester tester, String label) =>
      tester.widget<EffectTile>(
        find.ancestor(of: find.text(label), matching: find.byType(EffectTile)),
      );

  group('the order of the shelves', () {
    // A shelf is timed when its effects open over a fixed window — Intro and
    // Reveal. They play once and then rest, so they are not what the sheet
    // leads with: the lasting looks come first, fullest first, and the timed
    // shelves after them (the user's call).
    bool timed(EffectCategory c) =>
        effectsInCategory(c).any((e) => e.introSeconds != null);

    test('Retro comes first', () {
      expect(kEffectPanelCategories.first, EffectCategory.retro);
    });

    test('Intro and Reveal are neither first nor second', () {
      final firstTwo = kEffectPanelCategories.take(2);
      expect(firstTwo, isNot(contains(EffectCategory.intro)));
      expect(firstTwo, isNot(contains(EffectCategory.reveal)));
    });

    test('every lasting shelf comes before every timed one', () {
      final firstTimed = kEffectPanelCategories.indexWhere(timed);
      expect(firstTimed, greaterThan(0));
      expect(kEffectPanelCategories.skip(firstTimed).every(timed), isTrue);
    });

    test('after Retro, within each group the fullest shelf leads', () {
      for (final group in [
        kEffectPanelCategories
            .where((c) => !timed(c) && c != EffectCategory.retro)
            .toList(),
        kEffectPanelCategories.where(timed).toList(),
      ]) {
        final counts = group.map((c) => effectsInCategory(c).length).toList();
        for (var i = 1; i < counts.length; i++) {
          expect(counts[i], lessThanOrEqualTo(counts[i - 1]),
              reason: '${group[i]} outranks its left');
        }
      }
    });
  });

  testWidgets('offers every category except none', (tester) async {
    await pumpPanel(tester, notifierWith());
    expect(kEffectPanelCategories, isNot(contains(EffectCategory.none)));
    for (final category in kEffectPanelCategories) {
      await openCategory(tester, category);
      expect(find.text(effectCategoryLabel(category)), findsOneWidget);
    }
  });

  testWidgets('lists every catalog effect in the active category, and no None',
      (tester) async {
    for (final category in kEffectPanelCategories) {
      await pumpPanel(tester, notifierWith());
      await openCategory(tester, category);
      final expected = effectsInCategory(category);
      expect(gridItemCount(tester), expected.length,
          reason: '${category.name} must offer every catalog effect');
      expect(find.text('None'), findsNothing,
          reason: 'a bar is removed with Delete, not a None tile');
      for (final effect in expected) {
        await tester.scrollUntilVisible(
          find.text(effect.label),
          120,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text(effect.label), findsOneWidget, reason: effect.id);
      }
    }
  });

  testWidgets('switching category changes the tiles', (tester) async {
    await pumpPanel(tester, notifierWith());
    await openCategory(tester, EffectCategory.grade);
    expect(find.text('Vignette'), findsOneWidget);
    expect(find.text('VHS Tape'), findsNothing);
    await openCategory(tester, EffectCategory.retro);
    expect(find.text('VHS Tape'), findsOneWidget);
    expect(find.text('Vignette'), findsNothing);
  });

  testWidgets('no title and no apply-to-all: the sheet is the effects',
      (tester) async {
    await pumpPanel(tester, notifierWith());
    expect(find.text('Effects'), findsNothing);
    expect(find.byKey(const Key('effects_apply_all')), findsNothing);
  });

  testWidgets('with no bar selected the first tap adds one at the playhead',
      (tester) async {
    final notifier = notifierWith(playhead: 2);
    await pumpPanel(tester, notifier);
    expect(find.byType(Slider), findsNothing, reason: 'nothing to set yet');

    await openCategory(tester, EffectCategory.grade);
    await tester.tap(find.text('Vignette'));
    await tester.pump();

    final added = notifier.state.effectBars.single;
    expect((added.effectId, added.start, added.end), ('vignette', 2.0, 5.0));
    expect(notifier.state.selectedEffectBarId, added.id);
    expect(tileFor(tester, 'Vignette').isSelected, isTrue);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('a second tap changes that bar rather than adding another',
      (tester) async {
    final notifier = notifierWith();
    await pumpPanel(tester, notifier);
    await openCategory(tester, EffectCategory.grade);
    await tester.tap(find.text('Vignette'));
    await tester.pump();
    await tester.tap(find.text('Duotone'));
    await tester.pump();

    expect(notifier.state.effectBars.single.effectId, 'duotone');
    expect(tileFor(tester, 'Duotone').isSelected, isTrue);
    expect(tileFor(tester, 'Vignette').isSelected, isFalse);
  });

  testWidgets('opening the sheet adds nothing; only a tap does', (tester) async {
    final notifier = notifierWith();
    await pumpPanel(tester, notifier);
    await tester.pump(const Duration(seconds: 1));
    expect(notifier.state.effectBars, isEmpty);
    expect(notifier.state.canUndo, isFalse);
  });

  testWidgets('opened on a selected bar it shows that bar\'s effect',
      (tester) async {
    await pumpPanel(
      tester,
      notifierWith(bars: [bar('glow')], selectedEffectBarId: 'e'),
    );
    expect(gridItemCount(tester), effectsInCategory(EffectCategory.light).length,
        reason: 'the Light shelf is open');
    expect(tileFor(tester, videoEffectById('glow')!.label).isSelected, isTrue);
  });

  testWidgets('the slider reads and writes the bar\'s intensity',
      (tester) async {
    final notifier =
        notifierWith(bars: [bar('blur', intensity: 0.4)], selectedEffectBarId: 'e');
    await pumpPanel(tester, notifier);

    expect(find.text('40%'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, closeTo(0.4, 1e-9));
    expect((slider.min, slider.max), (0.0, 1.0));

    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump();
    final intensity = notifier.state.effectBars.single.intensity.baseValue;
    expect(intensity, greaterThan(0.4));
    expect(intensity, lessThanOrEqualTo(1.0));
    expect(notifier.state.effectBars.single.effectId, 'blur');
  });

  testWidgets('a whole slider drag is one undo step', (tester) async {
    final notifier =
        notifierWith(bars: [bar('blur', intensity: 0.4)], selectedEffectBarId: 'e');
    await pumpPanel(tester, notifier);
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    notifier.undo();
    expect(notifier.state.effectBars.single.intensity.baseValue, 0.4);
    expect(notifier.state.canUndo, isFalse);
  });

  testWidgets('on a keyframed bar the slider writes the keyframe, not the base',
      (tester) async {
    final keyed = bar('blur').copyWith(
      intensity: const AnimatableDouble(baseValue: 0.4, keyframes: [
        Keyframe(progress: 0, value: 0),
        Keyframe(progress: 1, value: 1),
      ]),
    );
    final notifier =
        notifierWith(bars: [keyed], selectedEffectBarId: 'e', playhead: 1);
    await pumpPanel(tester, notifier);
    expect(find.text('0%'), findsOneWidget, reason: 'the value at the playhead');
    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump();
    final intensity = notifier.state.effectBars.single.intensity;
    expect(intensity.baseValue, 0.4, reason: 'the base is untouched');
    expect(intensity.keyframes.first.value, greaterThan(0));
  });

  group('the tiles play', () {
    int firstFrame(WidgetTester tester) => tester
        .widget<EffectPreviewStage>(find.byType(EffectPreviewStage).first)
        .frameIndex
        .value;

    testWidgets('every tile has a stage for its effect', (tester) async {
      await pumpPanel(tester, notifierWith());
      // Only the tiles on screen are built (the grid keeps none off it), so
      // the stages are the opening shelf's first tiles, in order.
      final stages = tester
          .widgetList<EffectPreviewStage>(find.byType(EffectPreviewStage))
          .toList();
      final effects = effectsInCategory(kEffectPanelCategories.first);
      expect(stages, isNotEmpty);
      expect(stages.map((s) => s.effectId),
          effects.take(stages.length).map((e) => e.id));
    });

    testWidgets('the grid keeps no tiles off screen', (tester) async {
      await pumpPanel(tester, notifierWith());
      expect(
        tester.widget<GridView>(find.byType(GridView)).scrollCacheExtent,
        const ScrollCacheExtent.pixels(0),
      );
    });

    testWidgets('the frame index follows the clock', (tester) async {
      await pumpPanel(tester, notifierWith());
      expect(firstFrame(tester), 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(firstFrame(tester), greaterThanOrEqualTo(1));
    });

    testWidgets('the clock holds still while the grid scrolls', (tester) async {
      await pumpPanel(tester, notifierWith());
      await openCategory(tester, EffectCategory.intro);
      // Past the loop's 0.4 s plain beat first: frame 0 cannot tell a held
      // clock from the beat, so a hold caught there pins nothing.
      await tester.pump(const Duration(milliseconds: 600));
      expect(firstFrame(tester), greaterThanOrEqualTo(1));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GridView)),
      );
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      final held = firstFrame(tester);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(firstFrame(tester), held);
      await gesture.up();
      await tester.pump();
      // The first stretch absorbs the release's ballistic scroll settling;
      // the second runs the resumed clock past the loop's 0.4 s plain beat,
      // where the frame is 0 whether or not the clock moves.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(firstFrame(tester), isNot(held));
    });

    group('with atlases that decode', () {
      late List<ui.Image> created;

      setUp(() => created = []);

      Future<ui.Image> fakeDecode(Uint8List bytes) async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 8, 8),
          Paint()..color = const Color(0xFF224466),
        );
        final picture = recorder.endRecording();
        final image = picture.toImageSync(800, 720);
        picture.dispose();
        created.add(image);
        return image;
      }

      Future<void> pumpPlaying(WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              videoEditorProvider.overrideWith((ref) => notifierWith()),
              effectPreviewRendererProvider.overrideWithValue(
                (bar) async => EffectPreviewAtlas(Uint8List.fromList([1])),
              ),
              effectAtlasDecoderProvider.overrideWithValue(fakeDecode),
            ],
            child: const MaterialApp(
              home: Scaffold(body: EffectsPanel(key: ValueKey('playing'))),
            ),
          ),
        );
        // The atlases draw one at a time; a few pumps settle the category.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      testWidgets("switching category disposes the old tiles' images",
          (tester) async {
        await pumpPlaying(tester);
        expect(created, isNotEmpty);
        final before = List.of(created);
        // Any tab but the one the sheet opened on.
        await openCategory(tester, kEffectPanelCategories[1]);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        for (final image in before) {
          expect(image.debugDisposed, isTrue);
        }
      });

      testWidgets('closing the sheet disposes every image', (tester) async {
        await pumpPlaying(tester);
        expect(created, isNotEmpty);
        await tester.pumpWidget(const SizedBox());
        for (final image in created) {
          expect(image.debugDisposed, isTrue);
        }
      });
    });
  });
}
