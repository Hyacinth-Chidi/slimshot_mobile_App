import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/home_widget/home_widget_sync.dart';
import 'package:slimshotai/features/home_widget/launch_actions.dart';

/// A tap on the home screen widget or the icon's menu reaches the app as an
/// action: read once, and sent where one rule says.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(kHomeWidgetChannel);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('the three actions read from the wire; anything else is nothing', () {
    expect(
      LaunchAction.fromWire({'action': 'continue', 'draftId': 'd1'}),
      const ContinueEdit('d1'),
    );
    expect(LaunchAction.fromWire({'action': 'new_video'}), const NewVideo());
    expect(
      LaunchAction.fromWire({'action': 'compress_video', 'draftId': null}),
      const CompressVideo(),
    );
    for (final junk in <Object?>[
      null,
      'x',
      {'action': 'continue'},
      {'action': 'continue', 'draftId': ''},
      {'action': 'share'},
    ]) {
      expect(LaunchAction.fromWire(junk), isNull, reason: '$junk');
    }
  });

  test('where a tap goes', () {
    LaunchRoute r(
      LaunchAction a, {
      bool busy = false,
      String? open,
      bool seen = true,
    }) =>
        routeFor(a, busy: busy, openDraftId: open, onboardingSeen: seen);
    expect(r(const NewVideo()), LaunchRoute.goHome);
    expect(r(const NewVideo(), busy: true), LaunchRoute.bringForward);
    expect(r(const ContinueEdit('d1'), open: 'd1'), LaunchRoute.bringForward);
    expect(r(const ContinueEdit('d1'), open: 'd2'), LaunchRoute.goHome);
    expect(r(const CompressVideo(), seen: false), LaunchRoute.waitForHome);
    expect(
      r(const ContinueEdit('d1'), busy: true, seen: false),
      LaunchRoute.bringForward,
    );
  });

  test('an action is taken once, and the last tap wins', () {
    var notified = 0;
    final actions = LaunchActions()..addListener(() => notified++);
    actions
      ..post(const NewVideo())
      ..post(const CompressVideo());
    expect(actions.pending, const CompressVideo());
    expect(actions.take(), const CompressVideo());
    expect(actions.take(), isNull);
    expect(notified, 2);
  });

  test('the action the app started with, then later ones, reach onAction',
      () async {
    var asked = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'takeLaunchAction') {
        asked++;
        return {'action': 'new_video', 'draftId': null};
      }
      return null;
    });
    final received = <LaunchAction>[];
    final launch = LaunchChannel(channel: channel, onAction: received.add);
    await launch.start();
    await messenger.handlePlatformMessage(
      kHomeWidgetChannel,
      const StandardMethodCodec().encodeMethodCall(const MethodCall(
        'launchAction',
        {'action': 'compress_video', 'draftId': null},
      )),
      (_) {},
    );
    expect(received, [const NewVideo(), const CompressVideo()]);
    expect(asked, 1);
    launch.dispose();
  });

  test('a phone without the channel is no error', () async {
    await LaunchChannel(
      channel: const MethodChannel('nowhere'),
      onAction: (_) {},
    ).start();
  });

  group('LaunchRouter', () {
    late List<String> log;
    late LaunchActions actions;

    LaunchRouter router({bool busy = false, String? open, bool seen = true}) =>
        LaunchRouter(
          busy: () => busy,
          openDraftId: () => open,
          onboardingSeen: () async => seen,
          saveOpenEdit: () async => log.add('save'),
          goHome: () => log.add('home'),
          untilEditorGone: () async => log.add('gone'),
          actions: actions,
        );

    setUp(() {
      log = [];
      actions = LaunchActions()..addListener(() => log.add('post'));
    });

    test('another edit open: saved, Home, the editor gone, then the action',
        () async {
      await router(open: 'd2').handle(const ContinueEdit('d1'));
      expect(log, ['save', 'home', 'gone', 'post']);
      expect(actions.take(), const ContinueEdit('d1'));
    });

    // An editor still loading its media has no draft id yet; Home must not
    // act until it has gone all the same.
    test('nothing to save: Home, the editor gone, then the action', () async {
      await router().handle(const NewVideo());
      expect(log, ['home', 'gone', 'post']);
      expect(actions.take(), const NewVideo());
    });

    test('busy, or Continue on the open edit: nothing at all', () async {
      await router(busy: true).handle(const NewVideo());
      await router(open: 'd1').handle(const ContinueEdit('d1'));
      expect(log, isEmpty);
      expect(actions.pending, isNull);
    });

    test('before onboarding: kept for Home, nowhere navigated', () async {
      await router(seen: false).handle(const CompressVideo());
      expect(log, ['post']);
      expect(actions.take(), const CompressVideo());
    });
  });
}
