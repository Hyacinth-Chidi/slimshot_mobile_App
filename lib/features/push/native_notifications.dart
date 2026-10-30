import 'package:flutter/services.dart';

import 'push_messaging.dart';

/// Draws a notification that arrived while the app was open — Android draws
/// one itself only while the app is in the background or closed — in the
/// same channel, with the same icon (`NotificationsChannel.kt`).
class NativeNotifications {
  const NativeNotifications();

  /// Pinned to the Kotlin side's by `push_android_test.dart`.
  static const String channelName = 'slimshot_ai/notifications';

  static const MethodChannel _channel = MethodChannel(channelName);

  Future<void> show(PushNotice notice) => _channel.invokeMethod<void>(
        'show',
        {'title': notice.title, 'body': notice.body},
      );
}
