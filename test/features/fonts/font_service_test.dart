import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimshotai/features/fonts/data/font_catalog_cache.dart';
import 'package:slimshotai/features/fonts/data/font_client.dart';
import 'package:slimshotai/features/fonts/data/font_library.dart';
import 'package:slimshotai/features/fonts/data/font_models.dart';
import 'package:slimshotai/features/fonts/font_registry.dart';
import 'package:slimshotai/features/fonts/font_service.dart';

import 'support.dart';

void main() {
  late Directory root;
  late FakeFontServer server;
  late List<String> registered;
  late FontLibrary library;
  late FontCatalogCache cache;
  late FontRegistry registry;
  late FontService service;

  setUp(() {
    root = Directory.systemTemp.createTempSync('font_service_test');
    server = FakeFontServer();
    registered = [];
    library = FontLibrary(client: server.client, root: root);
    cache = FontCatalogCache(root: root);
    registry = FontRegistry(loader: (bytes, name) async => registered.add(name));
    service = FontService(
      client: FontClient(server.api()),
      library: library,
      cache: cache,
      registry: registry,
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> saveLists() => cache.save(SavedFontList(
        fonts: parseServerFonts(server.fonts),
        fetchedAt: DateTime.now(),
      ));

  test('a local name needs nothing', () async {
    expect(await service.ensureAvailable('Montserrat Bold'), FontAvailability.available);
    expect(await service.ensureAvailable('Roboto'), FontAvailability.available);
    expect(server.totalHits, 0);
  });

  test('a font on the phone is registered without a request', () async {
    final font = ServerFont.tryParse(fontRow('pd', 'Playfair Display'))!;
    await library.download(font, FontDownloadTicket.tryParse({
      'url': 'https://cdn.test/fonts/pd-v1.ttf', 'format': 'ttf', 'version': 1,
    })!);
    server.hits.clear();
    final fresh = FontService(
      client: FontClient(server.api()),
      library: FontLibrary(client: server.client, root: root),
      cache: cache,
      registry: registry,
    );
    expect(await fresh.ensureAvailable('Playfair Display'), FontAvailability.available);
    expect(server.totalHits, 0);
    expect(registered, ['Playfair Display']);
  });

  test('a font in the saved lists is downloaded by its id', () async {
    await saveLists();
    expect(await service.ensureAvailable('Lato Bold'), FontAvailability.available);
    expect(server.hitsFor('download:lb'), 1);
    expect(server.hitsFor('file:lb'), 1);
    expect(server.hitsFor('family:Lato Bold'), 0);
    expect(registered, ['Lato Bold']);
    expect(library.find('Lato Bold')?.id, 'lb');
  });

  test('otherwise the family lookup finds a Regular face', () async {
    expect(await service.ensureAvailable('Righteous'), FontAvailability.available);
    expect(server.hitsFor('family:Righteous'), 1);
    expect(server.hitsFor('download:rg'), 1);
    expect(registered, ['Righteous']);
  });

  test('a family lookup that answers another face is refused', () async {
    server.overrides['family:Lato Bold'] =
        () => FakeFontServer.ok(fontRow('lr', 'Lato Bold Display'));
    expect(await service.ensureAvailable('Lato Bold'), FontAvailability.failed);
    expect(server.hitsFor('download:lr'), 0);
    expect(registered, isEmpty);
  });

  test('a font the server does not have fails quietly', () async {
    expect(await service.ensureAvailable('Comic Sans'), FontAvailability.failed);
    expect(registered, isEmpty);
  });

  test('no connection answers offline and throws nothing', () async {
    await saveLists();
    server.overrides['file:pd'] = () => throw http.ClientException('no route');
    expect(await service.ensureAvailable('Playfair Display'), FontAvailability.offline);
    expect(registered, isEmpty);
  });

  test('two calls for one name share one download', () async {
    await saveLists();
    final gate = server.gates['file:pd'] = Completer<void>();
    final first = service.ensureAvailable('Playfair Display');
    final second = service.ensureAvailable('Playfair Display');
    gate.complete();
    expect(await Future.wait([first, second]), [FontAvailability.available, FontAvailability.available]);
    expect(server.hitsFor('download:pd'), 1);
    expect(registered, ['Playfair Display']);
  });

  test('progress is reported while a font downloads', () async {
    await saveLists();
    final progress = <double>[];
    await service.ensureAvailable('Playfair Display', onProgress: progress.add);
    expect(progress.last, 1.0);
  });

  test('a higher version is downloaded, an equal one is not', () async {
    await saveLists();
    await service.ensureAvailable('Playfair Display');
    server.hits.clear();
    await service.updateOutdated(parseServerFonts([fontRow('pd', 'Playfair Display')]));
    expect(server.hitsFor('download:pd'), 0);
    server.fonts[0] = fontRow('pd', 'Playfair Display', version: 2);
    await service.updateOutdated(parseServerFonts(server.fonts));
    expect(server.hitsFor('download:pd'), 1);
    expect(library.find('Playfair Display')?.version, 2);
  });

  test('an updated font already registered this session is not registered again', () async {
    await saveLists();
    await service.ensureAvailable('Playfair Display');
    server.fonts[0] = fontRow('pd', 'Playfair Display', version: 2);
    await service.updateOutdated(parseServerFonts(server.fonts));
    expect(registered, ['Playfair Display']);
  });

  test('prefetch makes each name available and survives failures', () async {
    await service.prefetch(['Righteous', 'Comic Sans', 'Poppins']);
    expect(registry.isAvailable('Righteous'), isTrue);
    expect(registry.isAvailable('Comic Sans'), isFalse);
    expect(server.hitsFor('family:Poppins'), 0);
  });

  test('a font on the phone the engine refuses is fetched again', () async {
    final font = ServerFont.tryParse(fontRow('pd', 'Playfair Display'))!;
    await library.download(font, FontDownloadTicket.tryParse({
      'url': 'https://cdn.test/fonts/pd-v1.ttf', 'format': 'ttf', 'version': 1,
    })!);
    server.hits.clear();
    var refuse = true;
    final fresh = FontService(
      client: FontClient(server.api()),
      library: library,
      cache: cache,
      registry: FontRegistry(loader: (bytes, name) async {
        if (refuse) {
          refuse = false;
          throw Exception('not a font');
        }
        registered.add(name);
      }),
    );
    expect(await fresh.ensureAvailable('Playfair Display'), FontAvailability.available);
    expect(server.hitsFor('file:pd'), 1);
    expect(registered, ['Playfair Display']);
  });
}
