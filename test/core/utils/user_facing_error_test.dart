import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/utils/user_facing_error.dart';

void main() {
  test('an error written for the user is shown as written', () {
    expect(
      userMessageFor(
        const UserFacingError('Move the playhead further into the clip to split it.'),
        fallback: "Couldn't split the clip.",
      ),
      'Move the playhead further into the clip to split it.',
    );
  });

  test('a user-facing error reads as its own words, with no type prefix', () {
    // Thrown and caught as an Exception, it still prints as a sentence — an
    // `Exception('…')` prints as "Exception: …", which is what used to reach
    // the toasts.
    expect(
      const UserFacingError('This clip is already a still.').toString(),
      'This clip is already a still.',
    );
    expect(const UserFacingError('x'), isA<Exception>());
  });

  test('anything else is the fallback, never its own text', () {
    for (final error in [
      Exception('MediaCodec failed: 0x80001001'),
      StateError('Bad state'),
      PlatformException(code: 'export_failed', message: 'IllegalStateException at…'),
      'a string thrown',
    ]) {
      expect(userMessageFor(error, fallback: 'Export failed. Try again.'),
          'Export failed. Try again.');
    }
  });
}
