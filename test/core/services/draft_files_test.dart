import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/draft_files.dart';

/// A draft owns its files, and they go when it does.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('draft_files_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('the proxies folder is created under the draft, on demand', () async {
    final dir = await DraftFiles.proxiesDir('d1', root: root);
    expect(dir.existsSync(), isTrue);
    expect(dir.path.replaceAll('\\', '/'), endsWith('/drafts/d1/proxies'));
  });

  test('deleteAll removes the folder and the files named for the draft, nothing else',
      () async {
    final proxies = await DraftFiles.proxiesDir('d1', root: root);
    File('${proxies.path}/reverse_1.mp4').writeAsBytesSync([1]);
    File('${root.path}/cover_d1_5.jpg').writeAsBytesSync([1]);
    File('${root.path}/freeze_d1_6.jpg').writeAsBytesSync([1]);
    File('${root.path}/bg_d1_7.png').writeAsBytesSync([1]);
    // Another draft, a look-alike id, and an unrelated file all stay.
    await DraftFiles.proxiesDir('d10', root: root);
    File('${root.path}/cover_d10_5.jpg').writeAsBytesSync([1]);
    File('${root.path}/notes_d1_.txt').writeAsBytesSync([1]);

    await DraftFiles.deleteAll('d1', root: root);

    expect(Directory('${root.path}/drafts/d1').existsSync(), isFalse);
    expect(File('${root.path}/cover_d1_5.jpg').existsSync(), isFalse);
    expect(File('${root.path}/freeze_d1_6.jpg').existsSync(), isFalse);
    expect(File('${root.path}/bg_d1_7.png').existsSync(), isFalse);
    expect(Directory('${root.path}/drafts/d10').existsSync(), isTrue);
    expect(File('${root.path}/cover_d10_5.jpg').existsSync(), isTrue);
    expect(File('${root.path}/notes_d1_.txt').existsSync(), isTrue);
  });

  test('deleteAll on a draft with no files is not an error', () async {
    await DraftFiles.deleteAll('nobody', root: root);
  });

  test('exists is false for null and for a path to nothing', () {
    expect(DraftFiles.exists(null), isFalse);
    expect(DraftFiles.exists('${root.path}/absent.mp4'), isFalse);
    final f = File('${root.path}/here.mp4')..writeAsBytesSync([1]);
    expect(DraftFiles.exists(f.path), isTrue);
  });
}
