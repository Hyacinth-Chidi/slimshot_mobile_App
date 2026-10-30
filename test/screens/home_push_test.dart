import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/features/push/push_controller.dart';
import 'package:slimshotai/features/push/push_messaging.dart';
import 'package:slimshotai/features/push/push_providers.dart';
import 'package:slimshotai/screens/home_screen.dart';

import '../support/fake_push_messaging.dart';

/// Push starts from Home: the first visit after onboarding is where the app
/// asks for permission, once, and every visit sends the token.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(WidgetTester tester, List<Override> overrides) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    // Home loops animations, so it never settles by itself.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Home asks for notifications and sends the token',
      (tester) async {
    final push = FakePushMessaging();
    final sent = <String?>[];
    await pumpHome(tester, [
      pushControllerProvider.overrideWithValue(
        PushController(
          messaging: push,
          sendToken: (token) async => sent.add(token),
          showNotice: (_) async {},
        ),
      ),
    ]);
    expect(push.requests, 1);
    expect(push.current, PushPermission.granted);
    expect(sent, ['fcm-1']);
  });

  testWidgets('a build without push opens Home as before', (tester) async {
    await pumpHome(tester, const []);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
