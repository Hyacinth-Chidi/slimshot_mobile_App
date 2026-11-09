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

  // The owner's pick of three mockups (2026-11-09): the question and its two
  // buttons and nothing else — no icon stacked over one short line, the same
  // space on every side. It was narrow, 24 over the question and 16 under
  // the buttons, which read tall and bottom-heavy.
  group('balanced', () {
    Future<void> phone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await ask(tester);
    }

    final surface = find.byKey(kQuestionDialogKey);

    testWidgets('the same space on every side', (tester) async {
      await phone(tester);
      final box = tester.getRect(surface);
      final question = tester.getRect(find.text('Discard this video?'));
      final cancel = tester.getRect(find.byKey(const Key('discard_cancel')));
      final discard = tester.getRect(find.byKey(const Key('discard_confirm')));
      expect(question.top - box.top, moreOrLessEquals(kQuestionDialogPadding, epsilon: 0.5));
      expect(box.bottom - cancel.bottom, moreOrLessEquals(kQuestionDialogPadding, epsilon: 0.5));
      expect(cancel.left - box.left, moreOrLessEquals(kQuestionDialogPadding, epsilon: 0.5));
      expect(box.right - discard.right, moreOrLessEquals(kQuestionDialogPadding, epsilon: 0.5));
      expect(question.center.dx, moreOrLessEquals(box.center.dx, epsilon: 0.5));
    });

    testWidgets('no icon over the question', (tester) async {
      await phone(tester);
      expect(find.descendant(of: surface, matching: find.byType(Icon)), findsNothing);
    });

    testWidgets('on a 360dp phone it is 296 wide, centred', (tester) async {
      await phone(tester);
      final box = tester.getRect(surface);
      expect(box.width, moreOrLessEquals(296, epsilon: 0.5));
      expect(box.center.dx, moreOrLessEquals(180, epsilon: 0.5));
    });

    testWidgets('it fits a 320dp phone at 1.3× text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await ask(tester);
      expect(tester.takeException(), isNull);
    });
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
