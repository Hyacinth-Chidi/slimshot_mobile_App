import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/held_work.dart';
import '../../account/models/account_models.dart';
import '../logic/speech/speech_request.dart';
import '../logic/speech/voice_clip.dart';
import 'speech_errors.dart';
import 'speech_pipeline.dart';
import 'speech_service.dart';

/// The line a run's stage shows, for [count] voices.
String speechStageLabel(SpeechStage stage, {int count = 1}) {
  final voices = count == 1 ? 'voice' : 'voices';
  return switch (stage) {
    SpeechStage.speaking => 'Making the $voices',
    SpeechStage.downloading => 'Saving the $voices',
  };
}

/// One voice run as the sheet shows it: where the pipeline is, a failure's
/// line, a shortfall waiting on the user, and the voices once they land —
/// Auto captions' `CaptionRun`, for the same kind of purchase.
///
/// A retry goes again on the same pipeline — under the same key, so a lost
/// answer is never a second charge — an earned balance that covers the price
/// carries a shortfall on, and closing answers it no, so a short run never
/// starts. It holds the app from [start] until it is disposed (`HeldWork`):
/// a run torn down from outside would have spent its credits on nothing.
class SpeechRun extends ChangeNotifier {
  SpeechRun({
    required SpeechPipeline pipeline,
    required this.voiceId,
    required this.plan,
    HeldWork? heldWork,
  })  : _pipeline = pipeline,
        _held = heldWork ?? HeldWork.instance;

  final SpeechPipeline _pipeline;
  final String voiceId;
  final SpeechReady plan;
  final HeldWork _held;

  SpeechStage _stage = SpeechStage.speaking;
  Object? _failure;
  CreditQuote? _shortfall;
  Completer<bool>? _decision;
  List<VoiceClip>? _voices;
  bool _started = false;
  bool _finished = false;
  bool _disposed = false;

  SpeechStage get stage => _stage;

  /// What stopped the run, while it is shown.
  Object? get failure => _failure;

  /// The failure's one line.
  String? get error {
    final failure = _failure;
    return failure == null ? null : speechErrorMessage(failure);
  }

  /// The price the balance does not cover, while the user is asked.
  CreditQuote? get shortfall => _shortfall;

  /// The voices, once they land. Set once, never after a stop.
  List<VoiceClip>? get voices => _voices;

  /// Takes the hold and runs. A second call does nothing.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _held.hold(this);
    unawaited(_run());
  }

  /// After a failure: runs again on the same pipeline, so a held key is
  /// reused rather than replaced.
  void retry() {
    if (_disposed || _failure == null) return;
    _failure = null;
    _shortfall = null;
    _decision = null;
    _stage = SpeechStage.speaking;
    notifyListeners();
    unawaited(_run());
  }

  /// A balance the user just earned: enough carries the run on, too little
  /// updates the shortfall.
  void earned(int balance) {
    final quote = _shortfall;
    final decision = _decision;
    if (_disposed || quote == null || decision == null || decision.isCompleted) {
      return;
    }
    if (balance >= quote.credits) {
      _shortfall = null;
      _decision = null;
      notifyListeners();
      decision.complete(true);
    } else {
      _shortfall = CreditQuote(
        credits: quote.credits,
        balance: balance,
        enough: false,
      );
      notifyListeners();
    }
  }

  Future<bool> _showShortfall(CreditQuote quote) {
    final decision = Completer<bool>();
    _shortfall = quote;
    _decision = decision;
    _changed();
    return decision.future;
  }

  Future<void> _run() async {
    try {
      final voices = await _pipeline.run(
        voiceId,
        plan,
        onProgress: (stage) {
          _stage = stage;
          _changed();
        },
        onShortfall: _showShortfall,
      );
      _finished = true;
      if (_disposed) return;
      _voices = voices;
      notifyListeners();
    } on SpeechCancelled {
      // Stopped: whoever stopped it is already on its way out.
    } catch (error) {
      // The words go to the log; the user sees the plain line.
      debugPrint('Text to speech failed: $error');
      if (_disposed) return;
      _failure = error;
      notifyListeners();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _held.release(this);
    if (_started && !_finished) _pipeline.cancel();
    // Closed on its shortfall — Cancel, Back, a tap outside: nothing starts.
    final decision = _decision;
    if (decision != null && !decision.isCompleted) decision.complete(false);
    super.dispose();
  }
}
