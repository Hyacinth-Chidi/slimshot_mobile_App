import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/audio_tools/same_file.dart';

/// The gallery hands back a fresh copy of a video on every pick, often under
/// a new name, so "the same video again" is a question about the bytes.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('same_file_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File write(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  List<int> video(int seed, {int length = 300 * 1024}) =>
      List<int>.generate(length, (i) => (i * 31 + seed) % 256);

  test('one path is the same file', () async {
    final a = write('a.mp4', video(1));
    expect(await isSameFile(a.path, a.path), isTrue);
  });

  test('a copy under another name is the same file', () async {
    final a = write('a.mp4', video(1));
    final b = write('image_picker_123.mp4', video(1));
    expect(await isSameFile(a.path, b.path), isTrue);
  });

  test('a different length is a different file', () async {
    final a = write('a.mp4', video(1));
    final b = write('b.mp4', video(1, length: 300 * 1024 + 1));
    expect(await isSameFile(a.path, b.path), isFalse);
  });

  test('the same length with different bytes is a different file', () async {
    final a = write('a.mp4', video(1));
    final b = write('b.mp4', video(2));
    expect(await isSameFile(a.path, b.path), isFalse);
  });

  test('a difference near the end is found', () async {
    final bytes = video(1);
    final a = write('a.mp4', bytes);
    final changed = [...bytes]..[bytes.length - 10] ^= 0xff;
    final b = write('b.mp4', changed);
    expect(await isSameFile(a.path, b.path), isFalse);
  });

  test('a file that is not there is not the same', () async {
    final a = write('a.mp4', video(1));
    expect(await isSameFile(a.path, '${dir.path}/gone.mp4'), isFalse);
  });

  test('small files are compared whole', () async {
    final a = write('a.mp4', [1, 2, 3]);
    final b = write('b.mp4', [1, 2, 3]);
    final c = write('c.mp4', [1, 2, 4]);
    expect(await isSameFile(a.path, b.path), isTrue);
    expect(await isSameFile(a.path, c.path), isFalse);
  });
}
