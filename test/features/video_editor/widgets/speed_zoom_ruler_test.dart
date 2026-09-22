import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/speed_panel.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/value_ruler.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/zoom_panel.dart';

/// Speed and Zoom are set with the `ValueRuler`, not a Material slider.
///
/// The ruler's reason (see its own doc) is that sensitivity is **per pixel**
/// rather than per widget width, so a large range stays settable to two
/// decimals on any screen. That argument is strongest exactly here:
///
/// - Speed's model range is 0.1x–10x (`SpeedCurve.kMinSpeed/kMaxSpeed`), and
///   the slider reached only **2x** — 4x was unreachable from the Speed tool
///   at all. A slider spanning 0.1–10 would put 1x a tenth of the way along
///   and make every ordinary value a pixel-hunt.
/// - Zoom runs 1x–5x, where a tenth of a step is a visible difference.
///
/// Volume and Opacity deliberately keep their sliders: 0–100% on a track is
/// the universal idiom and precision there is not worth a second gesture.
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(height: 160, child: child)),
      );

  group('speed', () {
    testWidgets('is a ruler, and reaches the range the model allows',
        (tester) async {
      await tester.pumpWidget(host(
        SpeedPanel(displaySpeed: 1.0, onChanged: (_) {}),
      ));

      expect(find.byType(ValueRuler), findsOneWidget);
      expect(find.byType(Slider), findsNothing);

      final ruler = tester.widget<ValueRuler>(find.byType(ValueRuler));
      expect(ruler.min, 0.1, reason: 'the model floor');
      expect(ruler.max, 10.0, reason: '2x was an arbitrary UI ceiling');
    });

    testWidgets('reads as a multiplier', (tester) async {
      await tester.pumpWidget(host(
        SpeedPanel(displaySpeed: 2.5, onChanged: (_) {}),
      ));
      expect(find.text('2.5x'), findsOneWidget);
    });

    testWidgets('a drag is one undo step', (tester) async {
      var starts = 0;
      var ends = 0;
      await tester.pumpWidget(host(
        SpeedPanel(
          displaySpeed: 1.0,
          onChanged: (_) {},
          onChangeStart: () => starts++,
          onChangeEnd: () => ends++,
        ),
      ));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(ValueRuler)));
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(starts, 1);
      expect(ends, 1);
    });

    testWidgets('an empty message replaces the control', (tester) async {
      await tester.pumpWidget(host(
        SpeedPanel(
          displaySpeed: 1.0,
          onChanged: (_) {},
          emptyMessage: 'Select a clip',
        ),
      ));
      expect(find.text('Select a clip'), findsOneWidget);
      expect(find.byType(ValueRuler), findsNothing);
    });
  });

  group('zoom', () {
    testWidgets('is a ruler over the zoom range', (tester) async {
      await tester.pumpWidget(host(
        ZoomPanel(currentScale: 1.0, onChanged: (_) {}, onReset: () {}),
      ));

      expect(find.byType(ValueRuler), findsOneWidget);
      expect(find.byType(Slider), findsNothing);

      final ruler = tester.widget<ValueRuler>(find.byType(ValueRuler));
      expect(ruler.min, 1.0);
      expect(ruler.max, 5.0);
    });

    testWidgets('reads as a percentage', (tester) async {
      await tester.pumpWidget(host(
        ZoomPanel(currentScale: 2.5, onChanged: (_) {}, onReset: () {}),
      ));
      expect(find.text('250%'), findsOneWidget);
    });

    testWidgets('Reset appears only when there is something to reset',
        (tester) async {
      await tester.pumpWidget(host(
        ZoomPanel(currentScale: 1.0, onChanged: (_) {}, onReset: () {}),
      ));
      expect(find.text('Reset'), findsNothing);

      var resets = 0;
      await tester.pumpWidget(host(
        ZoomPanel(
          currentScale: 2.0,
          onChanged: (_) {},
          onReset: () => resets++,
        ),
      ));
      expect(find.text('Reset'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      expect(resets, 1);
    });
  });
}
