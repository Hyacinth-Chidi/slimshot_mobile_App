import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fonts come from SlimShot's server and the few bundled with the app.
/// google_fonts fetched from Google at runtime, outside the app's control
/// and its licences; it must not come back by way of a stray import.
void main() {
  test('nothing in the app imports google_fonts', () {
    final offenders = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            entity.readAsStringSync().contains('package:google_fonts'))
          entity.path,
    ];
    expect(offenders, isEmpty);
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('google_fonts:')));
  });
}
