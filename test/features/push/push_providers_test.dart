import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/push/firebase_push_messaging.dart';
import 'package:slimshotai/features/push/native_notifications.dart';
import 'package:slimshotai/features/push/push_messaging.dart';
import 'package:slimshotai/features/push/push_providers.dart';

import '../../support/account_harness.dart';
import '../../support/fake_push_messaging.dart';
import '../../support/fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  FakeServer serverAcceptingTokens() =>
      FakeServer()..on('PUT', '/push/token', (_) => envelope({'registered': true}));

  ProviderContainer containerWith(
    FakeServer server,
    FakePushMessaging push, {
    List<PushNotice>? shown,
  }) {
    final container = ProviderContainer(
      overrides: [
        ...accountOverrides(server),
        pushAvailableProvider.overrideWithValue(true),
        pushMessagingProvider.overrideWithValue(push),
        showPushNoticeProvider.overrideWithValue((n) async => shown?.add(n)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('there is no push', () {
    test('in a build without Firebase', () {
      final container = ProviderContainer(
        overrides: [accountFeatureProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      expect(container.read(pushControllerProvider), isNull);
    });

    test('in a build without the server, which holds the tokens', () {
      final container = ProviderContainer(
        overrides: [
          accountFeatureProvider.overrideWithValue(false),
          pushAvailableProvider.overrideWithValue(true),
          pushMessagingProvider.overrideWithValue(FakePushMessaging()),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(pushControllerProvider), isNull);
    });
  });

  test('the token goes to PUT /push/token with the install', () async {
    final server = serverAcceptingTokens();
    final container = containerWith(
      server,
      FakePushMessaging(current: PushPermission.granted),
    );
    await container.read(pushControllerProvider)!.start();
    expect(server.lastBody('PUT', '/push/token'), {
      'token': 'fcm-1',
      'deviceToken': 'dev-1',
    });
  });

  test('switched off, the server is told to forget it', () async {
    final server = serverAcceptingTokens();
    final container = containerWith(
      server,
      FakePushMessaging(current: PushPermission.granted),
    );
    await container.read(pushControllerProvider)!.setEnabled(false);
    expect(server.lastBody('PUT', '/push/token'), {
      'token': null,
      'deviceToken': 'dev-1',
    });
  });

  // The server ties an install's token to the account it is signed in to.
  test('a sign-in sends the token again', () async {
    final server = serverAcceptingTokens();
    final container = containerWith(
      server,
      FakePushMessaging(current: PushPermission.granted),
    );
    await container.read(pushControllerProvider)!.start();
    expect(server.to('PUT', '/push/token'), hasLength(1));

    await container.read(accountProvider.notifier).completeSignIn(
          SignInResult(
            tokens: const SessionTokens(accessToken: 'a', refreshToken: 'r'),
            user: AccountUser.fromJson(userJson()),
          ),
        );
    await pumpEventQueue();
    expect(server.to('PUT', '/push/token'), hasLength(2));
  });

  test('a notification arriving while the app is open is drawn', () async {
    final push = FakePushMessaging(current: PushPermission.granted);
    final shown = <PushNotice>[];
    final container = containerWith(serverAcceptingTokens(), push, shown: shown);
    await container.read(pushControllerProvider)!.start();
    push.notices.add(const PushNotice(title: 'New effects', body: 'Try them'));
    await pumpEventQueue();
    expect(shown.single.title, 'New effects');
  });

  // Android 13+ tells never asked, refused once and refused for good
  // apart; provisional is iOS's.
  test('Firebase\'s answers read as the app\'s', () {
    expect(pushPermissionOf(AuthorizationStatus.authorized), PushPermission.granted);
    expect(pushPermissionOf(AuthorizationStatus.provisional), PushPermission.granted);
    expect(pushPermissionOf(AuthorizationStatus.denied), PushPermission.denied);
    expect(pushPermissionOf(AuthorizationStatus.deniedPermanently),
        PushPermission.blocked);
    expect(pushPermissionOf(AuthorizationStatus.notDetermined), PushPermission.notAsked);
  });

  test('the app draws an open-app notification on its own channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(NativeNotifications.channelName),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(NativeNotifications.channelName),
        null,
      ),
    );
    await const NativeNotifications()
        .show(const PushNotice(title: 'T', body: 'B'));
    expect(calls.single.method, 'show');
    expect(calls.single.arguments, {'title': 'T', 'body': 'B'});
  });
}
