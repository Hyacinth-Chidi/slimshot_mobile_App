import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/app_build.dart';

/// This install's build, as Android reports it — what the saved tile
/// drawings are kept against, so one build's are never shown by another.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(kAppBuildChannel, null));

  test('the build is what the platform reports', () async {
    messenger.setMockMethodCallHandler(kAppBuildChannel, (call) async {
      expect(call.method, 'buildStamp');
      return '2-1793141004000';
    });
    expect(await appBuildStamp(), '2-1793141004000');
  });

  test('a platform that cannot say gives no build, never an error',
      () async {
    messenger.setMockMethodCallHandler(kAppBuildChannel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    expect(await appBuildStamp(), isNull);
  });

  test('a platform without the channel gives no build', () async {
    messenger.setMockMethodCallHandler(
      kAppBuildChannel,
      (call) async => throw MissingPluginException(),
    );
    expect(await appBuildStamp(), isNull);
  });
}
