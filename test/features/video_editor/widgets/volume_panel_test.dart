import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/volume_panel.dart';

/// The volume panel: what it reports, and what it reads.
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(height: 120, child: child)),
      );

  testWidgets('it reads as a percentage, like every other level in the editor',
      (tester) async {
    // Volume and Opacity are adjacent tools on the clip menu over the same
    // 0..1 model, and volume used to read 0-10 while opacity read 0-100%.
    // One scale per concept; a percentage is what an editor shows for a level.
    await tester.pumpWidget(host(
      VolumePanel(displayVolume: 0.5, onChanged: (_) {}),
    ));
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('5'), findsNothing, reason: 'the old 0-10 scale is gone');

    await tester.pumpWidget(host(
      VolumePanel(displayVolume: 1.0, onChanged: (_) {}),
    ));
    expect(find.text('100%'), findsOneWidget);

    await tester.pumpWidget(host(
      VolumePanel(displayVolume: 0.0, onChanged: (_) {}),
    ));
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('a drag reports its start exactly once', (tester) async {
    // **Device-relevant:** the video-overlay volume path wrote through
    // `updateVideoOverlay` on every slider frame, and that snapshots the whole
    // editor state for undo — so Undo walked a drag back a pixel at a time.
    // The panel has to offer a start callback for a caller to snapshot once,
    // the rule every other drag in this codebase follows.
    var starts = 0;
    var changes = 0;
    await tester.pumpWidget(host(
      VolumePanel(
        displayVolume: 0.5,
        onChangeStart: () => starts++,
        onChanged: (_) => changes++,
      ),
    ));

    final slider = find.byType(Slider);
    final centre = tester.getCenter(slider);
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(starts, 1, reason: 'one undo snapshot covers the whole drag');
    expect(changes, greaterThan(0), reason: 'the drag still writes live');
  });

  testWidgets('an empty message replaces the control', (tester) async {
    await tester.pumpWidget(host(
      VolumePanel(
        displayVolume: 0.5,
        onChanged: (_) {},
        emptyMessage: 'Nothing selected',
      ),
    ));
    expect(find.text('Nothing selected'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });
}
