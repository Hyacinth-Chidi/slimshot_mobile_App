import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/core/widgets/discard_dialog.dart';

/// Leaving a new project asks "Save as draft?" (the owner's call,
/// 2026-11-09): Save keeps it, Don't save throws it away, and anything else
/// — a tap outside, Back — stays in the editor.
void main() {
  Future<Future<DraftChoice?>> open(WidgetTester tester) async {
    late Future<DraftChoice?> answer;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => answer = askSaveDraft(context),
              child: const Text('leave'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('it asks "Save as draft?" with Save and Don\'t save', (tester) async {
    await open(tester);
    expect(kSaveDraftQuestion, 'Save as draft?');
    expect(find.text(kSaveDraftQuestion), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text("Don't save"), findsOneWidget);
  });

  testWidgets('Save answers save', (tester) async {
    final answer = await open(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await answer, DraftChoice.save);
    expect(find.text(kSaveDraftQuestion), findsNothing);
  });

  testWidgets("Don't save answers discard", (tester) async {
    final answer = await open(tester);
    await tester.tap(find.text("Don't save"));
    await tester.pumpAndSettle();
    expect(await answer, DraftChoice.discard);
  });

  testWidgets('a tap outside stays: no answer', (tester) async {
    final answer = await open(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text(kSaveDraftQuestion), findsNothing);
    expect(await answer, isNull);
  });

  testWidgets('Back stays: no answer', (tester) async {
    final answer = await open(tester);
    tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(find.text(kSaveDraftQuestion), findsNothing);
    expect(await answer, isNull);
  });

  // White on purple, never dark: Save is the way out most people take.
  testWidgets('Save is white on purple', (tester) async {
    await open(tester);
    final save = tester.widget<TextButton>(
        find.ancestor(of: find.text('Save'), matching: find.byType(TextButton)));
    expect(save.style!.backgroundColor!.resolve({}), AppColors.primaryStart);
    expect(tester.widget<Text>(find.text('Save')).style!.color, Colors.white);
  });
}
