import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/timeline_zoom.dart';

/// Pinch-to-zoom on the timeline: how far it may go, and what the ruler does.
void main() {
  group('the zoom range', () {
    test('opens at today\'s scale', () {
      expect(kDefaultPixelsPerSecond, 50);
    });

    test('zooms in to frame precision', () {
      // A 30fps frame at least ~20px wide: a cut can land on an exact frame.
      expect(kMaxPixelsPerSecond / 30, greaterThanOrEqualTo(20));
    });

    test('zooms out until the whole project fits most of the screen', () {
      final min = minPixelsPerSecond(viewportWidth: 400, durationSeconds: 180);
      expect(180 * min, closeTo(400 * kZoomOutFitFraction, 1e-9));
    });

    test('never needs zooming out past the default for a short project', () {
      expect(
        minPixelsPerSecond(viewportWidth: 400, durationSeconds: 3),
        kDefaultPixelsPerSecond,
      );
    });

    test('an empty project keeps the default', () {
      expect(
        minPixelsPerSecond(viewportWidth: 400, durationSeconds: 0),
        kDefaultPixelsPerSecond,
      );
    });

    test('a pinch scales the scale it started from, held inside the range', () {
      expect(zoomedPixelsPerSecond(start: 50, scale: 2, min: 10), 100);
      expect(zoomedPixelsPerSecond(start: 50, scale: 100, min: 10), kMaxPixelsPerSecond);
      expect(zoomedPixelsPerSecond(start: 50, scale: 0.01, min: 10), 10);
    });
  });

  group('the ruler', () {
    test('keeps labels at least the minimum apart at every zoom', () {
      for (final pps in [2.0, 10.0, 50.0, 120.0, 300.0, 600.0]) {
        final interval = rulerTickInterval(pps);
        expect(interval * pps, greaterThanOrEqualTo(kRulerMinLabelSpacingPx),
            reason: '$pps px/s');
      }
    });

    test('uses the finest step that fits', () {
      // At the default, labels every two seconds (100px apart).
      expect(rulerTickInterval(50), 2);
      // Zoomed in, sub-second steps.
      expect(rulerTickInterval(600), lessThan(1));
      // Zoomed out a long way, a minute or more.
      expect(rulerTickInterval(1), greaterThanOrEqualTo(60));
    });
  });
}
