import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/app_version.dart';
import 'package:slimshotai/core/models/update_info.dart';
import 'package:slimshotai/core/services/update_service.dart';

UpdateInfo _latest(String version, int build) => UpdateInfo(
      latestVersion: version,
      latestBuildNumber: build,
      forceUpdate: false,
      title: '',
      releaseNotes: const [],
      updateUrl: '',
      minSupportedVersion: '1.0.0',
    );

void main() {
  // The version was written into the update check and Settings by hand, and
  // stayed at 2.0.0 (2) when pubspec moved to 2.0.1+3: Settings named the
  // wrong version, and once the update API said 2.0.1, every 2.0.1 install
  // would have been told to update to itself, for ever.
  test('the app knows the version pubspec.yaml builds', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(line.trim(), 'version: $kAppVersion+$kAppBuildNumber');
  });

  group('an update is offered', () {
    test('not for the version installed', () {
      expect(updateIsAvailable(_latest('2.0.1', 3), version: '2.0.1', build: 3),
          isFalse);
    });

    test('not for an older one', () {
      expect(updateIsAvailable(_latest('2.0.0', 2), version: '2.0.1', build: 3),
          isFalse);
    });

    test('for a newer version', () {
      expect(updateIsAvailable(_latest('2.0.2', 4), version: '2.0.1', build: 3),
          isTrue);
      expect(updateIsAvailable(_latest('2.1.0', 4), version: '2.0.1', build: 3),
          isTrue);
    });

    test('for a newer build of the same version', () {
      expect(updateIsAvailable(_latest('2.0.1', 4), version: '2.0.1', build: 3),
          isTrue);
    });

    test('measured against this build by default', () {
      expect(updateIsAvailable(_latest(kAppVersion, kAppBuildNumber)), isFalse);
    });
  });
}
