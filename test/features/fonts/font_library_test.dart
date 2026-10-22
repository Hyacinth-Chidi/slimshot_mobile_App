import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/features/fonts/data/font_library.dart';
import 'package:slimshotai/features/fonts/data/font_models.dart';

import 'support.dart';

void main() {
  late Directory root;
  late FakeFontServer server;

  setUp(() {
    root = Directory.systemTemp.createTempSync('font_library_test');
    server = FakeFontServer();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  ServerFont font(String id, String family, {String style = 'Regular', int version = 1}) =>
      ServerFont.tryParse(fontRow(id, family, style: style, version: version))!;

  FontDownloadTicket ticket(String id, {int version = 1}) => FontDownloadTicket(
        url: 'https://cdn.test/fonts/$id-v$version.ttf',
        filename: '$id.ttf',
        format: 'ttf',
        byteSize: 4,
        version: version,
      );

  File fileIn(String name) => File('${root.path}/font_library/$name');

  test('a download lands as a file and an index entry', () async {
    final library = FontLibrary(client: server.client, root: root);
    final entry = await library.download(font('lb', 'Lato', style: 'Bold'), ticket('lb'));
    expect(fileIn('lb-v1.ttf').existsSync(), isTrue);
    expect(entry.filePath, fileIn('lb-v1.ttf').path);
    expect(library.find('Lato Bold')?.id, 'lb');
    expect(library.find('lato bold')?.id, 'lb');
    expect(library.find('Lato Bold')?.version, 1);
  });

  test('a new instance on the same folder finds it', () async {
    await FontLibrary(client: server.client, root: root)
        .download(font('pd', 'Playfair Display'), ticket('pd'));
    final again = FontLibrary(client: server.client, root: root);
    await again.load();
    expect(again.find('Playfair Display')?.displayName, 'Playfair Display');
  });

  test('a half-written file is never taken for a font', () async {
    Directory('${root.path}/font_library').createSync(recursive: true);
    fileIn('pd-v1.part').writeAsBytesSync([0, 1]);
    final library = FontLibrary(client: server.client, root: root);
    expect(await library.load(), isEmpty);
    expect(library.find('Playfair Display'), isNull);
  });

  test('an entry whose file is gone is dropped', () async {
    await FontLibrary(client: server.client, root: root)
        .download(font('pd', 'Playfair Display'), ticket('pd'));
    fileIn('pd-v1.ttf').deleteSync();
    final again = FontLibrary(client: server.client, root: root);
    await again.load();
    expect(again.find('Playfair Display'), isNull);
  });

  test('two downloads of one font share one request', () async {
    final library = FontLibrary(client: server.client, root: root);
    final gate = server.gates['file:pd'] = Completer<void>();
    final first = library.download(font('pd', 'Playfair Display'), ticket('pd'));
    final second = library.download(font('pd', 'Playfair Display'), ticket('pd'));
    gate.complete();
    await Future.wait([first, second]);
    expect(server.hitsFor('file:pd'), 1);
  });

  test('a higher version replaces the entry and removes the old file', () async {
    final library = FontLibrary(client: server.client, root: root);
    await library.download(font('pd', 'Playfair Display'), ticket('pd'));
    await library.download(font('pd', 'Playfair Display', version: 2), ticket('pd', version: 2));
    expect(fileIn('pd-v2.ttf').existsSync(), isTrue);
    expect(fileIn('pd-v1.ttf').existsSync(), isFalse);
    expect(library.find('Playfair Display')?.version, 2);
    expect((await library.load()).where((e) => e.id == 'pd'), hasLength(1));
  });

  test('no connection is an offline failure', () async {
    final library = FontLibrary(
      client: MockClient((_) async => throw http.ClientException('no route')),
      root: root,
    );
    await expectLater(
      library.download(font('pd', 'Playfair Display'), ticket('pd')),
      throwsA(isA<FontDownloadFailed>().having((e) => e.offline, 'offline', isTrue)),
    );
    expect(fileIn('pd-v1.part').existsSync(), isFalse);
    expect(library.find('Playfair Display'), isNull);
  });

  // A captive-portal Wi-Fi answers any address with its own page, 200 OK.
  test('a body that is not a font is refused and leaves nothing', () async {
    server.overrides['file:pd'] = () => http.Response('<html>Sign in to the Wi-Fi</html>', 200);
    final library = FontLibrary(client: server.client, root: root);
    await expectLater(
      library.download(font('pd', 'Playfair Display'), ticket('pd')),
      throwsA(isA<FontDownloadFailed>()),
    );
    expect(library.find('Playfair Display'), isNull);
    expect(fileIn('pd-v1.ttf').existsSync(), isFalse);
    expect(fileIn('pd.part').existsSync(), isFalse);
  });
}
