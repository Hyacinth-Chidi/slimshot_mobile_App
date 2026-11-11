import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/draft_files.dart';
import 'package:slimshotai/features/video_editor/logic/speech/voice_clip.dart';

/// A voice Text to speech made is replaced on the timeline at once, but its
/// file is kept until the editor closes — Undo brings the clip back, and it
/// must still play. At close, a voice file no track uses goes.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('draft_voices_'));
  tearDown(() => root.deleteSync(recursive: true));

  test("a replaced voice's file is kept until the editor closes", () async {
    final audio = await DraftFiles.audioDir('d1', root: root);
    File file(String name) => File('${audio.path}/$name')..writeAsBytesSync([1]);
    final used = file('tts_text_1_200.mp3');
    final replaced = file('tts_text_1_100.mp3');
    final halfDownloaded = file('tts_text_2_300.mp3.part');
    // Other tools' sound in the same folder: a recorded take is `voice_…`.
    final take = file('voice_1700000000000.m4a');
    final extracted = file('extract_1700000000000.m4a');

    // Until the editor closes, Undo may still want the replaced file.
    expect(replaced.existsSync(), isTrue);

    await DraftFiles.sweepVoices('d1', keep: {used.path}, root: root);

    expect(used.existsSync(), isTrue);
    expect(replaced.existsSync(), isFalse);
    expect(halfDownloaded.existsSync(), isFalse);
    expect(take.existsSync(), isTrue, reason: 'only voices from text are swept');
    expect(extracted.existsSync(), isTrue);
  });

  test("a voice's file is named for its text, as one the sweep takes", () async {
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000005);
    expect(voiceFileName('text_1', at), 'tts_text_1_1700000000005.mp3');
    // A text id is the app's own, but a file name cannot carry just anything.
    expect(voiceFileName('a/b c:d', at), 'tts_a_b_c_d_1700000000005.mp3');
    expect(voiceFileName('x' * 200, at).length, lessThan(100));

    final audio = await DraftFiles.audioDir('d1', root: root);
    final orphan = File('${audio.path}/${voiceFileName('t', at)}')
      ..writeAsBytesSync([1]);
    await DraftFiles.sweepVoices('d1', keep: const {}, root: root);
    expect(orphan.existsSync(), isFalse);
  });

  test('a path written with other separators still keeps its file', () async {
    final audio = await DraftFiles.audioDir('d1', root: root);
    final used = File('${audio.path}/tts_a_1.mp3')..writeAsBytesSync([1]);

    await DraftFiles.sweepVoices(
      'd1',
      keep: {used.path.replaceAll('\\', '/')},
      root: root,
    );
    expect(used.existsSync(), isTrue);
  });

  test('a draft with no audio folder is nothing to sweep', () async {
    await DraftFiles.sweepVoices('none', keep: const {}, root: root);
    expect(Directory('${root.path}/drafts/none').existsSync(), isFalse);
  });
}
