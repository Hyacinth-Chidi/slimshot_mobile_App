import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_preview_atlases.dart';
import 'package:slimshotai/features/video_editor/logic/tile_preview_store.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';
import 'package:slimshotai/features/video_editor/providers/effect_preview_provider.dart';

/// The session's effect preview atlases: drawn one at a time, shared while
/// drawing, failures remembered and a busy engine not, and asks nobody wants
/// any more dropped before they start.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> rendered;
  late Map<String, Completer<EffectPreviewResult>> pending;

  Future<EffectPreviewResult> render(EditorTimelineEffect bar) {
    rendered.add(bar.effectId);
    return (pending[bar.effectId] = Completer<EffectPreviewResult>()).future;
  }

  setUp(() {
    rendered = [];
    pending = {};
  });

  Uint8List bytes(int n) => Uint8List.fromList([n]);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('one drawing at a time', () async {
    final atlases = EffectPreviewAtlases(render);
    atlases.request('vignette');
    atlases.request('grain');
    await settle();
    expect(rendered, ['vignette']);
    pending['vignette']!.complete(EffectPreviewAtlas(bytes(1)));
    await settle();
    expect(rendered, ['vignette', 'grain']);
  });

  test('the sample bar is what is drawn', () async {
    final atlases = EffectPreviewAtlases((bar) {
      expect(bar.id, 'preview_vignette');
      expect(bar.end, 3.0);
      return Future.value(EffectPreviewAtlas(bytes(1)));
    });
    expect(await atlases.request('vignette').atlas, bytes(1));
  });

  test('a second ask shares the first', () async {
    final atlases = EffectPreviewAtlases(render);
    final a = atlases.request('vignette');
    final b = atlases.request('vignette');
    await settle();
    pending['vignette']!.complete(EffectPreviewAtlas(bytes(7)));
    expect(await a.atlas, bytes(7));
    expect(await b.atlas, bytes(7));
    expect(rendered, ['vignette']);
  });

  test('an atlas is kept for the session', () async {
    final atlases = EffectPreviewAtlases(render);
    final first = atlases.request('vignette');
    await settle();
    pending['vignette']!.complete(EffectPreviewAtlas(bytes(3)));
    await first.atlas;
    expect(atlases.peek('vignette'), bytes(3));
    expect(await atlases.request('vignette').atlas, bytes(3));
    expect(rendered, ['vignette']);
  });

  test('failed is remembered', () async {
    final atlases = EffectPreviewAtlases(render);
    final first = atlases.request('vignette');
    await settle();
    pending['vignette']!.complete(const EffectPreviewFailed());
    expect(await first.atlas, isNull);
    expect(atlases.hasFailed('vignette'), isTrue);
    expect(await atlases.request('vignette').atlas, isNull);
    expect(rendered, ['vignette']);
  });

  test('busy is not remembered', () async {
    final atlases = EffectPreviewAtlases(render);
    final first = atlases.request('vignette');
    await settle();
    pending['vignette']!.complete(const EffectPreviewBusy());
    expect(await first.atlas, isNull);
    expect(atlases.hasFailed('vignette'), isFalse);
    atlases.request('vignette');
    await settle();
    expect(rendered, ['vignette', 'vignette']);
  });

  test('a timeout counts as busy and lets the next ask start', () async {
    final atlases = EffectPreviewAtlases(
      render,
      timeout: const Duration(milliseconds: 30),
    );
    final stuck = atlases.request('vignette');
    atlases.request('grain');
    expect(await stuck.atlas, isNull);
    expect(atlases.hasFailed('vignette'), isFalse);
    await settle();
    expect(rendered, ['vignette', 'grain']);
    // The lost answer arriving late changes nothing.
    pending['vignette']!.complete(EffectPreviewAtlas(bytes(9)));
    await settle();
    expect(atlases.peek('vignette'), isNull);
  });

  test('withdrawn asks are dropped', () async {
    final atlases = EffectPreviewAtlases(render);
    atlases.request('vignette');
    final grain = atlases.request('grain');
    await settle();
    grain.withdraw();
    pending['vignette']!.complete(EffectPreviewAtlas(bytes(1)));
    await settle();
    await settle();
    expect(rendered, ['vignette']);
    expect(await grain.atlas, isNull);
  });

  test('a withdrawn ask still kept by another ticket is drawn', () async {
    final atlases = EffectPreviewAtlases(render);
    atlases.request('vignette');
    final one = atlases.request('grain');
    final two = atlases.request('grain');
    await settle();
    one.withdraw();
    pending['vignette']!.complete(EffectPreviewAtlas(bytes(1)));
    await settle();
    expect(rendered, ['vignette', 'grain']);
    pending['grain']!.complete(EffectPreviewAtlas(bytes(2)));
    expect(await two.atlas, bytes(2));
  });

  test('an unknown effect fails without drawing', () async {
    final atlases = EffectPreviewAtlases(render);
    expect(await atlases.request('from_the_future').atlas, isNull);
    expect(atlases.hasFailed('from_the_future'), isTrue);
    expect(rendered, isEmpty);
  });

  test('clear drops bytes and keeps failures', () async {
    final atlases = EffectPreviewAtlases(render);
    final a = atlases.request('vignette');
    await settle();
    pending['vignette']!.complete(EffectPreviewAtlas(bytes(1)));
    await a.atlas;
    final b = atlases.request('grain');
    await settle();
    pending['grain']!.complete(const EffectPreviewFailed());
    await b.atlas;
    atlases.clear();
    expect(atlases.peek('vignette'), isNull);
    expect(atlases.hasFailed('grain'), isTrue);
  });

  test('a renderer that throws counts as busy', () async {
    final atlases = EffectPreviewAtlases((_) async => throw StateError('x'));
    expect(await atlases.request('vignette').atlas, isNull);
    expect(atlases.hasFailed('vignette'), isFalse);
  });

  test('memory pressure clears the session atlases', () async {
    final container = ProviderContainer(overrides: [
      effectPreviewRendererProvider
          .overrideWithValue((_) async => EffectPreviewAtlas(bytes(5))),
    ]);
    addTearDown(container.dispose);
    final atlases = container.read(effectPreviewAtlasesProvider);
    await atlases.request('vignette').atlas;
    expect(atlases.peek('vignette'), isNotNull);
    TestWidgetsFlutterBinding.instance.handleMemoryPressure();
    expect(atlases.peek('vignette'), isNull);
  });

  test('a disposed provider stops listening for memory pressure', () async {
    final container = ProviderContainer(overrides: [
      effectPreviewRendererProvider
          .overrideWithValue((_) async => EffectPreviewAtlas(bytes(5))),
    ]);
    final atlases = container.read(effectPreviewAtlasesProvider);
    await atlases.request('vignette').atlas;
    container.dispose();
    TestWidgetsFlutterBinding.instance.handleMemoryPressure();
    expect(atlases.peek('vignette'), isNotNull);
  });

  // Drawn once per build of the app, not once per launch: the icon a tile
  // shows while the engine draws it is then seen the first time only.
  group('kept on the phone', () {
    late Directory support;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('effect_atlases_test');
    });

    tearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });

    TilePreviewStore store() => TilePreviewStore(
          version: () async => '7-100',
          supportDirectory: () async => support,
        );

    // An atlas is a JPEG: it opens on FF D8 and closes on FF D9.
    Uint8List jpeg(int n) => Uint8List.fromList([0xFF, 0xD8, n, 0xFF, 0xD9]);

    // Reading a real file takes real time; wait for what follows it.
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('an atlas drawn once is kept, and the next launch shows it without '
        'drawing', () async {
      final firstStore = store();
      final first = EffectPreviewAtlases(render, store: firstStore);
      final ticket = first.request('vignette');
      await settle();
      pending['vignette']!.complete(EffectPreviewAtlas(jpeg(1)));
      await ticket.atlas;
      await firstStore.flush();

      final nextStore = store();
      await nextStore.prepare();
      rendered.clear();
      final next = EffectPreviewAtlases(render, store: nextStore);
      expect(next.isSaved('vignette'), isTrue);
      expect(next.isSaved('grain'), isFalse);
      expect(await next.request('vignette').atlas, jpeg(1));
      expect(next.peek('vignette'), jpeg(1));
      expect(rendered, isEmpty);
    });

    test('a failed or busy effect is not kept', () async {
      final firstStore = store();
      final atlases = EffectPreviewAtlases(render, store: firstStore);
      final failed = atlases.request('vignette');
      final busy = atlases.request('grain');
      await settle();
      pending['vignette']!.complete(const EffectPreviewFailed());
      await failed.atlas;
      await settle();
      pending['grain']!.complete(const EffectPreviewBusy());
      await busy.atlas;
      await firstStore.flush();

      final nextStore = store();
      await nextStore.prepare();
      final next = EffectPreviewAtlases(render, store: nextStore);
      expect(next.isSaved('vignette'), isFalse,
          reason: 'the next launch tries again');
      expect(next.isSaved('grain'), isFalse);
    });

    test('an atlas on the phone is not kept waiting behind a drawing',
        () async {
      final kept = store();
      await kept.write(TilePreviewKind.effects, 'vignette', jpeg(2));
      await kept.flush();
      final atlases = EffectPreviewAtlases(render, store: kept);
      atlases.request('grain');
      await settle();
      expect(await atlases.request('vignette').atlas, jpeg(2));
      expect(rendered, ['grain']);
      pending['grain']!.complete(const EffectPreviewBusy());
    });

    test('a kept atlas that is not a picture is drawn again, and kept anew',
        () async {
      final kept = store();
      await kept.write(
          TilePreviewKind.effects, 'vignette', Uint8List.fromList([1, 2, 3]));
      await kept.flush();
      final atlases = EffectPreviewAtlases(render, store: kept);
      final ticket = atlases.request('vignette');
      await until(() => pending.containsKey('vignette'));
      pending['vignette']!.complete(EffectPreviewAtlas(jpeg(3)));
      expect(await ticket.atlas, jpeg(3));
      await kept.flush();

      final nextStore = store();
      await nextStore.prepare();
      expect(
        await EffectPreviewAtlases(render, store: nextStore)
            .request('vignette')
            .atlas,
        jpeg(3),
      );
    });

    test('after memory pressure an atlas comes back from the phone, not the '
        'engine', () async {
      final kept = store();
      final atlases = EffectPreviewAtlases(render, store: kept);
      final first = atlases.request('vignette');
      await settle();
      pending['vignette']!.complete(EffectPreviewAtlas(jpeg(4)));
      await first.atlas;
      await kept.flush();
      atlases.clear();
      rendered.clear();
      expect(atlases.peek('vignette'), isNull);
      expect(await atlases.request('vignette').atlas, jpeg(4));
      expect(rendered, isEmpty);
    });
  });
}
