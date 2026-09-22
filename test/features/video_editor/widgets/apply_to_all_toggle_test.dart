import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/apply_to_all_toggle.dart';

/// The "apply to all clips" switch at the top of a tool sheet.
///
/// It used to be a two-line block with a Material [Switch] — around 70px of a
/// sheet capped at 45% of the screen, spent on a control the user glances at
/// once. It is now a label and a small check, which is the shape the rest of
/// this app already marks a choice with.
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 360, child: child)),
      );

  testWidgets('it is compact, and not a Material switch', (tester) async {
    await tester.pumpWidget(host(
      ApplyToAllToggle(
        value: false,
        onChanged: (_) {},
        subtitle: 'Only this clip',
      ),
    ));

    expect(find.byType(Switch), findsNothing);
    final height = tester.getSize(find.byType(ApplyToAllToggle)).height;
    expect(
      height,
      lessThan(56),
      reason: 'a glance-once control should not eat the sheet',
    );
  });

  testWidgets('the subtitle survives, because it says what the state does',
      (tester) async {
    // "Apply to all" alone does not tell a user what happens when it is off.
    await tester.pumpWidget(host(
      ApplyToAllToggle(
        value: false,
        onChanged: (_) {},
        subtitle: 'Only this clip',
      ),
    ));
    expect(find.text('Only this clip'), findsOneWidget);
  });

  testWidgets('tapping anywhere on the row flips it', (tester) async {
    // The whole row is the target, not a 20px box at its end.
    bool? got;
    await tester.pumpWidget(host(
      ApplyToAllToggle(
        value: false,
        onChanged: (v) => got = v,
        subtitle: 'Only this clip',
      ),
    ));

    await tester.tap(find.text('Apply to all clips'));
    expect(got, isTrue);
  });

  testWidgets('disabled, it neither reports nor invites a tap', (tester) async {
    // A single-clip project has nothing to apply "to all" of. Dimmed rather
    // than hidden, so the control does not appear and disappear.
    var taps = 0;
    await tester.pumpWidget(host(
      ApplyToAllToggle(
        value: false,
        enabled: false,
        onChanged: (_) => taps++,
        subtitle: 'Only this clip',
      ),
    ));

    await tester.tap(find.text('Apply to all clips'), warnIfMissed: false);
    expect(taps, 0);
  });
}
