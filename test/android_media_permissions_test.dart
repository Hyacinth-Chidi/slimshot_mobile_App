import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Google Play refuses an app targeting Android 13+ that declares
/// READ_MEDIA_IMAGES or READ_MEDIA_VIDEO where the system photo picker would
/// do (its photo and video permissions policy; it blocked 2.0.1 (4) on
/// 2026-11-02). Every pick goes through the photo picker
/// (`MediaPickerService`), which needs no permission, and nothing asks for
/// either at runtime, so the app has never held them on Android 13+. They are
/// removed from the merged manifest outright, so a plugin added later cannot
/// bring them back.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  for (final permission in [
    'android.permission.READ_MEDIA_IMAGES',
    'android.permission.READ_MEDIA_VIDEO',
  ]) {
    test('$permission is removed, never requested', () {
      final entries = RegExp(
        r'<uses-permission\b[^>]*android:name="' +
            RegExp.escape(permission) +
            r'"[^>]*/>',
      ).allMatches(manifest).map((m) => m.group(0)!).toList();
      expect(entries, hasLength(1), reason: 'one entry: the removal');
      expect(entries.single, contains('tools:node="remove"'));
    });
  }

  test('the manifest declares the tools namespace its removals use', () {
    expect(manifest, contains('xmlns:tools="http://schemas.android.com/tools"'));
  });
}
