import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/sound_library/data/catalog_models.dart';
import 'package:slimshotai/features/sound_library/sound_effects_controller.dart';

import 'support.dart';

const _a = CatalogSound(id: 'a', title: 'Sound a', durationMs: 800);
const _b = CatalogSound(id: 'b', title: 'Sound b', durationMs: 800);

void main() {
  late Directory root;
  late ControllerHarness h;
  late SoundEffectsController c;
  late List<SoundSheetNotice> notices;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sfx_controller_test');
    h = ControllerHarness(root);
  });

  tearDown(() => deleteTemp(root));

  Future<SoundEffectsController> opened() async {
    c = h.build();
    notices = [];
    c.notices.listen(notices.add);
    await c.open();
    await settle();
    return c;
  }

  group('pills', () {
    test('pills are Downloaded then the server\'s order', () async {
      await opened();
      expect(c.pills, [kDownloadedPill, 'impacts', 'funny-memes']);
      expect(c.pillName(kDownloadedPill), 'Downloaded');
      expect(c.pillName('funny-memes'), 'Funny & Memes');
      expect(c.selected, 'impacts', reason: 'opens on the first server pill');
      expect(c.sounds.map((s) => s.id), ['a', 'b']);
    });

    test('cached rows show before the server answers', () async {
      await h.cache.saveCategories(const [
        CatalogCategory(id: '1', slug: 'impacts', name: 'Impacts'),
      ]);
      await h.cache.saveFirstPage('impacts', const [CatalogSound(id: 'old', title: 'Old')]);
      h.server.gates['categories'] = Completer();
      c = h.build();
      unawaited(c.open());
      await settle();
      expect(c.selected, 'impacts');
      expect(c.sounds.map((s) => s.id), ['old']);
      h.server.gates['categories']!.complete();
      await settle();
      expect(c.sounds.map((s) => s.id), ['a', 'b']);
    });

    test('offline keeps cached rows and says so', () async {
      await h.cache.saveCategories(const [
        CatalogCategory(id: '1', slug: 'impacts', name: 'Impacts'),
      ]);
      await h.cache.saveFirstPage('impacts', const [CatalogSound(id: 'old', title: 'Old')]);
      h.server.overrides['categories'] = () => throw const SocketException('down');
      h.server.overrides['assets:impacts:-'] = () => throw const SocketException('down');
      await opened();
      expect(c.offline, isTrue);
      expect(c.pills, [kDownloadedPill, 'impacts']);
      expect(c.sounds.map((s) => s.id), ['old']);
    });

    test('a missing root shows Downloaded only, no error', () async {
      h.server.overrides['categories'] =
          () => FakeCatalogServer.error('NOT_FOUND', 404);
      await opened();
      expect(c.pills, [kDownloadedPill]);
      expect(c.selected, kDownloadedPill);
      expect(c.offline, isFalse);
    });

    test('a vanished category falls back to Downloaded', () async {
      await opened();
      h.server.categories = [h.server.categories.last];
      h.server.pages.remove('impacts');
      await c.refresh();
      await settle();
      expect(c.pills, [kDownloadedPill, 'funny-memes']);
      expect(c.selected, kDownloadedPill);
    });

    test('rate limited waits before asking again', () async {
      h.server.overrides['categories'] = () => FakeCatalogServer.error(
            'RATE_LIMITED',
            429,
            details: {'retryAfterSeconds': 41},
          );
      await opened();
      final asked = h.server.hitsFor('categories');
      await c.select('impacts');
      await settle();
      expect(h.server.hitsFor('assets:impacts:-'), 0,
          reason: 'nothing automatic inside the window');
      h.server.overrides.remove('categories');
      await c.retry();
      await settle();
      expect(h.waits.single, const Duration(seconds: 41));
      expect(h.server.hitsFor('categories'), asked + 1);
    });
  });

  group('pages', () {
    test('stale page for a previous pill is dropped', () async {
      await opened();
      h.server.gates['assets:impacts:-'] = Completer();
      unawaited(c.select('impacts'));
      await settle();
      await c.select('funny-memes');
      await settle();
      h.server.gates['assets:impacts:-']!.complete();
      await settle();
      expect(c.selected, 'funny-memes');
      expect(c.sounds.map((s) => s.id), ['m']);
    });

    test('loadMore stops at a null cursor', () async {
      h.server.pages['impacts'] = [
        [soundRow('a'), soundRow('b')],
        [soundRow('c')],
      ];
      await opened();
      expect(c.hasMore, isTrue);
      await c.loadMore();
      await settle();
      expect(c.sounds.map((s) => s.id), ['a', 'b', 'c']);
      expect(c.hasMore, isFalse);
      await c.loadMore();
      await settle();
      expect(h.server.hitsFor('assets:impacts:1'), 1);
    });

    test('refresh during paging leaves no duplicate ids', () async {
      h.server.pages['impacts'] = [
        [soundRow('a'), soundRow('b')],
        [soundRow('b'), soundRow('c')],
      ];
      await opened();
      h.server.gates['assets:impacts:1'] = Completer();
      unawaited(c.loadMore());
      await settle();
      unawaited(c.refresh());
      await settle();
      h.server.gates['assets:impacts:1']!.complete();
      await settle();
      final ids = c.sounds.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('listening', () {
    test('tapping a row not in the library downloads then plays it', () async {
      await opened();
      await c.tapRow(_a);
      await settle();
      expect(c.inLibrary('a'), isTrue);
      expect(h.player.played.single, endsWith('a.mp3'));
      expect(c.playingId, 'a');
    });

    test('tapping it again stops it', () async {
      await opened();
      await c.tapRow(_a);
      await settle();
      await c.tapRow(_a);
      expect(c.playingId, isNull);
      expect(h.player.stops, greaterThan(0));
    });

    test('tapping another row mid-download keeps the first unplayed', () async {
      await opened();
      h.server.gates['file:a'] = Completer();
      unawaited(c.tapRow(_a));
      await settle();
      expect(c.progressOf('a'), isNotNull);
      await c.tapRow(_b);
      await settle();
      h.server.gates['file:a']!.complete();
      await settle();
      expect(c.inLibrary('a'), isTrue, reason: 'kept');
      expect(h.player.played.where((p) => p.endsWith('a.mp3')), isEmpty);
      expect(c.playingId, 'b');
    });

    test('a sound that plays to its end is no longer playing', () async {
      await opened();
      await c.tapRow(_a);
      await settle();
      expect(c.playingId, 'a');
      h.player.finish();
      await settle();
      expect(c.playingId, isNull);
    });

    test('a file that will not play is not left playing and throws nothing', () async {
      await opened();
      h.player.failPlays = true;
      await c.tapRow(_a);
      await settle();
      expect(c.playingId, isNull);
    });

    test('offline, a row not in the library does nothing', () async {
      h.server.overrides['categories'] = () => throw const SocketException('down');
      await opened();
      await c.tapRow(_a);
      await settle();
      expect(h.server.hitsFor('download:a'), 0);
      expect(h.player.played, isEmpty);
    });
  });

  group('adding', () {
    test('+ on a library sound adds without a request', () async {
      await opened();
      await c.tapRow(_a);
      await settle();
      final before = h.server.hitsFor('download:a');
      final added = await c.add(_a);
      expect(added?.id, 'a');
      expect(h.server.hitsFor('download:a'), before);
    });

    test('+ on a new sound downloads then returns it', () async {
      await opened();
      final added = await c.add(_b);
      expect(added?.id, 'b');
      expect(File(added!.filePath).existsSync(), isTrue);
      expect(added.durationMs, 800);
    });

    test('+ stops the preview', () async {
      await opened();
      await c.tapRow(_a);
      await settle();
      await c.add(_a);
      expect(c.playingId, isNull);
    });

    test('a listen then a + on one sound makes one download', () async {
      await opened();
      h.server.gates['file:a'] = Completer();
      unawaited(c.tapRow(_a));
      await settle();
      final adding = c.add(_a);
      await settle();
      h.server.gates['file:a']!.complete();
      final added = await adding;
      expect(added?.id, 'a');
      expect(h.server.hitsFor('download:a'), 1);
      expect(h.server.hitsFor('file:a'), 1);
    });

    test('a second + while adding is ignored', () async {
      await opened();
      h.server.gates['file:b'] = Completer();
      final first = c.add(_b);
      await settle();
      final second = await c.add(_b);
      h.server.gates['file:b']!.complete();
      expect(second, isNull);
      expect((await first)?.id, 'b');
    });

    test('+ when the sound was removed drops the row and says it failed', () async {
      await opened();
      h.server.overrides['download:a'] = () => FakeCatalogServer.error('NOT_FOUND', 404);
      expect(await c.add(_a), isNull);
      await settle();
      expect(c.sounds.map((s) => s.id), ['b']);
      expect(notices.single.kind, SoundSheetNoticeKind.downloadFailed);
      expect(notices.single.title, 'Sound a');
    });

    test('+ on a gated sound says it is unavailable', () async {
      await opened();
      h.server.overrides['download:a'] = () => FakeCatalogServer.error('FORBIDDEN', 403);
      expect(await c.add(_a), isNull);
      await settle();
      expect(notices.single.kind, SoundSheetNoticeKind.unavailable);
    });

    test('a zero duration is read from the file', () async {
      await opened();
      h.player.duration = 1.25;
      final added = await c.add(const CatalogSound(id: 'z', title: 'Zero'));
      expect(added?.durationMs, 0 + 800,
          reason: 'the ticket knew; the file is asked only when nobody did');
      h.server.overrides['download:y'] = () => FakeCatalogServer.ok({
            'url': 'https://cdn.test/audio/y.mp3',
            'filename': 'y.mp3',
            'format': 'mp3',
            'byteSize': 3,
            'durationMs': 0,
          });
      final unknown = await c.add(const CatalogSound(id: 'y', title: 'Unknown'));
      expect(unknown?.durationMs, 1250);
    });

    test('a file with no readable length is a failed add', () async {
      await opened();
      h.player.duration = null;
      h.server.overrides['download:y'] = () => FakeCatalogServer.ok({
            'url': 'https://cdn.test/audio/y.mp3',
            'filename': 'y.mp3',
            'format': 'mp3',
            'byteSize': 3,
            'durationMs': 0,
          });
      expect(await c.add(const CatalogSound(id: 'y', title: 'Unknown')), isNull);
      await settle();
      expect(notices.single.kind, SoundSheetNoticeKind.downloadFailed);
    });

    test('dispose during a download adds nothing and does not throw', () async {
      await opened();
      h.server.gates['file:b'] = Completer();
      final adding = c.add(_b);
      await settle();
      c.dispose();
      h.server.gates['file:b']!.complete();
      expect(await adding, isNull);
      await settle();
      expect(h.player.disposed, isTrue);
      expect(h.library.find('b'), isNotNull, reason: 'the file is kept');
    });
  });
}
