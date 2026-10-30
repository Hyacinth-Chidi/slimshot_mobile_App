import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/app_version.dart';
import 'package:slimshotai/features/push/push_controller.dart';
import 'package:slimshotai/features/push/push_messaging.dart';
import 'package:slimshotai/features/push/push_providers.dart';
import 'package:slimshotai/screens/settings_screen.dart';

import '../support/app_lifecycle.dart';
import '../support/fake_push_messaging.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, [
    List<Override> overrides = const [],
  ]) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: SettingsScreen()),
      ),
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

  group('Notifications', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final toggle = find.byKey(const ValueKey('settings_notifications_switch'));

    (PushController, List<String?>) controllerWith(FakePushMessaging push) {
      final sent = <String?>[];
      return (
        PushController(
          messaging: push,
          sendToken: (token) async => sent.add(token),
          showNotice: (_) async {},
        ),
        sent,
      );
    }

    testWidgets('is not offered in a build without push', (tester) async {
      await pump(tester);
      expect(find.text('Notifications'), findsNothing);
    });

    testWidgets('is on by default; off tells the server to forget the phone',
        (tester) async {
      final (controller, sent) =
          controllerWith(FakePushMessaging(current: PushPermission.granted));
      await pump(tester, [pushControllerProvider.overrideWithValue(controller)]);
      expect(tester.widget<Switch>(toggle).value, isTrue);

      await tester.tap(find.text('Notifications'));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(sent, [null]);
    });

    // On is a promise only the phone can keep: turned off there, the switch
    // says so here.
    testWidgets('reads off where the phone has turned them off',
        (tester) async {
      final (controller, _) =
          controllerWith(FakePushMessaging(current: PushPermission.denied));
      await pump(tester, [pushControllerProvider.overrideWithValue(controller)]);
      expect(tester.widget<Switch>(toggle).value, isFalse);
    });

    testWidgets('refused by the phone, it opens the phone\'s settings',
        (tester) async {
      final (controller, sent) = controllerWith(
        FakePushMessaging(
          current: PushPermission.denied,
          answer: PushPermission.denied,
        ),
      );
      var opened = 0;
      await pump(tester, [
        pushControllerProvider.overrideWithValue(controller),
        openAppSettingsProvider.overrideWithValue(() async => opened++),
      ]);
      await tester.tap(find.text('Notifications'));
      await tester.pump();
      await tester.pump();
      expect(opened, 1);
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(sent, isEmpty);
      // Past the toast.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('allowed in the phone settings, it reads on coming back',
        (tester) async {
      final push = FakePushMessaging(
        current: PushPermission.blocked,
        answer: PushPermission.blocked,
      );
      final (controller, sent) = controllerWith(push);
      await pump(tester, [
        pushControllerProvider.overrideWithValue(controller),
        openAppSettingsProvider.overrideWithValue(() async {}),
      ]);
      await tester.tap(find.text('Notifications'));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<Switch>(toggle).value, isFalse);

      // Away to the phone's settings, allowed there, and back.
      await sendAppLifecycle(tester, AppLifecycleState.paused);
      push.current = PushPermission.granted;
      await sendAppLifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(sent, ['fcm-1']);
      await tester.pump(const Duration(seconds: 5)); // past the toast
    });

    testWidgets('no in the dialog just now: off, and nothing opened',
        (tester) async {
      final (controller, _) = controllerWith(
        FakePushMessaging(answer: PushPermission.denied),
      );
      var opened = 0;
      await pump(tester, [
        pushControllerProvider.overrideWithValue(controller),
        openAppSettingsProvider.overrideWithValue(() async => opened++),
      ]);
      await tester.tap(find.text('Notifications'));
      await tester.pump();
      await tester.pump();
      expect(opened, 0);
      expect(tester.widget<Switch>(toggle).value, isFalse);
    });
  });
}
