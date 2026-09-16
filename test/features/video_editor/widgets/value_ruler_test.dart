import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/value_ruler.dart';

/// The ruler every Transform tab is built from.
///
/// A strip of ticks that slides under the finger, a fixed centre indicator,
/// and a readout. **Dragging right raises the value** — the direction the user
/// specified — and the ticks travel with the finger, so the motion and the
/// number agree.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required double value,
    required double min,
    required double max,
    double unitsPerPixel = 0.01,
    ValueChanged<double>? onChanged,
    VoidCallback? onChangeStart,
    VoidCallback? onChangeEnd,
    VoidCallback? onReset,
    List<double> snapPoints = const [],
    String Function(double)? format,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ValueRuler(
                value: value,
                min: min,
                max: max,
                unitsPerPixel: unitsPerPixel,
                onChanged: onChanged ?? (_) {},
                onChangeStart: onChangeStart,
                onChangeEnd: onChangeEnd,
                onReset: onReset,
                snapPoints: snapPoints,
                format: format ?? (v) => v.toStringAsFixed(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('direction', () {
    testWidgets('dragging right raises the value, left lowers it',
        (tester) async {
      var value = 1.0;
      await pump(tester, value: 1.0, min: 0.1, max: 8.0,
          onChanged: (v) => value = v);

      await tester.drag(find.byType(ValueRuler), const Offset(60, 0));
      expect(value, greaterThan(1.0));

      await pump(tester, value: value, min: 0.1, max: 8.0,
          onChanged: (v) => value = v);
      final raised = value;
      await tester.drag(find.byType(ValueRuler), const Offset(-60, 0));
      expect(value, lessThan(raised));
    });

    testWidgets('sixty pixels at 0.01 per pixel is 0.6', (tester) async {
      // The sensitivity is the contract each tab tunes: pixels travelled,
      // not a fraction of the widget's width, so precision does not depend on
      // the phone.
      var value = 1.0;
      await pump(tester, value: 1.0, min: 0, max: 10,
          onChanged: (v) => value = v);
      await tester.drag(find.byType(ValueRuler), const Offset(60, 0));
      expect(value, closeTo(1.6, 1e-6));
    });
  });

  group('range', () {
    testWidgets('the value is clamped to its range', (tester) async {
      var value = 1.0;
      await pump(tester, value: 1.0, min: 0.5, max: 2.0,
          onChanged: (v) => value = v);
      await tester.drag(find.byType(ValueRuler), const Offset(5000, 0));
      expect(value, 2.0);

      await pump(tester, value: value, min: 0.5, max: 2.0,
          onChanged: (v) => value = v);
      await tester.drag(find.byType(ValueRuler), const Offset(-5000, 0));
      expect(value, 0.5);
    });

    testWidgets('it tracks an anchor, not accumulated deltas', (tester) async {
      // A delta dropped at a clamp is lost for good, leaving the ruler offset
      // from the finger — the fault the trim handles already fixed once.
      // Slam into the maximum and come all the way back: the value must
      // return to where the finger started, not stop short by the overshoot.
      var value = 1.0;
      await pump(tester, value: 1.0, min: 0.0, max: 2.0,
          onChanged: (v) => value = v);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(ValueRuler)));
      await gesture.moveBy(const Offset(4000, 0));
      await tester.pump();
      expect(value, 2.0);
      await gesture.moveBy(const Offset(-4000, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(value, closeTo(1.0, 1e-6),
          reason: 'returning to the start position returns the start value');
    });
  });

  group('one gesture, one undo step', () {
    testWidgets('start and end are each reported once per drag',
        (tester) async {
      // The ruler reports the ends of a gesture; the notifier snapshots once
      // on start. Snapshotting per change would make undo walk a drag back a
      // pixel at a time.
      var starts = 0;
      var ends = 0;
      await pump(tester, value: 1.0, min: 0, max: 2,
          onChangeStart: () => starts++, onChangeEnd: () => ends++);
      await tester.drag(find.byType(ValueRuler), const Offset(40, 0));
      expect(starts, 1);
      expect(ends, 1);
    });
  });

  group('snapping', () {
    testWidgets('lands exactly on a snap point when close', (tester) async {
      // A rotation that reads 89.6° is a mistake nobody meant. Within the
      // snap radius the value lands on the point itself.
      var value = 0.0;
      await pump(tester, value: 0.0, min: -180, max: 180, unitsPerPixel: 0.5,
          snapPoints: const [0, 90, -90, 180, -180],
          onChanged: (v) => value = v);
      // 178px * 0.5 = 89°, inside the radius of 90.
      await tester.drag(find.byType(ValueRuler), const Offset(178, 0));
      expect(value, 90.0);
    });

    testWidgets('does not snap from far away', (tester) async {
      var value = 0.0;
      await pump(tester, value: 0.0, min: -180, max: 180, unitsPerPixel: 0.5,
          snapPoints: const [0, 90],
          onChanged: (v) => value = v);
      // 120px * 0.5 = 60°, nowhere near 90.
      await tester.drag(find.byType(ValueRuler), const Offset(120, 0));
      expect(value, closeTo(60.0, 1e-6));
    });
  });

  group('readout', () {
    testWidgets('shows the formatted value', (tester) async {
      await pump(tester, value: 1.5, min: 0, max: 8,
          format: (v) => '${v.toStringAsFixed(1)}×');
      expect(find.text('1.5×'), findsOneWidget);
    });

    testWidgets('tapping the readout resets', (tester) async {
      // The default is one tap away, which is what makes exploring safe.
      var resets = 0;
      await pump(tester, value: 2.4, min: 0, max: 8, onReset: () => resets++);
      await tester.tap(find.byKey(const Key('value_ruler_readout')));
      expect(resets, 1);
    });
  });
}
