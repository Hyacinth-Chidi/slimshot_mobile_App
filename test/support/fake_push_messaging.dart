import 'dart:async';

import 'package:slimshotai/features/push/push_messaging.dart';

/// Firebase Messaging as a test scripts it: what the phone answers when
/// asked for permission, the token it hands out, and the two streams.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({
    this.current = PushPermission.notAsked,
    this.answer = PushPermission.granted,
    this.currentToken = 'fcm-1',
  });

  /// What [permission] reports until a request changes it.
  PushPermission current;

  /// What the user picks when [requestPermission] shows the dialog.
  PushPermission answer;

  String? currentToken;
  int requests = 0;

  final StreamController<String> refreshes = StreamController.broadcast();
  final StreamController<PushNotice> notices = StreamController.broadcast();

  @override
  Future<PushPermission> permission() async => current;

  @override
  Future<PushPermission> requestPermission() async {
    requests++;
    return current = answer;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<PushNotice> get foregroundNotices => notices.stream;
}
