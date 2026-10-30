import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/app_version.dart';
import 'package:slimshotai/screens/settings_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    // Past the groups' entrance.
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('General holds Clear Cache', (tester) async {
    await pump(tester);
    expect(find.text('Clear Cache'), findsOneWidget);
  });

  testWidgets('shows the version this build is', (tester) async {
    await pump(tester);
    expect(find.text('v$kAppVersion ($kAppBuildNumber)'), findsOneWidget);
  });

  // A developer's tool, not a user's: it brought onboarding back on the next
  // launch (the owner's call, 2026-10-30).
  testWidgets('there is no Reset Onboarding', (tester) async {
    await pump(tester);
    expect(find.text('Reset Onboarding'), findsNothing);
  });
}
