import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/utils/file_utils.dart';

/// The app's temporary files — compressions, stripped photos, exports — are
/// of no use once off screen. They go when their result is left, and what a
/// previous session left behind goes at the next launch.
void main() {
  late Directory temp;
  late Directory elsewhere;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('file_utils_temp');
    elsewhere = await Directory.systemTemp.createTemp('file_utils_gallery');
  });

  tearDown(() async {
    for (final dir in [temp, elsewhere]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  final launch = DateTime.now().subtract(const Duration(minutes: 1));
  final lastSession = DateTime.now().subtract(const Duration(hours: 2));

  File make(String path, {DateTime? modified}) {
    final file = File(path)..createSync(recursive: true);
    file.writeAsBytesSync([1, 2, 3]);
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  group('the launch', () {
    test('clears what the previous session left: compressions, stripped '
        'photos, exports and the share sheet copies', () async {
      final left = [
        make('${temp.path}/slimshot_temp_0b1c.mp4', modified: lastSession),
        make('${temp.path}/slimshot_temp_photo_9a.jpg',
            modified: lastSession),
        make('${temp.path}/slimshot_export_1793141004000.mp4',
            modified: lastSession),
        make('${temp.path}/share_plus/SlimShot_Video_1.mp4',
            modified: lastSession),
      ];
      // Twenty minutes old: the rule is "before this launch", not "an hour".
      final recent = make('${temp.path}/slimshot_temp_recent.jpg',
          modified: DateTime.now().subtract(const Duration(minutes: 20)));
      await FileUtils.cleanupStartup(launchedAt: launch, tempDir: temp);
      for (final file in [...left, recent]) {
        expect(file.existsSync(), isFalse, reason: file.path);
      }
    });

    test('keeps a file written since it began', () async {
      final current = make('${temp.path}/slimshot_temp_now.mp4');
      await FileUtils.cleanupStartup(launchedAt: launch, tempDir: temp);
      expect(current.existsSync(), isTrue);
    });

    test('leaves alone what is not the app\'s own: picked media a draft may '
        'be playing from', () async {
      final picked = make('${temp.path}/3f2a/VID_20261028.mp4',
          modified: lastSession);
      final other = make('${temp.path}/notes.txt', modified: lastSession);
      await FileUtils.cleanupStartup(launchedAt: launch, tempDir: temp);
      expect(picked.existsSync(), isTrue);
      expect(other.existsSync(), isTrue);
    });
  });

  group('deleting a result', () {
    test('deletes the files inside the temporary folder', () async {
      final output = make('${temp.path}/slimshot_temp_out.mp4');
      final picked = make('${temp.path}/3f2a/VID_20261028.mp4');
      await FileUtils.deleteTempFiles([output.path, picked.path],
          tempDir: temp);
      expect(output.existsSync(), isFalse);
      expect(picked.existsSync(), isFalse);
      expect(Directory('${temp.path}/3f2a').existsSync(), isFalse,
          reason: "a picked copy's own folder goes with it");
      expect(temp.existsSync(), isTrue);
    });

    test('never touches a file outside it — the user\'s own photo or video',
        () async {
      final gallery = make('${elsewhere.path}/IMG_0001.jpg');
      final escaping = make('${elsewhere.path}/VID_0002.mp4');
      final relative =
          '${temp.path}/../${elsewhere.uri.pathSegments.where((s) => s.isNotEmpty).last}/VID_0002.mp4';
      await FileUtils.deleteTempFiles([gallery.path, relative], tempDir: temp);
      expect(gallery.existsSync(), isTrue);
      expect(escaping.existsSync(), isTrue);
    });

    test('a file already gone is no error', () async {
      await FileUtils.deleteTempFiles(['${temp.path}/slimshot_temp_gone.mp4'],
          tempDir: temp);
    });
  });

  test('Clear Cache takes the exports and the share sheet copies too',
      () async {
    final export = make('${temp.path}/slimshot_export_1.mp4');
    final shared = make('${temp.path}/share_plus/SlimShot_Image_1.jpg');
    final compressed = make('${temp.path}/slimshot_temp_out.jpg');
    final picked = make('${temp.path}/3f2a/VID_20261028.mp4');
    expect(await FileUtils.clearCache(tempDir: temp), 3);
    expect(export.existsSync(), isFalse);
    expect(shared.existsSync(), isFalse);
    expect(compressed.existsSync(), isFalse);
    expect(picked.existsSync(), isTrue,
        reason: 'a draft may be playing from it');
  });
}
