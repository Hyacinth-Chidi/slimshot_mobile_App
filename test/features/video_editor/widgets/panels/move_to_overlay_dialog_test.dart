import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/move_to_overlay_dialog.dart';

/// Asked only when the move would leave something behind: one line naming it,
/// Cancel and Move.
void main() {
  Future<Future<bool>> open(WidgetTester tester, List<String> losses) async {
    late Future<bool> answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => answer = confirmMoveToOverlay(context, losses),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('names what will not carry over', (tester) async {
    await open(tester, ['Filter', 'Speed curve']);
    expect(find.text("Filter and speed curve won't carry over."), findsOneWidget);
  });

  testWidgets('Move answers yes', (tester) async {
    final answer = await open(tester, ['Filter']);
    await tester.tap(find.byKey(const Key('move_to_overlay_confirm')));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });

  testWidgets('Cancel answers no', (tester) async {
    final answer = await open(tester, ['Filter']);
    await tester.tap(find.byKey(const Key('move_to_overlay_cancel')));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });
}
