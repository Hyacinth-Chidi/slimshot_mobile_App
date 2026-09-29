import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/core/utils/file_utils.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/caption_errors.dart';
import 'package:slimshotai/features/video_editor/services/caption_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/caption_service.dart';

void main() {
  const hello = CaptionTranscript(
    text: 'Hello world',
    words: [
      TranscriptWord(text: 'Hello', start: 0.2, end: 0.5),
      TranscriptWord(text: 'world', start: 0.6, end: 0.9),
    ],
  );
  const sound = CaptionAudioResult(
    outputPath: '/tmp/captions.m4a',
    durationSeconds: 3,
    hasSound: true,
  );
  const job = CaptionJobStart(jobId: 'cap_1', pollAfter: Duration.zero);

  late List<String> deleted;
  late List<String> keys;
  late int cancels;

  setUp(() {
    deleted = [];
    keys = [];
    cancels = 0;
  });

  CaptionPipeline pipeline({
    Future<CaptionAudioResult> Function(CaptionSource source)? render,
    Future<CaptionJobStart> Function(String? language)? start,
    Future<CaptionTranscript> Function(bool Function() isCancelled)? transcript,
  }) {
    var n = 0;
    return CaptionPipeline(
      audioPath: () async => '/tmp/captions.m4a',
      deleteFile: (path) async => deleted.add(path),
      newKey: () => 'key-${++n}',
      renderAudio: (path, source, onProgress) async {
        onProgress(0.5);
        return render == null ? sound : render(source);
      },
      startJob: (path, language, key) async {
        keys.add(key);
        return start == null ? job : start(language);
      },
      awaitJob: (job, isCancelled) =>
          transcript == null ? Future.value(hello) : transcript(isCancelled),
      onCancel: () => cancels++,
    );
  }

  test('render → upload → listen → place, and the audio file is cleaned up',
      () async {
    final stages = <CaptionStage>[];
    final progress = <double?>[];
    final drafts = await pipeline().run(
      const CaptionRequest(),
      onProgress: (stage, value) {
        if (stages.isEmpty || stages.last != stage) stages.add(stage);
        progress.add(value);
      },
    );
    expect(stages, CaptionStage.values);
    expect(progress, contains(0.5));
    expect(drafts.single.text, 'Hello world');
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('the audio file is one the startup sweep will find', () {
    // A run killed part-way never reaches its own cleanup; the sweep only
    // takes files that carry its prefix.
    final name = captionAudioFileName(DateTime.fromMillisecondsSinceEpoch(42));
    expect(name, startsWith(FileUtils.filePrefix));
    expect(name, endsWith('_42.m4a'));
  });

  test('no caption outlasts the sound it was heard in', () async {
    final drafts = await pipeline(
      render: (_) async => const CaptionAudioResult(
        outputPath: '/tmp/captions.m4a',
        durationSeconds: 1.0,
        hasSound: true,
      ),
    ).run(const CaptionRequest(), onProgress: (_, __) {});
    expect(drafts.single.end, const Duration(milliseconds: 1000));
  });

  test('the chosen sound and language reach the steps that use them',
      () async {
    CaptionSource? rendered;
    String? sent = 'unset';
    await pipeline(
      render: (source) async {
        rendered = source;
        return sound;
      },
      start: (language) async {
        sent = language;
        return job;
      },
    ).run(
      const CaptionRequest(source: CaptionSource.tracks, language: 'yo'),
      onProgress: (_, __) {},
    );
    expect(rendered, CaptionSource.tracks);
    expect(sent, 'yo');
  });

  test('nothing to hear stops before any upload', () async {
    await expectLater(
      pipeline(
        render: (_) async => const CaptionAudioResult(
          outputPath: '',
          durationSeconds: 0,
          hasSound: false,
        ),
      ).run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(
        isA<CaptionFailure>()
            .having((e) => e.code, 'code', CaptionFailure.noSound),
      ),
    );
    expect(keys, isEmpty);
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('no words is No speech found', () async {
    await expectLater(
      pipeline(
        transcript: (_) async => const CaptionTranscript(text: '', words: []),
      ).run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(
        isA<CaptionFailure>()
            .having((e) => e.code, 'code', CaptionFailure.noSpeech),
      ),
    );
  });

  test('a cancel while listening ends in CaptionCancelled and places nothing',
      () async {
    late CaptionPipeline p;
    p = pipeline(transcript: (isCancelled) async {
      p.cancel();
      expect(isCancelled(), isTrue);
      return hello;
    });
    await expectLater(
      p.run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<CaptionCancelled>()),
    );
    expect(cancels, 1);
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('a render stopped natively is a cancel', () async {
    await expectLater(
      pipeline(render: (_) async => throw const CaptionAudioCancelled())
          .run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<CaptionCancelled>()),
    );
  });

  test('Try again after an upload that never landed reuses its key', () async {
    var attempts = 0;
    final p = pipeline(start: (_) async {
      if (attempts++ == 0) {
        throw const SlimshotApiException(SlimshotApiException.network);
      }
      return job;
    });
    await expectLater(
      p.run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<SlimshotApiException>()),
    );
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    expect(keys, ['key-1', 'key-1']);
  });

  test('Try again after the server had the job takes a new key', () async {
    var attempts = 0;
    final p = pipeline(transcript: (_) async {
      if (attempts++ == 0) {
        throw const SlimshotApiException('PROVIDER_FAILED');
      }
      return hello;
    });
    await expectLater(
      p.run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<SlimshotApiException>()),
    );
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    expect(keys, ['key-1', 'key-2']);
  });

  test('a finished run retires its key', () async {
    final p = pipeline();
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    expect(keys, ['key-1', 'key-2']);
  });
}
