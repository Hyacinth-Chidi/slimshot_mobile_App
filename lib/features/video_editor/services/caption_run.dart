import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/held_work.dart';
import '../../account/models/account_models.dart';
import '../logic/captions/caption_grouping.dart';
import 'caption_errors.dart';
import 'caption_pipeline.dart';

/// The line a run's stage shows. The upload is never named (the user's
/// call): it reads as the listening it leads straight into.
String captionStageLabel(CaptionStage stage) => switch (stage) {
      CaptionStage.preparing => 'Preparing audio',
      CaptionStage.uploading => 'Listening',
      CaptionStage.listening => 'Listening',
      CaptionStage.placing => 'Placing captions',
    };

/// One caption run as a screen shows it: where the pipeline is, a failure's
/// line, a shortfall waiting on the user, and the words once they land.
///
/// The editor's progress sheet and the captions screen draw the same run, so
/// what a run does is written once: a retry goes again on the same pipeline —
/// under the same upload key, so a lost answer is never a second charge — an
/// earned balance that covers the price carries a shortfall on, and a stop
/// answers it no, so a short run never uploads.
///
/// It holds the app from [start] until it is disposed (`HeldWork`): a run
/// torn down from outside would have spent its credits on nothing.
class CaptionRun extends ChangeNotifier {
  CaptionRun({
    required CaptionPipeline pipeline,
    required this.request,
    HeldWork? heldWork,
  })  : _pipeline = pipeline,
        _held = heldWork ?? HeldWork.instance;

  final CaptionPipeline _pipeline;
  final CaptionRequest request;
  final HeldWork _held;

  CaptionStage _stage = CaptionStage.preparing;
  double? _progress = 0;
  Object? _failure;
  CreditQuote? _shortfall;
  Completer<bool>? _decision;
  List<CaptionDraft>? _drafts;
  bool _started = false;
  bool _finished = false;
  bool _disposed = false;

  CaptionStage get stage => _stage;

  /// The stage's progress, 0..1; null while the stage cannot say.
  double? get progress => _progress;

  /// What stopped the run, while it is shown.
  Object? get failure => _failure;

  /// The failure's one line.
  String? get error {
    final failure = _failure;
    return failure == null ? null : captionErrorMessage(failure);
  }

  /// The price the balance does not cover, while the user is asked.
  CreditQuote? get shortfall => _shortfall;

  /// The words, once they land. Set once, never after a stop.
  List<CaptionDraft>? get drafts => _drafts;

  /// Takes the hold and runs. A second call does nothing.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _held.hold(this);
    unawaited(_run());
  }

  /// After a failure: runs again on the same pipeline, so a held upload key
  /// is reused rather than replaced.
  void retry() {
    if (_disposed || _failure == null) return;
    _failure = null;
    _shortfall = null;
    _decision = null;
    _stage = CaptionStage.preparing;
    _progress = 0;
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
      final drafts = await _pipeline.run(
        request,
        onProgress: (stage, progress) {
          _stage = stage;
          _progress = progress;
          _changed();
        },
        onShortfall: _showShortfall,
      );
      _finished = true;
      if (_disposed) return;
      _drafts = drafts;
      notifyListeners();
    } on CaptionCancelled {
      // Stopped: whoever stopped it is already on its way out.
    } catch (error) {
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
    // Stopped on its shortfall — Close, Back, a tap outside: no upload.
    final decision = _decision;
    if (decision != null && !decision.isCompleted) decision.complete(false);
    super.dispose();
  }
}
