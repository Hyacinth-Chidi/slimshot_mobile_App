import 'dart:async';

import 'file_utils.dart';

/// Leaving a finished result — a compression, a privacy strip, an export —
/// throws its files away: they are the app's temporary copies, of no use once
/// off screen, since a saved one is in the gallery and a shared one the share
/// plugin copied before handing it over. One that was neither saved nor
/// shared is asked about first ([markKept] says it was).
///
/// The picked files a result was made from are never deleted here: a result
/// handed back as it was *is* its picked file, and the screen it was picked
/// for deletes those when it closes.
class ResultExit {
  ResultExit({TempFileDeleter delete = FileUtils.deleteTempFiles})
      : _delete = delete;

  final TempFileDeleter _delete;
  bool _kept = false;
  bool _leaving = false;

  /// The result was saved, or sent somewhere: leaving it asks nothing.
  void markKept() => _kept = true;

  /// Whether to leave. Asks through [confirm] when nothing was kept, then
  /// deletes [outputs] — never [inputs] — without waiting for the files to
  /// go. False when the answer was to stay, or a leave is already under way
  /// (a second tap while it asks).
  Future<bool> leave({
    required List<String> outputs,
    List<String> inputs = const [],
    required Future<bool> Function() confirm,
  }) async {
    if (_leaving) return false;
    _leaving = true;
    if (!_kept && !await confirm()) {
      _leaving = false;
      return false;
    }
    final picked = inputs.toSet();
    unawaited(_delete([
      for (final path in outputs)
        if (!picked.contains(path)) path,
    ]));
    return true;
  }
}
