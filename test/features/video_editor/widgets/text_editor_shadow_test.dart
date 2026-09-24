import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_editor_dialog.dart';

import '../../../support/test_fonts.dart';

/// The Style tab's shadow controls.
///
/// A shadow's colour was all the user could choose. Opacity, blur, distance
/// and angle sit under the Shadow target now, exactly as Thickness sits under
/// Outline and Radius/Padding under Background: shown once the target has a
/// colour. Every slider in the tab writes live, and **a drag is one undo
/// step** — the tab's sliders used to push an undo entry per frame.
void main() {
  TextOverlayModel text({
    Color shadow = Colors.transparent,
    Color outline = Colors.transparent,
    double outlineWidth = 0,
  }) =>
      TextOverlayModel(
        id: 't',
        text: 'Hi',
        fontFamily: kTestFontFamily,
        shadowColor: shadow,
        strokeColor: outline,
        strokeWidth: outlineWidth,
      );

  Future<VideoEditorNotifier> openStyle(
    WidgetTester tester,
    TextOverlayModel overlay,
  ) async {
    final notifier = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(textOverlays: [overlay]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                // The provider is autoDispose; the editor screen keeps it
                // alive by watching it, and so does this host.
                ref.watch(videoEditorProvider);
                return ElevatedButton(
                  onPressed: () => showTextEditor(
                    context: context,
                    overlay: overlay,
                    ref: ref,
                    initialTool: TextEditorTool.style,
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return notifier;
  }

  Future<void> target(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// The slider on the row labelled [label], scrolled into view.
  Future<Finder> sliderFor(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    return find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
      matching: find.byType(Slider),
    );
  }

  TextOverlayModel current(VideoEditorNotifier n) => n.state.textOverlays.single;

  const controls = ['Opacity', 'Blur', 'Distance', 'Angle'];

  testWidgets('Shadow offers opacity, blur, distance and angle once it has '
      'a colour', (tester) async {
    await openStyle(tester, text(shadow: Colors.black));
    await target(tester, 'Shadow');
    for (final label in controls) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('and none of them while it has no colour', (tester) async {
    await openStyle(tester, text());
    await target(tester, 'Shadow');
    for (final label in controls) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });

  for (final (label, read) in [
    ('Opacity', (TextOverlayModel o) => o.shadowOpacity),
    ('Blur', (TextOverlayModel o) => o.shadowBlurRadius),
    ('Distance', (TextOverlayModel o) => o.shadowDistance),
    ('Angle', (TextOverlayModel o) => o.shadowAngle),
  ]) {
    testWidgets('$label writes live, and a drag is one undo step',
        (tester) async {
      final n = await openStyle(tester, text(shadow: Colors.black));
      await target(tester, 'Shadow');
      final before = read(current(n));

      await tester.drag(await sliderFor(tester, label), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(read(current(n)), isNot(before), reason: 'written live');

      n.undo();
      expect(read(current(n)), before);
      expect(n.state.canUndo, isFalse, reason: 'one entry for the drag');
    });
  }

  testWidgets("the outline's Thickness drag is one undo step too",
      (tester) async {
    // Every frame of this slider went through `updateTextOverlay`, which
    // snapshots per call: Undo walked the drag back a frame at a time.
    final n = await openStyle(
      tester,
      text(outline: Colors.black, outlineWidth: 5),
    );
    await target(tester, 'Outline');

    await tester.drag(
      await sliderFor(tester, 'Thickness'),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    expect(current(n).strokeWidth, isNot(5));

    n.undo();
    expect(current(n).strokeWidth, 5);
    expect(n.state.canUndo, isFalse);
  });

  testWidgets('a preset is a complete look: it resets the shadow tuning',
      (tester) async {
    final n = await openStyle(
      tester,
      text(shadow: Colors.black).copyWith(shadowDistance: 15, shadowAngle: 200),
    );
    await tester.tap(find.text('Aa').first);
    await tester.pumpAndSettle();

    expect(current(n).shadowDistance, kTextShadowDefaultDistance);
    expect(current(n).shadowAngle, kTextShadowDefaultAngle);
  });
}
