import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/video_editor/logic/speech/speech_request.dart';
import 'package:slimshotai/features/video_editor/services/speech_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/speech_service.dart';

/// Two texts: "Hello" at 1s (text `a`) and "World" at 4s (text `b`), ten
/// characters between them.
const kTwoTexts = SpeechReady([
  SpeechTarget(textId: 'a', text: 'Hello', startSeconds: 1),
  SpeechTarget(textId: 'b', text: 'World', startSeconds: 4),
], 10);

const kPriced = CreditQuote(credits: 4, balance: 94, enough: true);
const kFree = CreditQuote(credits: 0, balance: 94, enough: true);
const kShort = CreditQuote(credits: 30, balance: 0, enough: false);

/// Every step a [SpeechPipeline] takes, faked and recorded: what was priced,
/// started under which key, downloaded and deleted.
class SpeechFakes {
  CreditQuote quote = kPriced;
  final List<int> quoted = [];

  final List<({String voiceId, List<SpeechItem> items, String key})> started =
      [];

  /// Thrown by every start while set.
  Object? startFailure;

  /// Thrown by the next starts, one each, before they succeed.
  List<Object> startFailures = [];
  CreditCharge? charge;
  final List<int> charged = [];

  Object? jobFailure;
  Future<List<SpokenItem>> Function(bool Function() isCancelled)? awaitWith;
  List<SpokenItem> spoken = const [
    SpokenItem(id: 't0', durationSeconds: 2),
    SpokenItem(id: 't1', durationSeconds: 3),
  ];

  final List<(String, String, String)> downloads = [];
  Map<String, Object> downloadFailures = {};
  Future<String> Function(String itemId)? downloadWith;
  final List<String> deleted = [];

  int cancels = 0;
  int _keys = 0;

  SpeechPipeline pipeline() => SpeechPipeline(
        quotePrice: (characters) async {
          quoted.add(characters);
          return quote;
        },
        startJob: (voiceId, items, key) async {
          started.add((voiceId: voiceId, items: items, key: key));
          final failure = startFailure ??
              (startFailures.isEmpty ? null : startFailures.removeAt(0));
          if (failure != null) throw failure;
          return SpeechJobStart(
            jobId: 'tts_1',
            pollAfter: Duration.zero,
            charged: charge,
          );
        },
        awaitJob: (job, isCancelled) async {
          if (awaitWith != null) return awaitWith!(isCancelled);
          if (jobFailure != null) throw jobFailure!;
          return spoken;
        },
        download: (jobId, itemId, textId) async {
          downloads.add((jobId, itemId, textId));
          final failure = downloadFailures[itemId];
          if (failure != null) throw failure;
          if (downloadWith != null) return downloadWith!(itemId);
          return '/voices/$textId.mp3';
        },
        deleteFile: (path) async => deleted.add(path),
        onCancel: () => cancels++,
        onCharged: charged.add,
        newKey: () => 'key-${++_keys}',
      );
}
