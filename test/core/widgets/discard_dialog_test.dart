import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/widgets/discard_dialog.dart';

/// Asked before a result nobody saved or shared is thrown away — the owner's
/// call: a long compression or export lost to one tap is painful.
void main() {
  test('it names what would be lost', () {
    expect(discardQuestion(isVideo: true, count: 1), 'Discard this video?');
    expect(discardQuestion(isVideo: true, count: 3), 'Discard these 3 videos?');
    expect(discardQuestion(isVideo: false, count: 1), 'Discard this photo?');
    expect(discardQuestion(isVideo: false, count: 5), 'Discard these 5 photos?');
  });

  Future<List<bool>> ask(WidgetTester tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async =>
                answers.add(await confirmDiscard(context, isVideo: true, count: 1)),
            child: const Text('leave'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    return answers;
  }

  testWidgets('Discard answers yes', (tester) async {
    final answers = await ask(tester);
    expect(find.text('Discard this video?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discard_confirm')));
    await tester.pumpAndSettle();
    expect(answers, [true]);
  });

  testWidgets('Cancel, or a tap outside, answers no', (tester) async {
    final answers = await ask(tester);
    await tester.tap(find.byKey(const Key('discard_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(answers, [false, false]);
  });

  // Captions made from Home and never exported: the credits were spent on
  // them, so they are asked about, never lost to a stray Back.
  testWidgets('the captions question: Discard is yes, Cancel stays',
      (tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async =>
                answers.add(await confirmDiscardCaptions(context)),
            child: const Text('leave'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    expect(find.text(kDiscardCaptionsQuestion), findsOneWidget);
    expect(kDiscardCaptionsQuestion, 'Discard these captions?');
    await tester.tap(find.byKey(const Key('discard_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard_confirm')));
    await tester.pumpAndSettle();
    expect(answers, [false, true]);
  });
}
