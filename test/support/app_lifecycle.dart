import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tells the app its lifecycle is now [state] the way the phone does: one
/// message on the lifecycle channel, from which the binding walks every
/// state in between. Calling the binding with the state directly skips them,
/// and straight from resumed to hidden is not a move a phone makes —
/// `AppLifecycleListener` asserts on it.
Future<void> sendAppLifecycle(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
    (_) {},
  );
}
