import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/features/push/push_controller.dart';
import 'package:slimshotai/features/push/push_messaging.dart';

import '../../support/fake_push_messaging.dart';

void main() {
  late FakePushMessaging messaging;
  late List<String?> sent;
  late List<(String, String)> shown;
  late bool failSends;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messaging = FakePushMessaging();
    sent = [];
    shown = [];
    failSends = false;
  });

  PushController controller() => PushController(
        messaging: messaging,
        sendToken: (token) async {
          if (failSends) throw Exception('offline');
          sent.add(token);
        },
        showNotice: (notice) async => shown.add((notice.title, notice.body)),
      );

  // Let the streams' events reach their listeners.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('starting', () {
    test('asks once, the first time, and sends the token when allowed',
        () async {
      final first = controller();
      await first.start();
      expect(messaging.requests, 1);
      expect(sent, ['fcm-1']);
      first.dispose();

      // A later launch does not ask again, and sends the token again.
      final second = controller();
      await second.start();
      expect(messaging.requests, 1);
      expect(sent, ['fcm-1', 'fcm-1']);
      second.dispose();
    });

    // A phone can report denied before this app ever asked (Android 12 and
    // older; a permission another plugin asked for), and is asked that once.
    test('a phone that reports denied before ever being asked is asked once',
        () async {
      messaging.current = PushPermission.denied;
      await controller().start();
      expect(messaging.requests, 1);
      expect(sent, ['fcm-1']);
    });

    test('refused, sends nothing and does not ask again', () async {
      messaging.answer = PushPermission.denied;
      await controller().start();
      await controller().start();
      expect(messaging.requests, 1);
      expect(sent, isEmpty);
    });

    test('a phone that never asks (Android 12 and older) just sends', () async {
      messaging.current = PushPermission.granted;
      await controller().start();
      expect(messaging.requests, 0);
      expect(sent, ['fcm-1']);
    });

    test('no token from Firebase sends nothing', () async {
      messaging.currentToken = null;
      await controller().start();
      expect(sent, isEmpty);
    });

    test('a send that fails is swallowed, never thrown', () async {
      failSends = true;
      await expectLater(controller().start(), completes);
    });
  });

  test('a token Firebase replaces is sent', () async {
    final push = controller();
    await push.start();
    messaging.refreshes.add('fcm-2');
    await settle();
    expect(sent, ['fcm-1', 'fcm-2']);
    push.dispose();
  });

  test('a notification arriving while the app is open is shown', () async {
    final push = controller();
    await push.start();
    messaging.notices.add(const PushNotice(title: 'New fonts', body: 'Ten more.'));
    await settle();
    expect(shown, [('New fonts', 'Ten more.')]);
    push.dispose();
  });

  group('the switch', () {
    test('is on by default', () async {
      expect(await controller().isEnabled(), isTrue);
    });

    test('off clears the token, and a later refresh sends nothing', () async {
      messaging.current = PushPermission.granted;
      final push = controller();
      await push.start();
      expect(await push.setEnabled(false), PushSwitch.off);
      expect(sent, ['fcm-1', null]);
      expect(await push.isEnabled(), isFalse);

      messaging.refreshes.add('fcm-2');
      await settle();
      expect(sent, ['fcm-1', null]);
      push.dispose();
    });

    // Switched off with no connection, the server would keep the token and
    // notifications would go on arriving under a switch that says off.
    test('off, every start tells the server again, never the token', () async {
      messaging.current = PushPermission.granted;
      failSends = true;
      await controller().setEnabled(false);
      failSends = false;
      await controller().start();
      expect(sent, [null]);
    });

    test('off, a notification arriving while the app is open is not drawn',
        () async {
      messaging.current = PushPermission.granted;
      final push = controller();
      await push.setEnabled(false);
      await push.start();
      messaging.notices.add(const PushNotice(title: 'T', body: 'B'));
      await settle();
      expect(shown, isEmpty);
      push.dispose();
    });

    test('off before ever asked: the first start does not ask', () async {
      await controller().setEnabled(false);
      await controller().start();
      expect(messaging.requests, 0);
    });

    test('back on sends the token', () async {
      messaging.current = PushPermission.granted;
      final push = controller();
      await push.setEnabled(false);
      expect(await push.setEnabled(true), PushSwitch.on);
      expect(sent.last, 'fcm-1');
      expect(await push.isEnabled(), isTrue);
    });

    test('back on asks if the phone has not been asked', () async {
      final push = controller();
      await push.setEnabled(false);
      expect(await push.setEnabled(true), PushSwitch.on);
      expect(messaging.requests, 1);
      expect(sent.last, 'fcm-1');
    });

    // Android 12 and older show no dialog: the answer cannot change, so only
    // the phone's settings can allow them.
    test('on, where no dialog can be shown, says blocked and reads off',
        () async {
      messaging
        ..current = PushPermission.denied
        ..answer = PushPermission.denied;
      final push = controller();
      expect(await push.setEnabled(true), PushSwitch.blocked);
      expect(await push.isOn(), isFalse);
      expect(sent, isEmpty);
    });

    // Blocked, the user is sent to the phone's settings: allowing them there
    // must be enough, with no second tap on a switch that went back to off.
    test('blocked, then allowed in the phone settings: on, and sent',
        () async {
      messaging
        ..current = PushPermission.blocked
        ..answer = PushPermission.blocked;
      final push = controller();
      expect(await push.setEnabled(true), PushSwitch.blocked);
      messaging.current = PushPermission.granted;
      expect(await push.isOn(), isTrue);
      await push.start();
      expect(sent, ['fcm-1']);
    });

    test('on, where the phone refused for good, says blocked without asking',
        () async {
      messaging.current = PushPermission.blocked;
      expect(await controller().setEnabled(true), PushSwitch.blocked);
      expect(messaging.requests, 0);
    });

    // The user has just said no in the dialog: that is an answer, not a
    // reason to send them to the phone's settings.
    test('on, then no in the dialog, is simply off', () async {
      messaging.answer = PushPermission.denied;
      final push = controller();
      expect(await push.setEnabled(true), PushSwitch.off);
      expect(messaging.requests, 1);
      expect(await push.isEnabled(), isFalse);
      expect(sent, isEmpty);
    });

    test('a second no, which Android makes final, is still simply off',
        () async {
      messaging
        ..current = PushPermission.denied
        ..answer = PushPermission.blocked;
      expect(await controller().setEnabled(true), PushSwitch.off);
    });
  });

  group('signing in', () {
    test('sends the token again, so it reaches the account', () async {
      messaging.current = PushPermission.granted;
      await controller().onSignedIn();
      expect(sent, ['fcm-1']);
    });

    test('sends nothing while switched off', () async {
      messaging.current = PushPermission.granted;
      final push = controller();
      await push.setEnabled(false);
      sent.clear();
      await push.onSignedIn();
      expect(sent, isEmpty);
    });

    test('never asks for permission', () async {
      await controller().onSignedIn();
      expect(messaging.requests, 0);
      expect(sent, isEmpty);
    });
  });

  // What the Settings switch shows: on only where notifications can arrive.
  group('on', () {
    test('when switched on and the phone allows them', () async {
      messaging.current = PushPermission.granted;
      expect(await controller().isOn(), isTrue);
    });

    test('not where the phone has turned them off', () async {
      messaging.current = PushPermission.denied;
      expect(await controller().isOn(), isFalse);
    });

    test('not when switched off', () async {
      messaging.current = PushPermission.granted;
      final push = controller();
      await push.setEnabled(false);
      expect(await push.isOn(), isFalse);
    });
  });
}
