import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/utils/toast_utils.dart';

/// The toast is a compact centred pill, not a banner.
///
/// Device-reported: the old toast was a full-width card pinned to the top of
/// the screen — deleting a draft raised a "Success!" banner over the drafts
/// screen's own action buttons, and the user had to wait ~4 seconds for their
/// UI back. These tests pin the properties that fixed that: compact, centred,
/// title-free, tap-dismissable, and one at a time.
void main() {
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );
    return tester.element(find.byType(SizedBox));
  }

  testWidgets('shows the message and no generic title', (tester) async {
    final context = await pumpHost(tester);
    ToastUtils.show(context, 'Draft deleted');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Draft deleted'), findsOneWidget);
    // "Success!" above "Draft deleted" is the same fact twice — the echo rule
    // that already removed sheet titles and the apply-to-all subtitle.
    expect(find.text('Success!'), findsNothing);
    expect(find.text('Error!'), findsNothing);
    expect(find.text('Warning!'), findsNothing);
  });

  testWidgets('is a compact pill centred on screen, not a full-width banner',
      (tester) async {
    final context = await pumpHost(tester);
    ToastUtils.show(context, 'Draft deleted');
    await tester.pump(const Duration(milliseconds: 300));

    final screen = tester.getSize(find.byType(MaterialApp));
    final pill = find.byType(ToastPill);
    final size = tester.getSize(pill);
    final centre = tester.getCenter(pill);

    // Compact: sized to its text, never edge to edge — a full-width card is
    // what covered the drafts screen's action buttons.
    expect(size.width, lessThan(screen.width * 0.9));
    // Centred both ways: over content, never over the top app bar's actions
    // or the editor's bottom toolbar.
    expect(centre.dx, closeTo(screen.width / 2, 1.0));
    expect(centre.dy, closeTo(screen.height / 2, screen.height * 0.15));
  });

  testWidgets('tap dismisses immediately', (tester) async {
    final context = await pumpHost(tester);
    ToastUtils.show(context, 'Draft deleted');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(ToastPill));
    await tester.pump();
    expect(find.text('Draft deleted'), findsNothing);
  });

  testWidgets('a second toast replaces the first, never stacks',
      (tester) async {
    final context = await pumpHost(tester);
    ToastUtils.show(context, 'first');
    await tester.pump(const Duration(milliseconds: 300));
    ToastUtils.show(context, 'second');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    expect(find.byType(ToastPill), findsOneWidget);
  });

  testWidgets('dismisses itself after its hold', (tester) async {
    final context = await pumpHost(tester);
    ToastUtils.show(context, 'Draft deleted');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Draft deleted'), findsOneWidget);

    // Generously past enter + hold for any severity; the hold timer fires
    // during this pump and starts the exit, which needs frames of its own.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Draft deleted'), findsNothing);
  });

  testWidgets('error and warning carry their own icon and severity colour',
      (tester) async {
    final context = await pumpHost(tester);

    ToastUtils.show(context, 'export failed', isError: true);
    await tester.pump(const Duration(milliseconds: 300));
    final errorIcon = tester.widget<Icon>(
      find.descendant(of: find.byType(ToastPill), matching: find.byType(Icon)),
    );

    ToastUtils.show(context, 'lane unavailable', isWarning: true);
    await tester.pump(const Duration(milliseconds: 300));
    final warningIcon = tester.widget<Icon>(
      find.descendant(of: find.byType(ToastPill), matching: find.byType(Icon)),
    );

    ToastUtils.show(context, 'saved');
    await tester.pump(const Duration(milliseconds: 300));
    final successIcon = tester.widget<Icon>(
      find.descendant(of: find.byType(ToastPill), matching: find.byType(Icon)),
    );

    // Three severities, three glyphs, three colours — the icon is what says
    // error/warning/success now that the shouting title is gone.
    expect(errorIcon.icon, isNot(warningIcon.icon));
    expect(warningIcon.icon, isNot(successIcon.icon));
    expect(errorIcon.color, isNot(successIcon.color));
  });

  test('ToastUtils is the one toast implementation in lib/', () {
    // "Centralised" is the user's own requirement: one toast, not toast code
    // per file. The settings screen carried a private `_showSnackBar` wrapper
    // whose icon and colour parameters were silently ignored — this scan is
    // what keeps the next one from appearing. Same pattern as the
    // `showEditorSheet` stray-scan for sheets.
    final strays = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final text = file.readAsStringSync();
      if (text.contains('SnackBar(') ||
          text.contains('ScaffoldMessenger') ||
          text.contains('showSnackBar')) {
        strays.add(file.path);
      }
    }
    expect(
      strays,
      isEmpty,
      reason: 'user feedback goes through ToastUtils.show, nothing else',
    );
  });

  testWidgets('taps outside the pill pass through to the screen below',
      (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TextButton(
              onPressed: () => pressed = true,
              child: const Text('under'),
            ),
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(Scaffold));
    ToastUtils.show(context, 'Draft deleted');
    await tester.pump(const Duration(milliseconds: 300));

    // The whole point: a toast must never make the user wait to use their UI.
    await tester.tap(find.text('under'));
    expect(pressed, isTrue);
  });
}
