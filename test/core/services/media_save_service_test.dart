import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/media_save_service.dart';

/// Whether a share counts as keeping the result: a result sent somewhere is
/// kept, so leaving it asks nothing; a share sheet closed without choosing
/// is not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late File file;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('media_save_test');
    file = File('${temp.path}/slimshot_temp_out.mp4')..writeAsBytesSync([1]);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<bool> shareAnswering(Object? Function() answer) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'shareFiles');
      return answer();
    });
    return MediaSaveService.shareFiles([file.path]);
  }

  test('sent somewhere: kept', () async {
    expect(await shareAnswering(() => 'com.whatsapp'), isTrue);
  });

  test('the sheet closed without choosing: not kept', () async {
    expect(await shareAnswering(() => ''), isFalse);
  });

  test('a phone that cannot say how it went: kept, so nobody is asked twice',
      () async {
    expect(await shareAnswering(() => null), isTrue);
  });

  test('a share that failed: not kept', () async {
    expect(
      await shareAnswering(() => throw PlatformException(code: 'failed')),
      isFalse,
    );
  });
}
