import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Camera feature asks for the camera — and must not cost the app the
/// phones that have none. A `CAMERA` permission on its own makes Play assume
/// the app *requires* a camera and hide it from every device without one (the
/// same filter that dropped devices when `RECORD_AUDIO` arrived), so each
/// camera feature is declared, and declared not required.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('the camera permission is declared', () {
    expect(
      manifest,
      matches(RegExp(r'<uses-permission\b[^>]*android:name="android\.permission\.CAMERA"')),
    );
  });

  for (final feature in [
    'android.hardware.camera',
    'android.hardware.camera.any',
    'android.hardware.camera.front',
    'android.hardware.camera.autofocus',
    'android.hardware.camera.flash',
  ]) {
    test('$feature is not required', () {
      final entry = RegExp(
        r'<uses-feature\b[^>]*android:name="' + RegExp.escape(feature) + r'"[^>]*/>',
      ).firstMatch(manifest)?.group(0);
      expect(entry, isNotNull, reason: 'declared, so Play does not imply it');
      expect(entry, contains('android:required="false"'));
    });
  }
}
