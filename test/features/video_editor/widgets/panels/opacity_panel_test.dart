import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/opacity_panel.dart';

/// The opacity slider reports the start of a drag.
///
/// A clip's opacity writes live through the edit rule on every frame of the
/// drag, and a drag is one undo step — so the caller needs one signal at the
/// start to take its snapshot, the same shape the transform rulers have. The
/// overlay path ignores it.
void main() {
  testWidgets('a drag reports its start once, then its values', (tester) async {
    var starts = 0;
    final values = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpacityPanel(
            opacity: 1.0,
            onChangeStart: () => starts++,
            onChanged: values.add,
          ),
        ),
      ),
    );

    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(-80, 0));
    await tester.pump();

    expect(starts, 1);
    expect(values, isNotEmpty);
    expect(values.last, lessThan(1.0));
  });
}
