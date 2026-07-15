// Basic smoke test for SlimShotAI

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimshotai/main.dart';

void main() {
  testWidgets('App starts without crashing', (WidgetTester tester) async {
    initializeAppRouter('/onboarding');

    await tester.pumpWidget(
      const ProviderScope(child: SlimShotApp(enableShareIntents: false)),
    );

    expect(find.byType(SlimShotApp), findsOneWidget);
  });
}
