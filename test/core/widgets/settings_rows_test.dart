import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/core/widgets/frosted_glass.dart';
import 'package:slimshotai/core/widgets/settings_rows.dart';

void main() {
  testWidgets('a settings group sets its rows on frosted glass', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsGroup(
            children: [
              SettingsItem(
                icon: LucideIcons.info,
                title: 'App Version',
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(FrostedGlass),
        matching: find.text('App Version'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('App Version'));
    expect(taps, 1);
  });
}
