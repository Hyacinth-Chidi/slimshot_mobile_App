import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
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

  /// The category row scrolls; a tab is dragged fully into view before it is
  /// tapped, as a thumb would.
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

  int gridItemCount(WidgetTester tester) {
    final grid = tester.widget<GridView>(find.byType(GridView));
    return (grid.childrenDelegate as SliverChildBuilderDelegate).childCount!;
  }

  EffectTile tileFor(WidgetTester tester, String label) =>
      tester.widget<EffectTile>(
        find.ancestor(of: find.text(label), matching: find.byType(EffectTile)),
      );

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
}
