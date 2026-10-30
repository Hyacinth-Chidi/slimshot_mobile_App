import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_messaging.dart';

/// Starts Firebase where this build carries its configuration — the
/// `google-services.json` the Firebase console gives, which the Gradle build
/// applies only when it is there. False without it, and on anything that
/// goes wrong: the app then runs without push.
Future<bool> startFirebase() async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 5));
    return true;
  } catch (error) {
    debugPrint('Push: Firebase not started: $error');
    return false;
  }
}

/// Firebase's answer as the app's. Android 13+ tells never asked, refused
/// once and refused for good apart; Android 12 and older answer only allowed
/// or denied, so the app keys its one ask to a flag of its own
/// (`PushController`).
PushPermission pushPermissionOf(AuthorizationStatus status) => switch (status) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional =>
        PushPermission.granted,
      AuthorizationStatus.denied => PushPermission.denied,
      AuthorizationStatus.deniedPermanently => PushPermission.blocked,
      AuthorizationStatus.notDetermined => PushPermission.notAsked,
    };

/// Firebase Cloud Messaging. Plugin code, untested by design: it needs a
/// phone with Google Play services.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging([FirebaseMessaging? messaging])
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Future<PushPermission> permission() async => pushPermissionOf(
        (await _messaging.getNotificationSettings()).authorizationStatus,
      );

  @override
  Future<PushPermission> requestPermission() async =>
      pushPermissionOf((await _messaging.requestPermission()).authorizationStatus);

  // The registration token, deliberately, not `register()`'s installation
  // ID: the server sends through the Admin SDK to registration tokens
  // (slimshot_server docs/app-push-api.md), and an installation ID is the
  // target of a newer direct-send API it does not use.
  @override
  // ignore: deprecated_member_use
  Future<String?> token() => _messaging.getToken();

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushNotice> get foregroundNotices => FirebaseMessaging.onMessage
      .where((message) => message.notification != null)
      .map(
        (message) => PushNotice(
          title: message.notification!.title ?? '',
          body: message.notification!.body ?? '',
        ),
      );
}
