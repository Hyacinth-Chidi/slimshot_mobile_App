import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/features/sound_library/data/catalog_models.dart';
import 'package:slimshotai/features/sound_library/data/sound_library.dart';

import 'support.dart';

const _sound = CatalogSound(
  id: 'cm2a1',
  title: 'UI Button',
  durationMs: 412,
  categorySlug: 'ui',
  categoryName: 'UI',
  coverUrl: 'https://cdn.test/cover.png',
);

const _ticket = DownloadTicket(
  url: 'https://cdn.test/audio/0b6f.mp3',
  filename: 'ui-button.mp3',
  format: 'mp3',
  byteSize: 6,
  durationMs: 412,
);

void main() {
  late Directory root;
  late Map<String, int> hits;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sound_library_test');
    hits = {};
  });

  tearDown(() => deleteTemp(root));

  /// Serves the sound in two chunks and the cover as one; [sound] and
  /// [cover] replace either answer.
  http.Client server({
    Future<http.StreamedResponse> Function()? sound,
    Future<http.StreamedResponse> Function()? cover,
  }) =>
      MockClient.streaming((request, _) async {
        final url = request.url.toString();
        hits[url] = (hits[url] ?? 0) + 1;
        if (url == _ticket.url) {
          return sound != null
              ? sound()
              : http.StreamedResponse(
                  Stream.fromIterable([
                    [1, 2, 3],
                    [4, 5, 6],
                  ]),
                  200,
                  contentLength: 6,
                );
        }
        if (url == _sound.coverUrl) {
          return cover != null
              ? cover()
              : http.StreamedResponse(Stream.value([9, 9]), 200);
        }
        return http.StreamedResponse(const Stream.empty(), 404);
      });

  Directory folder() => Directory('${root.path}/sound_library');

  List<String> namesIn(Directory dir) => dir.existsSync()
      ? [for (final f in dir.listSync()) f.uri.pathSegments.last]
      : const [];

  test('a download writes the file and indexes it', () async {
    final library = SoundLibrary(client: server(), root: root);
    final entry = await library.download(_sound, _ticket);
    expect(File(entry.filePath).readAsBytesSync(), [1, 2, 3, 4, 5, 6]);
    expect(entry.filePath, endsWith('cm2a1.mp3'));
    expect(entry.title, 'UI Button');
    expect(entry.durationMs, 412);
    expect(entry.categorySlug, 'ui');
    expect(library.find('cm2a1')?.filePath, entry.filePath);
    expect(namesIn(folder()).where((n) => n.endsWith('.part')), isEmpty);
  });

  test('progress reports received over byteSize', () async {
    final library = SoundLibrary(client: server(), root: root);
    final progress = <double>[];
    await library.download(_sound, _ticket, onProgress: progress.add);
    expect(progress, isNotEmpty);
    expect(progress.first, closeTo(0.5, 1e-9));
    expect(progress.last, 1.0);
  });

  test('a failed stream leaves no file and no entry', () async {
    final library = SoundLibrary(
      client: server(
        sound: () async {
          final controller = StreamController<List<int>>();
          controller.add([1, 2, 3]);
          scheduleMicrotask(() {
            controller.addError(const SocketException('gone'));
            controller.close();
          });
          return http.StreamedResponse(controller.stream, 200, contentLength: 6);
        },
      ),
      root: root,
    );
    await expectLater(
      library.download(_sound, _ticket),
      throwsA(isA<SoundDownloadFailed>()),
    );
    expect(namesIn(folder()).where((n) => n.startsWith('cm2a1')), isEmpty);
    expect(library.find('cm2a1'), isNull);
  });

  test('a refused fetch leaves no file and no entry', () async {
    final library = SoundLibrary(
      client: server(
        sound: () async => http.StreamedResponse(const Stream.empty(), 403),
      ),
      root: root,
    );
    await expectLater(
      library.download(_sound, _ticket),
      throwsA(isA<SoundDownloadFailed>()),
    );
    expect(namesIn(folder()).where((n) => n.startsWith('cm2a1')), isEmpty);
  });

  test('two downloads of one id make one request', () async {
    final library = SoundLibrary(client: server(), root: root);
    final first = library.download(_sound, _ticket);
    final second = library.download(_sound, _ticket);
    final results = await Future.wait([first, second]);
    expect(hits[_ticket.url], 1);
    expect(results[0].filePath, results[1].filePath);
  });

  test('a cover that fails still downloads the sound', () async {
    final library = SoundLibrary(
      client: server(
        cover: () async => http.StreamedResponse(const Stream.empty(), 500),
      ),
      root: root,
    );
    final entry = await library.download(_sound, _ticket);
    expect(entry.coverPath, isNull);
    expect(library.find('cm2a1'), isNotNull);
  });

  test('a cover is kept beside the sound', () async {
    final library = SoundLibrary(client: server(), root: root);
    final entry = await library.download(_sound, _ticket);
    expect(File(entry.coverPath!).readAsBytesSync(), [9, 9]);
  });

  test('the index survives a reload', () async {
    await SoundLibrary(client: server(), root: root).download(_sound, _ticket);
    final reopened = SoundLibrary(client: server(), root: root);
    final sounds = await reopened.load();
    expect(sounds.single.id, 'cm2a1');
    expect(sounds.single.title, 'UI Button');
    expect(sounds.single.coverPath, isNotNull);
    expect(reopened.find('cm2a1'), isNotNull);
  });

  test('the newest download comes first', () async {
    final library = SoundLibrary(client: server(), root: root);
    await library.download(_sound, _ticket);
    const other = CatalogSound(id: 'b', title: 'Chime');
    final otherTicket = DownloadTicket(
      url: _ticket.url,
      filename: 'chime.wav',
      format: 'wav',
      byteSize: 6,
      durationMs: 0,
    );
    await library.download(other, otherTicket);
    expect((await library.load()).map((s) => s.id), ['b', 'cm2a1']);
  });

  test('an entry whose file is gone is dropped on load', () async {
    final entry =
        await SoundLibrary(client: server(), root: root).download(_sound, _ticket);
    File(entry.filePath).deleteSync();
    final reopened = SoundLibrary(client: server(), root: root);
    expect(await reopened.load(), isEmpty);
    expect(reopened.find('cm2a1'), isNull);
  });

  test('a corrupt index reads as empty', () async {
    folder().createSync(recursive: true);
    File('${folder().path}/library.json').writeAsStringSync('{not json');
    final library = SoundLibrary(client: server(), root: root);
    expect(await library.load(), isEmpty);
    // And the library still works after it.
    await library.download(_sound, _ticket);
    expect((await SoundLibrary(client: server(), root: root).load()).single.id,
        'cm2a1');
  });
}
