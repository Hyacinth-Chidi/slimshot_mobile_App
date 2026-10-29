import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Privacy Strip left the app (the owner's call, 2026-10-29): Auto captions
/// took its place on Home. Its screens, routes, metadata reader and ad
/// placement must not come back by way of a stray reference.
void main() {
  test('nothing in the app is left of Privacy Strip', () {
    const traces = [
      'privacyStrip',
      'PrivacyStrip',
      'PhotoMetadata',
      'photo_metadata',
      'features/privacy',
      'PrivacyScreen',
      'PrivacyResultScreen',
      // The route, quoted — Settings' privacy policy address is not it.
      "'/privacy",
    ];
    final offenders = [
      for (final root in ['lib', 'android/app/src/main'])
        for (final entity in Directory(root).listSync(recursive: true))
          if (entity is File &&
              (entity.path.endsWith('.dart') ||
                  entity.path.endsWith('.kt') ||
                  entity.path.endsWith('.xml')))
            for (final trace in traces)
              // Not every source file is valid UTF-8; a trace is ASCII.
              if (utf8
                  .decode(entity.readAsBytesSync(), allowMalformed: true)
                  .contains(trace))
                '${entity.path}: $trace',
    ];
    expect(offenders, isEmpty);
  });
}
