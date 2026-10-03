import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';
import 'package:slimshotai/features/video_editor/services/text_atlas_overlay.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';

import '../../../support/test_fonts.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async =>
      (await Directory.systemTemp.createTemp('caption_atlas_test_')).path;
}

/// The export's half of the word highlight: what the atlas stores and what
/// the timeline sends the engine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  const canvas = Size(400, 700);
  const red = Color(0xFFFF0000);

  TextOverlayModel caption({
    CaptionHighlightStyle style = CaptionHighlightStyle.colour,
    Color background = Colors.transparent,
  }) =>
      TextOverlayModel(
        id: 'c',
        text: 'aaaa bbbb',
        fontFamily: kTestFontFamily,
        referenceCanvasSize: canvas,
        color: Colors.white,
        backgroundColor: background,
        startTime: const Duration(seconds: 1),
        endTime: const Duration(seconds: 3),
        captionSetId: 's',
        captionWords: const [
          CaptionWord(
            textStart: 0,
            textEnd: 4,
            start: Duration(milliseconds: 100),
            end: Duration(milliseconds: 500),
          ),
          CaptionWord(
            textStart: 5,
            textEnd: 9,
            start: Duration(milliseconds: 600),
            end: Duration(milliseconds: 1000),
          ),
        ],
        highlight: CaptionHighlight(style: style, color: red),
      );

  Future<RasterizedTextAtlas> atlasOf(TextOverlayModel overlay) async =>
      (await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlay,
        canvasSize: canvas,
        rasterScale: 1,
      ))!;

  Future<({ByteData data, int width})> pixels(String path) async {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
    final image = (await codec.getNextFrame()).image;
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final width = image.width;
    image.dispose();
    return (data: data, width: width);
  }

  int countIn(({ByteData data, int width}) img, Rect cell, bool Function(int r, int g, int b, int a) test) {
    var n = 0;
    for (var y = cell.top.ceil(); y < cell.bottom.floor(); y++) {
      for (var x = cell.left.ceil(); x < cell.right.floor(); x++) {
        final o = (y * img.width + x) * 4;
        if (test(img.data.getUint8(o), img.data.getUint8(o + 1), img.data.getUint8(o + 2),
            img.data.getUint8(o + 3))) {
          n++;
        }
      }
    }
    return n;
  }

  bool isRed(int r, int g, int b, int a) => a > 200 && r > 200 && g < 80 && b < 80;
  bool isBlack(int r, int g, int b, int a) => a > 200 && r < 40 && g < 40 && b < 40;

  group('the atlas', () {
    test('a lit cell for every glyph, in the highlight colour, and each glyph knows its word', () async {
      final atlas = await atlasOf(caption());
      expect(atlas.glyphs.map((g) => g.word), [0, 0, 0, 0, 1, 1, 1, 1]);
      expect(atlas.glyphs.every((g) => g.litAtlasRect != null), isTrue);
      final img = await pixels(atlas.pngPath);
      for (final g in atlas.glyphs) {
        expect(countIn(img, g.litAtlasRect!, isRed), greaterThan(0));
        expect(countIn(img, g.atlasRect, isRed), 0);
        expect(g.litAtlasRect!.size, g.atlasRect.size);
      }
    });

    test('pill: a pill cell per word in the highlight colour, and no lit cells', () async {
      final atlas = await atlasOf(caption(style: CaptionHighlightStyle.pill));
      expect(atlas.glyphs.every((g) => g.litAtlasRect == null), isTrue);
      expect(atlas.pills, hasLength(2));
      final img = await pixels(atlas.pngPath);
      for (final pill in atlas.pills) {
        expect(countIn(img, pill!.atlasRect, isRed), greaterThan(100));
      }
      expect(atlas.pills[0]!.boxRect.right, lessThan(atlas.pills[1]!.boxRect.right));
    });

    test('reveal and focus need no second look', () async {
      for (final style in [CaptionHighlightStyle.reveal, CaptionHighlightStyle.focus]) {
        final atlas = await atlasOf(caption(style: style));
        expect(atlas.glyphs.every((g) => g.litAtlasRect == null), isTrue, reason: style.name);
        expect(atlas.pills, isEmpty, reason: style.name);
        expect(atlas.highlight, isNotNull, reason: style.name);
      }
    });

    test('a boxed text stores its box as a cell of its own', () async {
      final atlas = await atlasOf(caption(background: Colors.black));
      expect(atlas.background, isNotNull);
      expect(atlas.background!.boxRect, atlas.backgroundRect);
      final img = await pixels(atlas.pngPath);
      final cell = atlas.background!.atlasRect.deflate(4);
      expect(countIn(img, cell, isBlack), greaterThan((cell.width * cell.height * 0.9).floor()));
    });

    test('plain text stores nothing new', () async {
      final plain = caption().copyWith(highlight: CaptionHighlight.none, clearCaption: true);
      final atlas = await atlasOf(plain);
      expect(atlas.glyphs.every((g) => g.litAtlasRect == null && g.word == -1), isTrue);
      expect(atlas.pills, isEmpty);
      expect(atlas.background, isNull);
      expect(atlas.highlight, isNull);
    });

    test('no two cells touch: a gutter keeps a solid cell out of its neighbour', () async {
      // The GPU samples a cell's edge between two texels, so a pill or box
      // cell packed flush against a glyph cell would draw a faint line of its
      // colour along that glyph's edge.
      final atlas = await atlasOf(caption(background: Colors.black));
      final pill = await atlasOf(caption(style: CaptionHighlightStyle.pill, background: Colors.black));
      for (final a in [atlas, pill]) {
        final cells = [
          for (final g in a.glyphs) g.atlasRect,
          for (final g in a.glyphs)
            if (g.litAtlasRect != null) g.litAtlasRect!,
          for (final p in a.pills)
            if (p != null) p.atlasRect,
          if (a.background != null) a.background!.atlasRect,
        ];
        for (var i = 0; i < cells.length; i++) {
          for (var j = i + 1; j < cells.length; j++) {
            const reach = kAtlasCellGapPx / 2 - 0.01;
            expect(cells[i].inflate(reach).overlaps(cells[j].inflate(reach)), isFalse, reason: '$i/$j');
          }
        }
      }
    });
  });

  group('on the wire', () {
    test('a plain glyph writes exactly the keys it always did', () {
      const glyph = EditorTimelineGlyph(
        atlasLeft: 0, atlasTop: 0, atlasRight: 1, atlasBottom: 1,
        boxLeft: 0, boxTop: 0, boxRight: 1, boxBottom: 1,
        srcLeft: 0, srcTop: 0, srcRight: 1, srcBottom: 1,
      );
      expect(glyph.toJson().keys.toSet(), {
        'atlasLeft', 'atlasTop', 'atlasRight', 'atlasBottom',
        'boxLeft', 'boxTop', 'boxRight', 'boxBottom',
        'srcLeft', 'srcTop', 'srcRight', 'srcBottom',
      });
    });

    test('a highlighted glyph carries its lit cell and its word, in atlas fractions', () async {
      final atlas = await atlasOf(caption());
      final glyphs = glyphsForAtlas(atlas);
      final first = glyphs.first.toJson();
      expect(first['word'], 0);
      expect(first['litAtlasLeft'], closeTo(atlas.glyphs.first.litAtlasRect!.left / atlas.atlasPxSize.width, 1e-9));
      expect(first['litAtlasBottom'], closeTo(atlas.glyphs.first.litAtlasRect!.bottom / atlas.atlasPxSize.height, 1e-9));
    });

    test('the highlight: style, times in seconds, words and pills in fractions', () async {
      final atlas = await atlasOf(caption(style: CaptionHighlightStyle.pill));
      final h = highlightForAtlas(atlas)!.toJson();
      expect(h['style'], 'pill');
      final words = (h['words'] as List).cast<Map<String, dynamic>>();
      expect(words, hasLength(2));
      expect(words[0]['start'], closeTo(0.1, 1e-9));
      expect(words[1]['end'], closeTo(1.0, 1e-9));
      expect(words[0]['rtl'], isFalse);
      final box = atlas.highlight!.wordBoxes[0]!;
      expect(words[0]['left'], closeTo(box.left / atlas.canvasPxSize.width, 1e-9));
      expect(words[0]['pillAtlasLeft'], closeTo(atlas.pills[0]!.atlasRect.left / atlas.atlasPxSize.width, 1e-9));
      expect(words[0]['pillLeft'], closeTo(atlas.pills[0]!.boxRect.left / atlas.canvasPxSize.width, 1e-9));
    });

    test('no highlight, no key; no box cell, no key', () async {
      final plain = caption().copyWith(highlight: CaptionHighlight.none, clearCaption: true);
      final atlas = await atlasOf(plain);
      expect(highlightForAtlas(atlas), isNull);
      expect(backgroundAtlasFor(atlas), isNull);
    });
  });

  group('the export', () {
    const channel = MethodChannel('slimshot_ai/native_timeline_preview');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<Map<String, dynamic>> sent;

    setUp(() {
      sent = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'exportVideo') {
          final timeline = (call.arguments as Map)['timeline'] as Map;
          sent.addAll([
            for (final o in timeline['overlays'] as List) Map<String, dynamic>.from(o as Map),
          ]);
          return {'outputPath': '/tmp/o.mp4', 'durationSeconds': 5.0, 'frameCount': 1, 'degradedTransitions': 0};
        }
        return null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<List<String>> export(TextOverlayModel text) async {
      final warnings = <String>[];
      await NativeTimelinePreviewService(fontsReady: () async {}).exportVideo(
        VideoEditorState(
          assets: const [
            MediaAsset(
              id: 'a',
              path: '/v.mp4',
              type: MediaAssetType.video,
              durationSeconds: 10,
              width: 1080,
              height: 1920,
              hasAudio: true,
            ),
          ],
          segments: [VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5)],
          textOverlays: [text],
        ),
        outputPath: '/tmp/o.mp4',
        previewCanvasSize: canvas,
        onWarning: warnings.add,
      );
      return warnings;
    }

    test('a boxed text now takes the atlas, its box drawn as one quad', () async {
      final warnings = await export(
        caption(background: Colors.black).copyWith(inAnimation: 'typing'),
      );
      final text = sent.single;
      expect(text['kind'], 'text');
      expect(text['backgroundAtlasLeft'], isA<double>());
      expect(warnings, isEmpty, reason: 'nothing falls back any more');
    });

    test('a highlighted caption sends its highlight', () async {
      await export(caption(style: CaptionHighlightStyle.karaoke));
      final text = sent.single;
      expect(text['kind'], 'text');
      final h = text['highlight'] as Map;
      expect(h['style'], 'karaoke');
      expect((h['words'] as List), hasLength(2));
    });

    test('plain text sends no new keys', () async {
      await export(caption().copyWith(highlight: CaptionHighlight.none, clearCaption: true));
      final text = sent.single;
      expect(text.containsKey('highlight'), isFalse);
      expect(text.containsKey('backgroundAtlasLeft'), isFalse);
      for (final g in (text['glyphs'] as List).cast<Map>()) {
        expect(g.containsKey('word'), isFalse);
        expect(g.containsKey('litAtlasLeft'), isFalse);
      }
    });
  });
}
