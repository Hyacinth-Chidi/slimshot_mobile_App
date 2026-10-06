import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/widgets/colour_field_backdrop.dart';
import 'package:slimshotai/features/account/widgets/account_sheet_frame.dart';

void main() {
  testWidgets('an account sheet sits on the home screen\'s light',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AccountSheetFrame(children: [Text('Sign in')]),
      ),
    ));

    final backdrop = find.descendant(
      of: find.byType(AccountSheetFrame),
      matching: find.byType(ColourFieldBackdrop),
    );
    expect(backdrop, findsOneWidget);
    expect(
      tester.widget<ColourFieldBackdrop>(backdrop).glows,
      AccountSheetFrame.glows,
    );
    // The light fills the sheet, not just the space behind its words.
    final sheet = find.descendant(
      of: find.byType(AccountSheetFrame),
      matching: find.byType(ClipRRect),
    );
    expect(tester.getSize(backdrop), tester.getSize(sheet));
    expect(find.text('Sign in'), findsOneWidget);
  });

  test("the sheet's light is as restrained as the home screen's", () {
    for (final g in AccountSheetFrame.glows) {
      expect(g.opacity, lessThanOrEqualTo(0.30), reason: '${g.color}');
    }
  });
}
