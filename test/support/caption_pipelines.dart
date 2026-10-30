import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/caption_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/caption_service.dart';

/// "Hello", one word from 0.2 s to 0.5 s.
const kHelloTranscript = CaptionTranscript(
  text: 'Hello',
  words: [TranscriptWord(text: 'Hello', start: 0.2, end: 0.5)],
);

/// A second of sound, rendered.
const kSoundRendered = CaptionAudioResult(
  outputPath: '/tmp/none.wav',
  durationSeconds: 1,
  hasSound: true,
);

/// A price the balance covers: the run goes straight on.
const kCoveredQuote = CreditQuote(credits: 0, balance: 94, enough: true);

/// A caption pipeline whose steps are the test's own — rendering the audio
/// (reporting through `onProgress`), the price, the upload (given its key)
/// and the transcript — so a run is driven step by step with no file, device
/// or network.
CaptionPipeline fakeCaptionPipeline({
  required Future<CaptionAudioResult> Function(
    void Function(double progress) onProgress,
  ) render,
  Future<CaptionTranscript> Function()? transcript,
  Future<CaptionJobStart> Function(String key)? upload,
  CreditQuote quote = kCoveredQuote,
  void Function()? onCancel,
  String Function()? newKey,
}) =>
    CaptionPipeline(
      audioPath: () async => '/tmp/none.wav',
      deleteFile: (_) async {},
      renderAudio: (path, source, onProgress) => render(onProgress),
      quotePrice: (_) async => quote,
      startJob: (path, language, key) => upload != null
          ? upload(key)
          : Future.value(
              const CaptionJobStart(jobId: 'cap_1', pollAfter: Duration.zero),
            ),
      awaitJob: (job, isCancelled) =>
          transcript == null ? Future.value(kHelloTranscript) : transcript(),
      onCancel: onCancel ?? () {},
      newKey: newKey,
    );
