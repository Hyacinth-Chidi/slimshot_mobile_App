import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';

/// Every sheet in the editor opens over a **clear** canvas.
///
/// Device-reported: with a sheet up, the rest of the screen dimmed, so the
/// preview the user was choosing *for* — a curve, a transition, a filter — was
/// muddied exactly while they compared choices. Flutter's default barrier is
/// `black54`; the editor's is nothing. One opener carries that decision so a
/// new sheet cannot quietly bring the tint back.
void main() {
  testWidgets('a sheet opens with no tint over the editor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEditorSheet<void>(
                context,
                builder: (_) => const SizedBox(
                  key: Key('sheet_body'),
                  height: 200,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sheet_body')), findsOneWidget);
    // A coloured barrier is an `AnimatedModalBarrier`; a clear one is a plain
    // `ModalBarrier` with no colour. Both are asserted, so a future Flutter
    // that draws the plain one with a colour is caught too.
    expect(find.byType(AnimatedModalBarrier), findsNothing);
    for (final barrier
        in tester.widgetList<ModalBarrier>(find.byType(ModalBarrier))) {
      final colour = barrier.color;
      expect(colour == null || colour.a == 0, isTrue,
          reason: 'barrier is tinted: $colour');
    }
  });

  testWidgets('the sheet still dismisses on a tap outside', (tester) async {
    // Clear is not the same as absent: the barrier must still be there to
    // catch the tap that closes the sheet.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                onPressed: () => showEditorSheet<void>(
                  context,
                  builder: (_) => const SizedBox(
                    key: Key('sheet_body'),
                    height: 200,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sheet_body')), findsOneWidget);

    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sheet_body')), findsNothing);
  });

  test('every sheet in the editor opens through the one opener', () {
    // A source scan, because the rule is a UX decision the compiler cannot
    // hold: a direct `showModalBottomSheet` anywhere in the editor gets
    // Flutter's tinted barrier back without anyone choosing it.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalised = entity.path.replaceAll('\\', '/');
      if (normalised.endsWith('/widgets/panels/editor_sheet.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('showModalBottomSheet')) offenders.add(normalised);
    }
    expect(offenders, isEmpty,
        reason: 'open sheets with showEditorSheet, not showModalBottomSheet');
  });
}
