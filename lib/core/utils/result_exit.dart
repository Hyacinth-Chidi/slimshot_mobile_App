import 'dart:async';

import 'file_utils.dart';
import 'held_work.dart';

/// Leaving a finished result — a compression, an export —
/// throws its files away: they are the app's temporary copies, of no use once
/// off screen, since a saved one is in the gallery and a shared one the share
/// plugin copied before handing it over. One that was neither saved nor
/// shared is asked about first ([markKept] says it was).
///
/// The picked files a result was made from are never deleted here: a result
/// handed back as it was *is* its picked file, and the screen it was picked
/// for deletes those when it closes.
class ResultExit {
  ResultExit({
    TempFileDeleter delete = FileUtils.deleteTempFiles,
    HeldWork? held,
  })  : _delete = delete,
        _held = held ?? HeldWork.instance;

  final TempFileDeleter _delete;
  final HeldWork _held;
  bool _kept = false;
  bool _leaving = false;

  /// Holds the app where it is ([HeldWork]) until the result is kept or
  /// [release]d: a tap on the home screen widget must not throw away a
  /// result nobody has saved or shared.
  void hold() {
    if (!_kept) _held.hold(this);
  }

  /// The screen is going, or has nothing left to keep.
  void release() => _held.release(this);

  /// The result was saved, or sent somewhere: leaving it asks nothing.
  /// Whether the result was saved or shared — kept somewhere off this
  /// screen.
  bool get kept => _kept;

  void markKept() {
    _kept = true;
    _held.release(this);
  }

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
