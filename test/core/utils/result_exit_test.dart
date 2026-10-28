import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/core/utils/result_exit.dart';

/// Leaving a finished result — a compression, a privacy strip, an export —
/// throws its files away; one nobody saved or shared is asked about first.
void main() {
  late List<String> deleted;
  late int asked;

  Future<void> delete(Iterable<String> paths) async => deleted.addAll(paths);

  setUp(() {
    deleted = [];
    asked = 0;
  });

  Future<bool> Function() answer(bool discard) => () async {
        asked++;
        return discard;
      };

  const outputs = ['/cache/slimshot_temp_a.mp4', '/cache/slimshot_temp_b.mp4'];
  const inputs = ['/cache/3f2a/VID_1.mp4', '/cache/3f2b/VID_2.mp4'];

  test('nothing kept: it asks, and staying keeps every file', () async {
    final exit = ResultExit(delete: delete);
    expect(
      await exit.leave(outputs: outputs, inputs: inputs, confirm: answer(false)),
      isFalse,
    );
    expect(asked, 1);
    expect(deleted, isEmpty);
  });

  test('nothing kept: discarding deletes the results, never the picked files',
      () async {
    final exit = ResultExit(delete: delete);
    expect(
      await exit.leave(outputs: outputs, inputs: inputs, confirm: answer(true)),
      isTrue,
    );
    await null;
    expect(deleted, outputs);
  });

  test('a result handed back as it was is the picked file, and stays for its '
      'own screen to clear', () async {
    final exit = ResultExit(delete: delete);
    await exit.leave(
      outputs: [inputs.first, outputs.first],
      inputs: inputs,
      confirm: answer(true),
    );
    await null;
    expect(deleted, [outputs.first]);
  });

  // A saved copy is in the gallery; a shared one, the share sheet copied
  // first — the app's own files are of no use either way.
  test('saved or shared: it leaves without asking, and the files still go',
      () async {
    final exit = ResultExit(delete: delete)..markKept();
    expect(
      await exit.leave(outputs: outputs, confirm: answer(false)),
      isTrue,
    );
    await null;
    expect(asked, 0);
    expect(deleted, outputs);
  });

  test('a second tap while it asks does nothing', () async {
    final exit = ResultExit(delete: delete);
    final question = Completer<bool>();
    final first = exit.leave(outputs: outputs, confirm: () {
      asked++;
      return question.future;
    });
    expect(await exit.leave(outputs: outputs, confirm: answer(true)), isFalse);
    expect(asked, 1);
    question.complete(false);
    expect(await first, isFalse);
    // Staying puts it back: the next tap asks again.
    expect(await exit.leave(outputs: outputs, confirm: answer(true)), isTrue);
    expect(asked, 2);
  });

  test('leaving does not wait for the files to go', () async {
    final never = Completer<void>();
    final exit = ResultExit(delete: (_) => never.future);
    expect(
      await exit.leave(outputs: outputs, confirm: answer(true)),
      isTrue,
    );
  });

  // A tap on the home screen widget only brings the app forward while a
  // result nobody kept is on screen, rather than throwing it away.
  test('a result holds the app until it is kept, or released', () {
    final held = HeldWork();
    final kept = ResultExit(delete: delete, held: held)..hold();
    final gone = ResultExit(delete: delete, held: held)..hold();
    expect(held.isHeld, isTrue);
    kept.markKept();
    expect(held.isHeld, isTrue);
    gone.release();
    expect(held.isHeld, isFalse);
  });

  test('a result already kept holds nothing', () {
    final held = HeldWork();
    ResultExit(delete: delete, held: held)
      ..markKept()
      ..hold();
    expect(held.isHeld, isFalse);
  });
}
