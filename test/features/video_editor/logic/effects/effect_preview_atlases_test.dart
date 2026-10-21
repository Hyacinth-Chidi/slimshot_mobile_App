import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_preview_atlases.dart';
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
}
