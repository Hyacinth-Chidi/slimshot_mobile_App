/// How far past the engine's last report the drawn playhead may run. Reports
/// arrive every 32–48 ms; one that has not landed in this long is not late,
/// it is not coming, and the playhead must not move on without it.
const double kPlayheadMaxExtrapolationSeconds = 0.1;

/// A report behind the drawn playhead by more than this is a jump (a seek, a
/// loop), not one that landed late, and is drawn as it is.
const double kPlayheadJumpSeconds = 0.25;

/// The playhead as **drawn** while the engine plays.
///
/// The engine reports its position about thirty times a second, and a
/// playhead that moves only when a report lands steps every other frame — at
/// a close zoom by ~20 px. Between reports this carries it on at the rate
/// time passes, which is the rate timeline seconds advance at whatever a
/// clip's speed.
///
/// **It writes nothing.** The editor's playhead state is still the engine's
/// reports alone (a second clock writing it is dead-ends entry 12); this is
/// what the timeline scrolls to and what text is drawn at, between them.
///
/// Three rules keep it honest:
///
/// - It moves only while the engine says its picture is moving
///   (`advancing`), and then exactly where the engine put it: the playhead
///   must never move while the video is stalled.
/// - It runs at most [kPlayheadMaxExtrapolationSeconds] past the last
///   report, so reports that stop arriving stop it too.
/// - It never steps back for a report that landed late; it holds until time
///   catches up with it. A report far behind is a jump and is drawn.
///
/// Times are a caller's monotonic clock (`at`), the same one for reports and
/// frames.
class PlayheadDisplayClock {
  double _sample = 0;
  Duration _sampleAt = Duration.zero;
  bool _advancing = false;

  /// What was last drawn, so a late report cannot pull it back.
  double _shown = 0;

  /// A report from the engine: where the playhead was at [at], and whether
  /// its picture is moving.
  void report(double seconds, {required bool advancing, required Duration at}) {
    _sample = seconds;
    _sampleAt = at;
    _advancing = advancing;
    if (!advancing || seconds < _shown - kPlayheadJumpSeconds) _shown = seconds;
  }

  /// Puts the playhead exactly at [seconds], still — before playback starts
  /// from there, and after anything else moves it.
  void place(double seconds) {
    _sample = seconds;
    _shown = seconds;
    _advancing = false;
  }

  /// The playhead to draw at [at], never past [end].
  double positionAt(Duration at, {double end = double.infinity}) {
    if (!_advancing) return _sample;
    final elapsed = (at - _sampleAt).inMicroseconds / 1e6;
    final carried = elapsed.clamp(0.0, kPlayheadMaxExtrapolationSeconds);
    var shown = _sample + carried;
    if (shown < _shown) shown = _shown;
    if (shown > end) shown = end;
    return _shown = shown;
  }
}
