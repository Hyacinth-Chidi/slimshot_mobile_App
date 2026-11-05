import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/camera/logic/camera_files.dart';

void main() {
  late Directory root;
  late CameraFiles files;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('camera_files_test');
    files = CameraFiles(Directory('${root.path}/camera'));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('a new shot is named for its kind and moment, in the camera folder', () async {
    final photo = await files.newShotPath('jpg', now: DateTime(2026, 11, 5, 9, 7, 3, 42));
    final video = await files.newShotPath('mp4', now: DateTime(2026, 11, 5, 9, 7, 3, 42));
    expect(File(photo).parent.path, files.directory.path);
    expect(photo.split('/').last, 'IMG_20261105_090703_042.jpg');
    expect(video.split('/').last, 'VID_20261105_090703_042.mp4');
    expect(await files.directory.exists(), isTrue, reason: 'made on first use');
  });

  test('two shots in one millisecond never share a name', () async {
    final moment = DateTime(2026, 11, 5, 9, 7, 3, 42);
    final first = await files.newShotPath('jpg', now: moment);
    await File(first).writeAsString('a');
    final second = await files.newShotPath('jpg', now: moment);
    expect(second, isNot(first));
  });

  test('deletes only what is inside the camera folder', () async {
    final shot = File(await files.newShotPath('jpg'));
    await shot.writeAsString('shot');
    final outside = File('${root.path}/user.jpg');
    await outside.writeAsString('mine');
    final sneaky = '${files.directory.path}/../user.jpg';

    await files.delete([shot.path, outside.path, sneaky]);

    expect(await shot.exists(), isFalse);
    expect(await outside.exists(), isTrue, reason: 'a file outside is the user\'s');
  });

  test('the sweep keeps what a draft points at and what is newer than the launch', () async {
    final kept = File(await files.newShotPath('mp4', now: DateTime(2026, 1, 1)));
    await kept.writeAsString('edited');
    final orphan = File(await files.newShotPath('jpg', now: DateTime(2026, 1, 2)));
    await orphan.writeAsString('left behind');
    final launch = DateTime.now().add(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final fresh = File(await files.newShotPath('jpg'));
    await fresh.writeAsString('taken while the sweep ran');

    await files.sweep(keep: (path) => path == kept.path, before: launch);

    expect(await kept.exists(), isTrue);
    expect(await orphan.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
  });

  test('a sweep of a folder never made does nothing', () async {
    await files.sweep(keep: (_) => false, before: DateTime.now());
    expect(await files.directory.exists(), isFalse);
  });
}
