import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/background_panel.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/crop_panel.dart';

/// A tool panel takes the height its content needs, not a fixed 160.
///
/// Device-reported: the crop panel opened as a 160px box holding one row of
/// ratio chips, and the empty rest read as a gap between the panel and the
/// timeline. The panel now sizes to its content, which means every panel body
/// has to lay out under an **unbounded** height — a horizontal list or an
/// `Expanded` inside one throws the moment the fixed box is gone. These pump
/// each body the way the panel now does and pin that it neither throws nor
/// sprawls.
void main() {
  Future<Size> pumpUnbounded(WidgetTester tester, Widget body,
      {VideoEditorNotifier? notifier}) async {
    final child = MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 360, child: KeyedSubtree(key: const Key('body'), child: body)),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      notifier == null
          ? child
          : ProviderScope(
              overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
              child: child,
            ),
    );
    expect(tester.takeException(), isNull);
    return tester.getSize(find.byKey(const Key('body')));
  }

  testWidgets('the crop panel sizes itself to one row of chips',
      (tester) async {
    final size = await pumpUnbounded(
      tester,
      CropPanel(
        selectedRatio: EditorCropRatio.ratio9x16,
        onRatioSelected: (_) {},
      ),
    );
    expect(size.height, greaterThan(40));
    expect(size.height, lessThan(80));
  });

  testWidgets('the background panel sizes itself to its swatches',
      (tester) async {
    final notifier = VideoEditorNotifier(VideoEditorService())
      ..state = const VideoEditorState(
        backgroundType: EditorBackgroundType.color,
      );
    final size = await pumpUnbounded(
      tester,
      BackgroundPanel(onClose: () {}),
      notifier: notifier,
    );
    // The switch row plus two rows of 32px swatches, and no more.
    expect(size.height, greaterThan(60));
    expect(size.height, lessThan(160));
  });
}
