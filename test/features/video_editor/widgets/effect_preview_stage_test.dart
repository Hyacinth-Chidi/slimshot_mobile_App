import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_preview_atlases.dart';
import 'package:slimshotai/features/video_editor/logic/tile_preview_store.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/effect_preview_stage.dart';

import '../../../support/memory_tile_store.dart';

/// A tile's stage decodes and **owns** its picture: a decode that lands after
/// the tile is gone, or for an effect the tile no longer shows, disposes what
/// it got — pictures outliving their tiles is exactly the leak the one-image
/// atlas exists to prevent.
void main() {
  late List<String> rendered;
  late Map<String, Completer<EffectPreviewResult>> pending;
  late EffectPreviewAtlases atlases;
  late List<Completer<ui.Image>> decodes;
  late ValueNotifier<int> frameIndex;

  Future<EffectPreviewResult> render(EditorTimelineEffect bar) {
    rendered.add(bar.effectId);
    return (pending[bar.effectId] = Completer<EffectPreviewResult>()).future;
  }

  setUp(() {
    rendered = [];
    pending = {};
    atlases = EffectPreviewAtlases(render);
    decodes = [];
    frameIndex = ValueNotifier<int>(0);
  });

  tearDown(() => frameIndex.dispose());

  Future<ui.Image> fakeDecode(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    decodes.add(completer);
    return completer.future;
  }

  Future<ui.Image> makeImage(WidgetTester tester) async {
    late ui.Image image;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 800, 720),
        Paint()..color = const Color(0xFF123456),
      );
      final picture = recorder.endRecording();
      image = await picture.toImage(800, 720);
      picture.dispose();
    });
    return image;
  }

  Widget stage({String effectId = 'vignette'}) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 90,
            child: EffectPreviewStage(
              effectId: effectId,
              icon: LucideIcons.circleDot,
              isSelected: false,
              atlases: atlases,
              frameIndex: frameIndex,
              decode: fakeDecode,
            ),
          ),
        ),
      );

  Uint8List bytes(int n) => Uint8List.fromList([n]);

  Future<void> cacheAtlas(String effectId) async {
    final ticket = atlases.request(effectId);
    await null;
    pending[effectId]!.complete(EffectPreviewAtlas(bytes(1)));
    await ticket.atlas;
  }

  EffectPreviewPainter painterOf(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<EffectPreviewPainter>()
      .single;

  testWidgets('the icon shows while there is no atlas', (tester) async {
    await tester.pumpWidget(stage());
    expect(find.byIcon(LucideIcons.circleDot), findsOneWidget);
    // The drawing left in flight holds the cache's timeout timer; answer it,
    // or the test ends with a pending timer.
    pending['vignette']!.complete(const EffectPreviewBusy());
    await tester.pump();
  });

  testWidgets('the icon shows for a failed effect', (tester) async {
    final first = atlases.request('vignette');
    await null;
    pending['vignette']!.complete(const EffectPreviewFailed());
    await first.atlas;
    await tester.pumpWidget(stage());
    await tester.pump();
    expect(find.byIcon(LucideIcons.circleDot), findsOneWidget);
    expect(decodes, isEmpty);
  });

  testWidgets('the stage is empty, not the icon, while cached bytes decode',
      (tester) async {
    await cacheAtlas('vignette');
    await tester.pumpWidget(stage());
    expect(decodes, hasLength(1));
    expect(find.byIcon(LucideIcons.circleDot), findsNothing);
  });

  testWidgets('a decoded atlas paints, repainting on the frame index',
      (tester) async {
    await cacheAtlas('vignette');
    await tester.pumpWidget(stage());
    final image = await makeImage(tester);
    decodes.single.complete(image);
    await tester.pump();
    await tester.pump();
    final painter = painterOf(tester);
    expect(identical(painter.image, image), isTrue);
    expect(identical(painter.frameIndex, frameIndex), isTrue);
    expect(painter.shouldRepaint(EffectPreviewPainter(image, frameIndex)),
        isFalse);
  });

  // An atlas is a JPEG: it opens on FF D8 and closes on FF D9.
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 9, 0xFF, 0xD9]);

  /// How present the painted picture is: the product of every fade above it.
  double pictureOpacity(WidgetTester tester) => tester
      .widgetList<FadeTransition>(find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is EffectPreviewPainter,
        ),
        matching: find.byType(FadeTransition),
      ))
      .fold(1.0, (opacity, fade) => opacity * fade.opacity.value);

  // Kept on the phone from an earlier launch: the icon is for an effect the
  // engine has yet to draw, and this one needs no drawing.
  testWidgets('a kept effect shows the bare stage, never the icon, while it '
      'is read back', (tester) async {
    final store = MemoryTileStore()
      ..saved[TilePreviewKind.effects]!['vignette'] = jpeg;
    atlases = EffectPreviewAtlases(render, store: store);
    await tester.pumpWidget(stage());
    expect(find.byIcon(LucideIcons.circleDot), findsNothing);
    await tester.pump();
    expect(find.byIcon(LucideIcons.circleDot), findsNothing);
    expect(rendered, isEmpty, reason: 'read back, not drawn');
    expect(decodes, hasLength(1));
  });

  testWidgets('a picture read back appears at once, not faded in',
      (tester) async {
    final store = MemoryTileStore()
      ..saved[TilePreviewKind.effects]!['vignette'] = jpeg;
    atlases = EffectPreviewAtlases(render, store: store);
    await tester.pumpWidget(stage());
    await tester.pump();
    decodes.single.complete(await makeImage(tester));
    await tester.pump();
    await tester.pump();
    expect(painterOf(tester), isNotNull);
    expect(pictureOpacity(tester), 1.0);
  });

  // Drawn by the engine for the first time: the picture fades in over the
  // icon that stood in for it, rather than switching in.
  testWidgets('a picture drawn for the first time fades in over its icon',
      (tester) async {
    await tester.pumpWidget(stage());
    expect(find.byIcon(LucideIcons.circleDot), findsOneWidget);
    pending['vignette']!.complete(EffectPreviewAtlas(bytes(1)));
    await tester.pump();
    decodes.single.complete(await makeImage(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byIcon(LucideIcons.circleDot), findsOneWidget,
        reason: 'fading out under the picture');
    expect(pictureOpacity(tester), inExclusiveRange(0.0, 1.0));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byIcon(LucideIcons.circleDot), findsNothing);
    expect(pictureOpacity(tester), 1.0);
  });

  testWidgets('a decode landing after dispose disposes its image',
      (tester) async {
    await cacheAtlas('vignette');
    await tester.pumpWidget(stage());
    expect(decodes, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    final image = await makeImage(tester);
    decodes.single.complete(image);
    await tester.pump();
    expect(image.debugDisposed, isTrue);
  });

  testWidgets('a decode for a replaced effect disposes the stale image',
      (tester) async {
    await cacheAtlas('vignette');
    await cacheAtlas('grain');
    await tester.pumpWidget(stage());
    expect(decodes, hasLength(1));
    await tester.pumpWidget(stage(effectId: 'grain'));
    final stale = await makeImage(tester);
    final fresh = await makeImage(tester);
    decodes[0].complete(stale);
    decodes[1].complete(fresh);
    await tester.pump();
    await tester.pump();
    expect(stale.debugDisposed, isTrue);
    expect(fresh.debugDisposed, isFalse);
    expect(identical(painterOf(tester).image, fresh), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dispose disposes the painted image', (tester) async {
    await cacheAtlas('vignette');
    await tester.pumpWidget(stage());
    final image = await makeImage(tester);
    decodes.single.complete(image);
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(image.debugDisposed, isTrue);
  });

  testWidgets('dispose withdraws the ticket', (tester) async {
    // The engine is busy with another effect, so the tile's ask is queued —
    // and withdrawn with the tile, so it is never drawn for nobody.
    atlases.request('vignette');
    await tester.pumpWidget(stage(effectId: 'grain'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending['vignette']!.complete(EffectPreviewAtlas(bytes(1)));
    await tester.pump();
    await tester.pump();
    expect(rendered, ['vignette']);
  });

  testWidgets('a tile keeps painting after the cache is cleared',
      (tester) async {
    await cacheAtlas('vignette');
    await tester.pumpWidget(stage());
    final image = await makeImage(tester);
    decodes.single.complete(image);
    await tester.pump();
    await tester.pump();
    atlases.clear();
    await tester.pump();
    expect(image.debugDisposed, isFalse);
    expect(identical(painterOf(tester).image, image), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
