import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../account/providers/account_providers.dart';
import 'firebase_push_messaging.dart';
import 'native_notifications.dart';
import 'push_controller.dart';
import 'push_messaging.dart';

/// Whether Firebase has started. `main` starts it in the background and
/// sets this when it is ready — never holding the app for it — so push comes
/// on whenever Firebase does. False until then, and in every test that does
/// not say otherwise.
final pushAvailableProvider = StateProvider<bool>((ref) => false);

final pushMessagingProvider =
    Provider<PushMessaging>((ref) => FirebasePushMessaging());

final showPushNoticeProvider = Provider<Future<void> Function(PushNotice)>(
  (ref) => const NativeNotifications().show,
);

/// The phone's settings page for this app: where notifications refused for
/// good can be allowed again.
final openAppSettingsProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await openAppSettings();
  },
);

/// Push notifications, or null in a build without Firebase or without the
/// server that keeps the tokens — not offered before they can work.
final pushControllerProvider = Provider<PushController?>((ref) {
  if (!ref.watch(pushAvailableProvider) || !ref.watch(accountFeatureProvider)) {
    return null;
  }
  final api = ref.watch(accountApiProvider);
  final controller = PushController(
    messaging: ref.watch(pushMessagingProvider),
    sendToken: (token) => api.sendWithDevice(
      '/push/token',
      {'token': token},
      method: 'PUT',
    ),
    showNotice: ref.watch(showPushNoticeProvider),
  );
  // The server ties an install's token to the account signed in on it, so a
  // sign-in sends the token again.
  ref.listen<bool>(
    accountProvider.select((account) => account.isSignedIn),
    (was, now) {
      if (now && !(was ?? false)) unawaited(controller.onSignedIn());
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
});
