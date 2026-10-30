import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_messaging.dart';

/// What turning the Settings switch did. [off] also answers a no in the
/// dialog just now; [blocked]: no dialog could be shown, so notifications can
/// only be allowed in the phone's own settings.
enum PushSwitch { on, off, blocked }

/// The Settings switch, on until the user turns it off.
const String kPushEnabledKey = 'push_enabled';

/// Whether the app has asked for permission by itself: it does so once.
const String kPushAskedKey = 'push_permission_asked';

/// Push notifications, as the server's `PUT /push/token` asks for them: the
/// install's FCM token sent on every start once notifications are allowed,
/// again whenever Firebase replaces it and after sign-in, and cleared
/// (`null`) when the user switches notifications off. The app asks for
/// permission by itself once — the first start after onboarding — and is on
/// by default; on Android 12 and older nothing is asked at all.
///
/// Nothing here throws: a phone without Google Play services, or a send that
/// fails, costs the notifications and nothing else.
class PushController {
  PushController({
    required PushMessaging messaging,
    required Future<void> Function(String? token) sendToken,
    required Future<void> Function(PushNotice notice) showNotice,
  })  : _messaging = messaging,
        _sendToken = sendToken,
        _showNotice = showNotice;

  final PushMessaging _messaging;
  final Future<void> Function(String? token) _sendToken;
  final Future<void> Function(PushNotice notice) _showNotice;

  StreamSubscription<String>? _refreshes;
  StreamSubscription<PushNotice>? _notices;

  /// Once per launch, from Home.
  Future<void> start() => _guard(() async {
        _listen();
        final prefs = await SharedPreferences.getInstance();
        if (!_enabledIn(prefs)) {
          // Again on every start: a switch-off sent with no connection
          // would leave the server sending under a switch that says off.
          await _send(null);
          return;
        }
        var permission = await _messaging.permission();
        // Not "notAsked" alone: Android 12 and older, or a permission another
        // plugin asked for, can read denied before this app ever asked, so
        // the one ask is keyed to our own flag.
        if (permission != PushPermission.granted &&
            !(prefs.getBool(kPushAskedKey) ?? false)) {
          await prefs.setBool(kPushAskedKey, true);
          permission = await _messaging.requestPermission();
        }
        if (permission == PushPermission.granted) await _sendCurrent();
      });

  Future<bool> isEnabled() async =>
      _enabledIn(await SharedPreferences.getInstance());

  /// What the Settings switch shows: switched on, and allowed by the phone —
  /// turned off in the phone's settings, nothing can arrive, whatever the
  /// app's own switch says.
  Future<bool> isOn() async {
    try {
      return await _allowed();
    } catch (error) {
      debugPrint('Push: $error');
      return false;
    }
  }

  Future<PushSwitch> setEnabled(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!on) {
        await prefs.setBool(kPushEnabledKey, false);
        await _send(null);
        return PushSwitch.off;
      }
      final permission = await _messaging.permission();
      if (permission != PushPermission.granted) {
        // Blocked keeps the wish: allowing them in the phone's settings is
        // then enough, with no second tap here.
        if (permission == PushPermission.blocked) {
          await prefs.setBool(kPushEnabledKey, true);
          return PushSwitch.blocked;
        }
        await prefs.setBool(kPushAskedKey, true);
        final answer = await _messaging.requestPermission();
        if (answer != PushPermission.granted) {
          // An answer that moved is the user's no in the dialog just now —
          // an answer, not a reason to open the phone's settings. One that
          // did not move is a phone that showed no dialog (Android 12 and
          // older), where only its settings can allow them.
          final blocked = answer == permission;
          await prefs.setBool(kPushEnabledKey, blocked);
          return blocked ? PushSwitch.blocked : PushSwitch.off;
        }
      }
      await prefs.setBool(kPushEnabledKey, true);
      await _sendCurrent();
      return PushSwitch.on;
    } catch (error) {
      debugPrint('Push: switch failed: $error');
      return on ? PushSwitch.blocked : PushSwitch.off;
    }
  }

  /// After sign-in, so the server ties the token to the account. Never asks.
  Future<void> onSignedIn() => _guard(() async {
        if (await _allowed()) await _sendCurrent();
      });

  void dispose() {
    unawaited(_refreshes?.cancel());
    unawaited(_notices?.cancel());
    _refreshes = null;
    _notices = null;
  }

  void _listen() {
    _refreshes ??= _messaging.tokenRefreshes.listen(
      (token) => _guard(() async {
        if (await _allowed()) await _send(token);
      }),
    );
    _notices ??= _messaging.foregroundNotices.listen(
      (notice) => _guard(() async {
        if (await isEnabled()) await _showNotice(notice);
      }),
    );
  }

  Future<bool> _allowed() async =>
      await isEnabled() &&
      await _messaging.permission() == PushPermission.granted;

  bool _enabledIn(SharedPreferences prefs) =>
      prefs.getBool(kPushEnabledKey) ?? true;

  Future<void> _sendCurrent() async {
    final token = await _messaging.token();
    if (token != null && token.isNotEmpty) await _send(token);
  }

  Future<void> _send(String? token) => _guard(() => _sendToken(token));

  Future<void> _guard(Future<void> Function() work) async {
    try {
      await work();
    } catch (error) {
      debugPrint('Push: $error');
    }
  }
}
