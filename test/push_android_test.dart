import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/push/native_notifications.dart';

const _res = 'android/app/src/main/res';

/// A status bar icon's size in px at each density: 24dp.
const _iconSizes = {
  'mdpi': 24,
  'hdpi': 36,
  'xhdpi': 48,
  'xxhdpi': 72,
  'xxxhdpi': 96,
};

String? _metaData(String manifest, String name, String attribute) =>
    RegExp('android:name="${RegExp.escape(name)}"\\s*android:$attribute="([^"]*)"')
        .firstMatch(manifest)
        ?.group(1);

/// `UPDATE_NOTIFICATION_ICON=1 flutter test test/push_android_test.dart`
/// redraws the small icon from `assets/logo.png`: the logo's outline in
/// white, inside the 20dp of the 24dp square a status bar icon keeps clear.
/// Without the variable this checks what is committed.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  if (Platform.environment['UPDATE_NOTIFICATION_ICON'] == '1') {
    testWidgets('redraw the small icon from the logo', (tester) async {
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          File('assets/logo.png').readAsBytesSync(),
        );
        final logo = (await codec.getNextFrame()).image;
        final logoSize = Size(logo.width * 1.0, logo.height * 1.0);
        for (final MapEntry(key: density, value: size) in _iconSizes.entries) {
          final height = size * 20 / 24;
          final width = height * logoSize.width / logoSize.height;
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawImageRect(
            logo,
            Offset.zero & logoSize,
            Rect.fromLTWH((size - width) / 2, (size - height) / 2, width, height),
            Paint()
              // Mipmapped: a 20x reduction averages, where a cubic aliases.
              ..filterQuality = FilterQuality.medium
              ..colorFilter =
                  const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          );
          final image = await recorder.endRecording().toImage(size, size);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('$_res/drawable-$density')
            ..createSync(recursive: true);
          File('${dir.path}/ic_stat_slimshot.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        }
        logo.dispose();
      });
    });
    return;
  }

  // A notification Firebase draws (app closed) and one the app draws (app
  // open) must land in the same channel, under the same switch in the
  // phone's settings, with the same icon.
  test('Firebase draws in the app\'s own channel', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/techfamz/slimshotai/notifications/'
      'NotificationsChannel.kt',
    ).readAsStringSync();
    final channel =
        RegExp(r'const val CHANNEL_ID = "([^"]+)"').firstMatch(kotlin)!.group(1);
    expect(
      _metaData(manifest,
          'com.google.firebase.messaging.default_notification_channel_id', 'value'),
      channel,
    );
    expect(File('$_res/values/strings.xml').readAsStringSync(),
        contains('name="notification_channel_name"'));
  });

  test('Dart and Kotlin name the notifications channel alike', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/techfamz/slimshotai/notifications/'
      'NotificationsChannel.kt',
    ).readAsStringSync();
    expect(
      RegExp(r'const val channelName = "([^"]+)"').firstMatch(kotlin)!.group(1),
      NativeNotifications.channelName,
    );
  });

  test('Firebase uses the app\'s small icon and colour', () {
    expect(
      _metaData(manifest,
          'com.google.firebase.messaging.default_notification_icon', 'resource'),
      '@drawable/ic_stat_slimshot',
    );
    expect(
      _metaData(manifest,
          'com.google.firebase.messaging.default_notification_color', 'resource'),
      '@color/notification_accent',
    );
    expect(File('$_res/values/colors.xml').readAsStringSync(),
        contains('name="notification_accent"'));
  });

  // Android draws a status bar icon from its alpha alone: anything not
  // transparent shows white, so a coloured icon becomes a white square.
  test('the small icon is a white shape at every density', () async {
    for (final MapEntry(key: density, value: size) in _iconSizes.entries) {
      final file = File('$_res/drawable-$density/ic_stat_slimshot.png');
      expect(file.existsSync(), isTrue, reason: density);
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      expect((image.width, image.height), (size, size), reason: density);
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      var inked = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        final alpha = bytes[i + 3];
        if (alpha == 0) continue;
        inked++;
        // Premultiplied: a white pixel's channels equal its alpha.
        expect([bytes[i], bytes[i + 1], bytes[i + 2]], [alpha, alpha, alpha],
            reason: '$density: not white');
      }
      expect(inked, greaterThan(size * size ~/ 8), reason: '$density: empty');
      expect(inked, lessThan(size * size * 3 ~/ 4), reason: '$density: a block');
    }
  });
}
