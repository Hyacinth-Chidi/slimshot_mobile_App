import 'package:flutter/foundation.dart';

/// An error whose message is written for the person using the app: a refusal
/// they can act on ("Move the playhead further into the clip to split it."),
/// in the words a toast should show.
///
/// Prints as the message alone. An `Exception('…')` prints as
/// "Exception: …", and a `StateError` as "Bad state: …", which is how those
/// prefixes reached people's screens.
class UserFacingError implements Exception {
  const UserFacingError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a toast says about a caught [error].
///
/// Its own words when it was written for the user ([UserFacingError]);
/// otherwise [fallback], a plain line saying what did not happen. The error
/// itself goes to the log, where it helps someone fixing the app — a
/// platform message, an exception class or a file path in a toast only
/// alarms someone using it (device-reported, 2026-11-10).
String userMessageFor(Object error, {required String fallback}) {
  if (error is UserFacingError) return error.message;
  debugPrint('[$fallback] $error');
  return fallback;
}
