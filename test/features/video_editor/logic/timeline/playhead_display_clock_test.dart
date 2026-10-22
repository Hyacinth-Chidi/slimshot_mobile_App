import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/playhead_display_clock.dart';

/// The playhead as drawn while the engine plays.
///
/// The engine reports its position about thirty times a second, and the
/// playhead moved only when a report landed: a step every other frame, a
/// third of a frame of video at a time, that at a close zoom is ~20 px.
/// Between reports it is now carried on at the rate time passes — only while
/// the engine says its picture is moving, never past where a report could
/// still be on its way, and never backwards for a report that lands late.
void main() {
  Duration ms(int n) => Duration(milliseconds: n);

  test('between reports it moves at the rate time passes', () {
    final clock = PlayheadDisplayClock()
      ..report(2.0, advancing: true, at: ms(1000));
    expect(clock.positionAt(ms(1000)), 2.0);
    expect(clock.positionAt(ms(1016)), closeTo(2.016, 1e-9));
    expect(clock.positionAt(ms(1032)), closeTo(2.032, 1e-9));
  });

  test('a stalled picture holds the playhead exactly where the engine is', () {
    final clock = PlayheadDisplayClock()
      ..report(2.0, advancing: true, at: ms(1000))
      ..report(2.03, advancing: false, at: ms(1032));
    expect(clock.positionAt(ms(1032)), 2.03);
    expect(clock.positionAt(ms(1500)), 2.03);
  });

  test('with no report for a while it stops rather than run on', () {
    final clock = PlayheadDisplayClock()
      ..report(2.0, advancing: true, at: ms(1000));
    const limit = 2.0 + kPlayheadMaxExtrapolationSeconds;
    expect(clock.positionAt(ms(1000 + 300)), closeTo(limit, 1e-9));
    expect(clock.positionAt(ms(1000 + 900)), closeTo(limit, 1e-9));
  });

  test('a report a little behind what is drawn holds it, never steps back', () {
    final clock = PlayheadDisplayClock()
      ..report(2.0, advancing: true, at: ms(1000));
    expect(clock.positionAt(ms(1040)), closeTo(2.040, 1e-9));

    // Landed late: the engine was at 2.030 when it sent this.
    clock.report(2.030, advancing: true, at: ms(1040));
    expect(clock.positionAt(ms(1040)), closeTo(2.040, 1e-9));
    expect(clock.positionAt(ms(1048)), closeTo(2.040, 1e-9));
    expect(clock.positionAt(ms(1056)), closeTo(2.046, 1e-9));
  });

  test('a report far behind is a jump, and is drawn', () {
    final clock = PlayheadDisplayClock()
      ..report(5.0, advancing: true, at: ms(1000));
    expect(clock.positionAt(ms(1050)), closeTo(5.05, 1e-9));
    clock.report(1.0, advancing: true, at: ms(1060));
    expect(clock.positionAt(ms(1060)), 1.0);
  });

  test('never past the end it is given', () {
    final clock = PlayheadDisplayClock()
      ..report(9.98, advancing: true, at: ms(1000));
    expect(clock.positionAt(ms(1050), end: 10.0), 10.0);
  });

  test('placed, it is exactly there and still', () {
    final clock = PlayheadDisplayClock()
      ..report(5.0, advancing: true, at: ms(1000))
      ..place(3.0);
    expect(clock.positionAt(ms(1000)), 3.0);
    expect(clock.positionAt(ms(1080)), 3.0);
  });
}
