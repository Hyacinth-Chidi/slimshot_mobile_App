import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimshotai/features/fonts/data/font_catalog_cache.dart';
import 'package:slimshotai/features/fonts/data/font_client.dart';
import 'package:slimshotai/features/fonts/data/font_library.dart';
import 'package:slimshotai/features/fonts/data/font_models.dart';
import 'package:slimshotai/features/fonts/data/font_preview_cache.dart';
import 'package:slimshotai/features/fonts/font_grid.dart';
import 'package:slimshotai/features/fonts/font_registry.dart';
import 'package:slimshotai/features/fonts/font_service.dart';

import 'support.dart';

void main() {
  group('the grid', () {
    test('System, the bundled fonts, Trending, then More fonts', () {
      final entries = fontGridEntries(
        trending: parseServerFonts([fontRow('pd', 'Playfair Display'), fontRow('lb', 'Lato', style: 'Bold')]),
        more: parseServerFonts([fontRow('rg', 'Righteous')]),
      );
      expect(entries.map((e) => e.label),
          ['SYSTEM', 'Montserrat Bold', 'Bebas Neue', 'Poppins', 'Playfair Display', 'Lato Bold', 'Righteous']);
      expect(entries.first.name, 'Roboto');
      expect(entries.first.source, FontSource.system);
      expect(entries[1].source, FontSource.bundled);
      expect(entries[4].source, FontSource.server);
      expect(entries[4].font?.id, 'pd');
    });

    test('a server font named like a local one is left out', () {
      final entries = fontGridEntries(
        trending: parseServerFonts([
          fontRow('bn', 'bebas neue'),
          fontRow('mb', 'Montserrat', style: 'Bold'),
          fontRow('rb', 'Roboto'),
          fontRow('pd', 'Playfair Display'),
        ]),
        more: const [],
      );
      expect(entries.where((e) => e.source == FontSource.server).map((e) => e.font!.id), ['pd']);
    });

    test('a font in both lists shows once, first place', () {
      final entries = fontGridEntries(
        trending: parseServerFonts([fontRow('pd', 'Playfair Display')]),
        more: parseServerFonts([fontRow('pd2', 'playfair display'), fontRow('rg', 'Righteous')]),
      );
      expect(entries.where((e) => e.source == FontSource.server).map((e) => e.font!.id), ['pd', 'rg']);
    });

    test('search ignores case, spaces, dashes and underscores', () {
      final entries = fontGridEntries(
        trending: parseServerFonts([fontRow('pd', 'Playfair Display'), fontRow('rg', 'Righteous')]),
        more: const [],
      );
      expect(filterFontEntries(entries, 'playfair-display').map((e) => e.label), ['Playfair Display']);
      expect(filterFontEntries(entries, 'BEBAS_neue').map((e) => e.label), ['Bebas Neue']);
      expect(filterFontEntries(entries, '  ').length, entries.length);
      expect(filterFontEntries(entries, 'zzz'), isEmpty);
    });
  });

  group('the controller', () {
    late Directory root;
    late FakeFontServer server;
    late DateTime clock;
    late List<String> registered;
    late FontLibrary library;
    late FontCatalogCache cache;
    late FontGridController controller;

    FontGridController build({bool configured = true}) {
      final client = FontClient(server.api());
      return FontGridController(
        service: FontService(
          client: client,
          library: library,
          cache: cache,
          registry: FontRegistry(loader: (bytes, name) async => registered.add(name)),
        ),
        client: client,
        cache: cache,
        library: library,
        previews: FontPreviewCache(client: server.client, root: root),
        serverConfigured: configured,
        now: () => clock,
      );
    }

    setUp(() {
      root = Directory.systemTemp.createTempSync('font_grid_test');
      server = FakeFontServer();
      clock = DateTime.utc(2026, 10, 22, 12);
      registered = [];
      library = FontLibrary(client: server.client, root: root);
      cache = FontCatalogCache(root: root);
      controller = build();
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    List<String> labels() => controller.entries.map((e) => e.label).toList();
    FontEntry entry(String label) => controller.entries.firstWhere((e) => e.label == label);

    test('the saved lists show at once, then the server\'s', () async {
      await cache.save(SavedFontLists(
        trending: parseServerFonts([fontRow('old', 'Oswald')]),
        more: const [],
        fetchedAt: clock.subtract(const Duration(hours: 1)),
      ));
      final gate = server.gates['fonts:trending'] = Completer<void>();
      final opening = controller.open();
      for (var i = 0; i < 20 && !labels().contains('Oswald'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(labels(), contains('Oswald'));
      gate.complete();
      await opening;
      expect(labels(), isNot(contains('Oswald')));
      expect(labels(), containsAllInOrder(['Playfair Display', 'Lato Bold', 'Righteous']));
      expect((await cache.load())!.fetchedAt, clock);
    });

    test('a list under five minutes old is not fetched again', () async {
      await controller.open();
      expect(server.hitsFor('fonts:trending'), 1);
      clock = clock.add(const Duration(minutes: 4));
      await build().open();
      expect(server.hitsFor('fonts:trending'), 1);
      clock = clock.add(const Duration(minutes: 2));
      await build().open();
      expect(server.hitsFor('fonts:trending'), 2);
    });

    test('a missing More fonts category leaves Trending', () async {
      server.lists.remove('more-fonts');
      await controller.open();
      expect(labels(), containsAllInOrder(['Playfair Display', 'Lato Bold']));
      expect(labels(), isNot(contains('Righteous')));
      expect(controller.takeNotice(), isNull);
    });

    test('a rate-limited list keeps the saved one and waits', () async {
      await controller.open();
      server.overrides['fonts:trending'] =
          () => FakeFontServer.error('RATE_LIMITED', 429, details: {'retryAfterSeconds': 30});
      await controller.refresh();
      expect(labels(), contains('Playfair Display'));
      expect(server.hitsFor('fonts:trending'), 2);
      clock = clock.add(const Duration(seconds: 10));
      await controller.refresh();
      expect(server.hitsFor('fonts:trending'), 2);
      clock = clock.add(const Duration(seconds: 21));
      await controller.refresh();
      expect(server.hitsFor('fonts:trending'), 3);
    });

    test('with no server address it lists local fonts and asks nothing', () async {
      final local = build(configured: false);
      await local.open();
      await local.refresh();
      expect(local.entries.map((e) => e.label), ['SYSTEM', 'Montserrat Bold', 'Bebas Neue', 'Poppins']);
      expect(server.totalHits, 0);
      expect(local.takeNotice(), isNull);
    });

    test('choosing a font on the phone applies it at once', () async {
      await controller.open();
      final applied = <String>[];
      await controller.choose(entry('Bebas Neue'), applied.add);
      expect(applied, ['Bebas Neue']);
      expect(server.hitsFor('download:bn'), 0);
    });

    test('choosing one not on the phone shows progress, then applies it', () async {
      await controller.open();
      expect(controller.stateOf(entry('Playfair Display')), isA<FontNotOnPhone>());
      final gate = server.gates['file:pd'] = Completer<void>();
      final applied = <String>[];
      final choosing = controller.choose(entry('Playfair Display'), applied.add);
      for (var i = 0; i < 20 && controller.stateOf(entry('Playfair Display')) is! FontDownloading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(controller.stateOf(entry('Playfair Display')), isA<FontDownloading>());
      expect(applied, isEmpty);
      gate.complete();
      await choosing;
      expect(applied, ['Playfair Display']);
      expect(controller.stateOf(entry('Playfair Display')), isA<FontReady>());
      expect(registered, ['Playfair Display']);
    });

    test('the last choice wins', () async {
      await controller.open();
      final gate = server.gates['file:pd'] = Completer<void>();
      final applied = <String>[];
      final first = controller.choose(entry('Playfair Display'), applied.add);
      await controller.choose(entry('Poppins'), applied.add);
      gate.complete();
      await first;
      expect(applied, ['Poppins']);
      expect(controller.stateOf(entry('Playfair Display')), isA<FontReady>());
    });

    test('a font that lands after the controller is disposed applies nothing', () async {
      await controller.open();
      final gate = server.gates['file:pd'] = Completer<void>();
      final applied = <String>[];
      final choosing = controller.choose(entry('Playfair Display'), applied.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.dispose();
      gate.complete();
      await choosing;
      expect(applied, isEmpty);
    });

    test('no connection: "No internet connection", and the tile keeps its arrow', () async {
      await controller.open();
      server.overrides['file:pd'] = () => throw http.ClientException('no route');
      final applied = <String>[];
      await controller.choose(entry('Playfair Display'), applied.add);
      expect(applied, isEmpty);
      expect(controller.stateOf(entry('Playfair Display')), isA<FontFailed>());
      expect(controller.takeNotice(), 'No internet connection');
      expect(controller.takeNotice(), isNull);
    });

    test("any other failure: \"Couldn't download this font\"", () async {
      await controller.open();
      server.overrides['download:pd'] = () => FakeFontServer.error('FORBIDDEN', 403);
      await controller.choose(entry('Playfair Display'), (_) {});
      expect(controller.takeNotice(), "Couldn't download this font");
    });
  });
}
