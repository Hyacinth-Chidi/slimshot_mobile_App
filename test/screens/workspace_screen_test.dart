import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/screens/workspace_screen.dart';

void main() {
  // History is gone (2026-10-28): its entries pointed at temporary files the
  // launch cleanup had already deleted, so most could not be saved or shown.
  testWidgets('Workspace has no History button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: WorkspaceScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.byIcon(LucideIcons.history), findsNothing);
  });
}
