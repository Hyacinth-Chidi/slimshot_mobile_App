import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The name under the app's icon once installed — "Slimshot", the owner's
/// call (2026-10-30). Inside the app the brand still reads SlimShot AI; only
/// the launcher's label is short.
void main() {
  test('the Android launcher shows "Slimshot"', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final application =
        RegExp(r'<application\b[^>]*>', dotAll: true).firstMatch(manifest)!;
    final label = RegExp(r'android:label="([^"]*)"')
        .firstMatch(application.group(0)!)!
        .group(1);
    expect(label, 'Slimshot');
  });

  test('the iOS home screen shows "Slimshot"', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final name = RegExp(
      r'<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>',
    ).firstMatch(plist)!.group(1);
    expect(name, 'Slimshot');
  });
}
