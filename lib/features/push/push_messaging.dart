/// Whether this phone lets the app show notifications.
enum PushPermission {
  granted,
  denied,

  /// Android 13 and later, before the user has been asked.
  notAsked,

  /// Refused for good (Android 13 and later): no dialog will show again, so
  /// only the phone's settings can allow them.
  blocked,
}

/// A notification that arrived while the app was open. Android shows a
/// notification itself only while the app is in the background or closed.
class PushNotice {
  const PushNotice({required this.title, required this.body});

  final String title;
  final String body;
}

/// What the app needs from Firebase Cloud Messaging, so the rules around it
/// can be tested without a phone.
abstract class PushMessaging {
  Future<PushPermission> permission();

  /// Shows the system's dialog where one can still be shown.
  Future<PushPermission> requestPermission();

  /// This install's FCM token; null when Firebase has none to give.
  Future<String?> token();

  Stream<String> get tokenRefreshes;
  Stream<PushNotice> get foregroundNotices;
}
