# Text Glyph Atlas (Stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export a text overlay as one quad **per glyph** instead of one flat quad, producing a pixel-identical file — the foundation per-character animation needs, with no animation yet.

**Architecture:** Flutter rasterises the text once into a sprite sheet (the atlas) plus a table of per-glyph source rects and layout rects. The timeline carries that table as a new `text` overlay kind. Kotlin draws one quad per glyph at an exact rect, rather than contain-fitting one image into a box. Because nothing animates yet, the reassembled glyphs must land exactly where the flat raster's pixels were — which is the acceptance gate for the whole stage.

**Tech Stack:** Flutter/Dart (`dart:ui`, `TextPainter`), Kotlin, OpenGL ES 2.0, Riverpod.

**Spec:** `docs/superpowers/specs/2026-09-11-text-animation-design.md`

## What this stage does NOT touch

**The canvas preview is unchanged.** `text_overlay_layer.dart` draws text as Flutter widgets
and always has — it never used a raster, so there is nothing to convert. The atlas exists for
the export, which cannot run Flutter's text engine per frame. Both sides still measure through
`TextOverlayLayout`, which is what keeps them agreeing.

Do not "unify" the preview onto the atlas. Drawing the preview from a raster would make text
editing round-trip through a PNG for every keystroke, and the widgets are already pixel-correct
because they come from the same engine.

Also untouched this stage: the animation tab, the Speed slider, the animation catalog, and
`NativeTimelineOverlay.stateAt` (whole-box animation keeps working exactly as it does today —
a glyph overlay inherits the same whole-box fade/slide until Stage 2 gives it per-glyph curves).

## Global Constraints

- **minSdk 24.** Probe capabilities at runtime; where a device refuses, degrade **loudly** (a user-visible `exportWarning` toast), never silently.
- **No device pixels in the timeline contract.** All overlay geometry is normalised to canvas fractions (0..1). See the overlay section of CLAUDE.md.
- **Preview and export must not duplicate a definition.** Anything that decides what text looks like lives in `logic/text_overlay_geometry.dart` and is read by both sides.
- **GLSL is compiled at runtime** — `flutter analyze` and `compileDebugKotlin` cannot catch a shader error. Device behaviour is the only real test of a shader change.
- **Max texture side is 4096px** on the oldest supported parts. `TextOverlayRasterizer.kMaxRasterSidePx` already encodes this.
- **Undo is manual:** call `saveStateForUndo()` before a structural edit; never per gesture frame.
- Verify with: `flutter analyze --no-pub`, `flutter test`, `.\android\gradlew.bat -p android compileDebugKotlin`.

---

### Task 1: Glyph table model and measurement

Produces the per-glyph geometry from Flutter's own text layout. No rendering yet — this task only answers "where is each character, and how big is it".

**Files:**
- Create: `lib/features/video_editor/logic/text_glyph_layout.dart`
- Test: `test/features/video_editor/logic/text_glyph_layout_test.dart`

**Interfaces:**
- Consumes: `TextOverlayLayout.measure(overlay, canvasSize)` from `logic/text_overlay_geometry.dart`, which returns `TextOverlayLayout` with fields `renderScale`, `boxSize`, `textWidth`, `textHeight`, `textOrigin` (an `Offset`), `hasBackground`, `outerPadding`, `backgroundPaddingH`, `backgroundPaddingV`. Also `TextOverlayLayout.textPainterFor(overlay, renderScale)` returning an unlaid `TextPainter`.
- Produces:
  - `class TextGlyphBox { final int charIndex; final Rect inkRect; final Rect paddedRect; }`
  - `List<TextGlyphBox> layoutTextGlyphs({required TextOverlayModel overlay, required Size canvasSize, required double shadowPadding})`
  - Rects are in **box-local pixels** (origin = the text box's top-left, the same space `TextOverlayLayout.textOrigin` lives in).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/video_editor/logic/text_glyph_layout_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_glyph_layout.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

void main() {
  TextOverlayModel overlayWith(String text) => TextOverlayModel(
        id: 't',
        text: text,
        referenceCanvasSize: const Size(400, 700),
      );

  group('layoutTextGlyphs', () {
    test('returns one box per character, in order', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.length, 3);
      expect(glyphs.map((g) => g.charIndex), [0, 1, 2]);
    });

    test('lays characters out left to right without overlapping', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs[0].inkRect.left, lessThan(glyphs[1].inkRect.left));
      expect(glyphs[1].inkRect.left, lessThan(glyphs[2].inkRect.left));
      // Adjacent glyphs may touch but must not overlap.
      expect(glyphs[0].inkRect.right, lessThanOrEqualTo(glyphs[1].inkRect.left + 0.01));
    });

    test('skips whitespace, which has no ink to draw', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('a b'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.map((g) => g.charIndex), [0, 2]);
    });

    test('a second line sits below the first', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('a\nb'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.length, 2);
      expect(glyphs[1].inkRect.top, greaterThan(glyphs[0].inkRect.bottom - 0.01));
    });

    test('padded rect grows by the shadow padding on every side', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('a'),
        canvasSize: const Size(400, 700),
        shadowPadding: 4,
      );
      final g = glyphs.single;
      expect(g.paddedRect.left, closeTo(g.inkRect.left - 4, 1e-9));
      expect(g.paddedRect.top, closeTo(g.inkRect.top - 4, 1e-9));
      expect(g.paddedRect.right, closeTo(g.inkRect.right + 4, 1e-9));
      expect(g.paddedRect.bottom, closeTo(g.inkRect.bottom + 4, 1e-9));
    });

    test('glyph boxes sit inside the measured text box', () {
      const canvas = Size(400, 700);
      final overlay = overlayWith('hello');
      final glyphs = layoutTextGlyphs(
        overlay: overlay,
        canvasSize: canvas,
        shadowPadding: 0,
      );
      for (final g in glyphs) {
        expect(g.inkRect.left, greaterThanOrEqualTo(-0.01));
        expect(g.inkRect.top, greaterThanOrEqualTo(-0.01));
      }
    });

    test('empty text produces no glyphs', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith(''),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/video_editor/logic/text_glyph_layout_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../text_glyph_layout.dart'`

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/video_editor/logic/text_glyph_layout.dart
import 'package:flutter/material.dart';

import '../models/text_overlay_model.dart';
import 'text_overlay_geometry.dart';

/// One character's place in a laid-out text box.
///
/// Rects are **box-local pixels** — origin at the text box's top-left, the
/// same space [TextOverlayLayout.textOrigin] lives in — so a glyph can be
/// placed without re-deriving the box.
class TextGlyphBox {
  const TextGlyphBox({
    required this.charIndex,
    required this.inkRect,
    required this.paddedRect,
  });

  /// Index into [TextOverlayModel.text]. Whitespace is skipped, so these are
  /// not contiguous — an animation that staggers by character must use this,
  /// not the list index, or a space would not consume a beat of the stagger.
  final int charIndex;

  /// Where the glyph's own pixels land.
  final Rect inkRect;

  /// [inkRect] grown by the shadow/stroke bleed, which is the rect the atlas
  /// actually stores. Shadows extend past a glyph's ink and would otherwise
  /// contaminate the neighbouring atlas cell.
  final Rect paddedRect;
}

/// Where every character of [overlay] sits, using Flutter's own text layout.
///
/// This asks `TextPainter` for each character's box rather than measuring
/// characters independently: kerning, ligatures and bidi mean the width of
/// "AV" is not the width of "A" plus the width of "V", and per-character
/// measurement would drift from what the flat raster draws.
List<TextGlyphBox> layoutTextGlyphs({
  required TextOverlayModel overlay,
  required Size canvasSize,
  required double shadowPadding,
}) {
  if (overlay.text.isEmpty) return const [];

  final layout = TextOverlayLayout.measure(overlay, canvasSize);
  final painter = TextOverlayLayout.textPainterFor(overlay, layout.renderScale)
    ..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);

  final origin = layout.textOrigin;
  final glyphs = <TextGlyphBox>[];

  for (var i = 0; i < overlay.text.length; i++) {
    // Whitespace has no ink; drawing a quad for it wastes a draw call and
    // gives an empty atlas cell.
    if (overlay.text[i].trim().isEmpty) continue;

    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    if (boxes.isEmpty) continue;

    final box = boxes.first.toRect().shift(origin);
    if (box.width <= 0 || box.height <= 0) continue;

    glyphs.add(
      TextGlyphBox(
        charIndex: i,
        inkRect: box,
        paddedRect: box.inflate(shadowPadding),
      ),
    );
  }

  painter.dispose();
  return glyphs;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/video_editor/logic/text_glyph_layout_test.dart`
Expected: PASS (7 tests)

If the whitespace test fails because `getBoxesForSelection` returns a zero-width box for a newline rather than an empty list, the `box.width <= 0` guard already covers it — confirm the failure is not instead a sign that `textOrigin` is being applied twice.

- [ ] **Step 5: Run the full suite and analyzer**

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all tests pass; no new analyzer errors (48 pre-existing issues is the current baseline).

- [ ] **Step 6: Commit**

```bash
git add lib/features/video_editor/logic/text_glyph_layout.dart test/features/video_editor/logic/text_glyph_layout_test.dart
git commit -m "feat(text): per-character glyph layout from Flutter's text engine

Asks TextPainter for each character's box rather than measuring
characters independently — kerning and ligatures mean the width of
'AV' is not the width of 'A' plus 'V', so per-character measurement
would drift from what the flat raster draws.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Rasterise the glyph atlas

Draws the text into a sprite sheet where each glyph occupies its own cell, and returns the mapping from cell to on-canvas placement.

**Files:**
- Modify: `lib/features/video_editor/services/text_overlay_rasterizer.dart`
- Test: `test/features/video_editor/services/text_overlay_rasterizer_test.dart`

**Interfaces:**
- Consumes: `layoutTextGlyphs(...)` and `TextGlyphBox` from Task 1. `TextOverlayLayout.measure`, `.textPainterFor`, `.strokeStyleFor`, `.hasStroke`, `.textAlignFor`, `.shadowsFor` from `logic/text_overlay_geometry.dart`. `TextOverlayRasterizer.effectiveRasterScale({rasterScale, overlayScale, canvasPxSize})` and `kMaxRasterSidePx`, both already present.
- Produces:
  - `class RasterizedGlyph { final Rect atlasRect; final Rect boxRect; }` — `atlasRect` in atlas pixels, `boxRect` in box-local canvas pixels.
  - `class RasterizedTextAtlas { final String pngPath; final Size canvasPxSize; final Size atlasPxSize; final List<RasterizedGlyph> glyphs; final Rect? backgroundRect; final double borderRadius; }`
  - `static Future<RasterizedTextAtlas?> rasterizeAtlas({required TextOverlayModel overlay, required Size canvasSize, required double rasterScale})`
- The existing `rasterize(...)` returning `RasterizedTextOverlay` **stays** — Task 5 uses it as the fallback path.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/video_editor/services/text_overlay_rasterizer_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TextOverlayModel overlayWith(String text, {Color? background}) =>
      TextOverlayModel(
        id: 't',
        text: text,
        backgroundColor: background ?? Colors.transparent,
        referenceCanvasSize: const Size(400, 700),
      );

  group('rasterizeAtlas', () {
    test('returns one glyph entry per inked character', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      expect(atlas, isNotNull);
      expect(atlas!.glyphs.length, 3);
    });

    test('atlas cells do not overlap', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('abcdef'),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      final rects = atlas!.glyphs.map((g) => g.atlasRect).toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(
            rects[i].overlaps(rects[j]),
            isFalse,
            reason: 'cell $i overlaps cell $j',
          );
        }
      }
    });

    test('every cell sits inside the atlas', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('hello world'),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      final bounds = Offset.zero & atlas!.atlasPxSize;
      for (final g in atlas.glyphs) {
        expect(bounds.contains(g.atlasRect.topLeft), isTrue);
        expect(bounds.contains(g.atlasRect.bottomRight - const Offset(0.01, 0.01)), isTrue);
      }
    });

    test('a cell and its box rect have the same shape', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        rasterScale: 2,
      );
      for (final g in atlas!.glyphs) {
        final atlasAspect = g.atlasRect.width / g.atlasRect.height;
        final boxAspect = g.boxRect.width / g.boxRect.height;
        expect(atlasAspect, closeTo(boxAspect, 0.02));
      }
    });

    test('carries the background rect when the overlay has one', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('abc', background: Colors.red),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      expect(atlas!.backgroundRect, isNotNull);
    });

    test('has no background rect when the overlay has none', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      expect(atlas!.backgroundRect, isNull);
    });

    test('empty text produces no atlas', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('   '),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      expect(atlas, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/video_editor/services/text_overlay_rasterizer_test.dart`
Expected: FAIL — `The method 'rasterizeAtlas' isn't defined for the type 'TextOverlayRasterizer'`

- [ ] **Step 3: Write minimal implementation**

Add to `lib/features/video_editor/services/text_overlay_rasterizer.dart`. Keep the existing `rasterize` method and `RasterizedTextOverlay` class exactly as they are; add these alongside, plus the import `import '../logic/text_glyph_layout.dart';`.

```dart
/// One glyph's cell in the atlas, and where it belongs on the canvas.
class RasterizedGlyph {
  const RasterizedGlyph({required this.atlasRect, required this.boxRect});

  /// The cell's rect in **atlas pixels**.
  final Rect atlasRect;

  /// Where the cell is drawn, in **box-local canvas pixels** (origin at the
  /// text box's top-left, before the user's pinch scale).
  final Rect boxRect;
}

/// A text overlay rasterised as a sprite sheet of glyphs.
///
/// The constructor is `const` so tests can build a fixture atlas without
/// running a rasteriser.
class RasterizedTextAtlas {
  const RasterizedTextAtlas({
    required this.pngPath,
    required this.canvasPxSize,
    required this.atlasPxSize,
    required this.glyphs,
    required this.backgroundRect,
    required this.borderRadius,
  });

  final String pngPath;

  /// The whole text box in canvas pixels — the same box `rasterize` reports.
  final Size canvasPxSize;

  final Size atlasPxSize;
  final List<RasterizedGlyph> glyphs;

  /// The background box in box-local canvas pixels, or null for no background.
  final Rect? backgroundRect;

  /// Background corner radius in canvas pixels.
  final double borderRadius;
}
```

Then the method, on `TextOverlayRasterizer`:

```dart
  /// Rasterises [overlay] as a sprite sheet: one cell per inked character.
  ///
  /// The cells are packed into rows rather than laid out as they appear on
  /// screen, so a wide single line does not force a wide, mostly-empty
  /// texture. Each cell is padded by the shadow blur plus the stroke width,
  /// because both extend past a glyph's ink and would otherwise bleed into
  /// the neighbouring cell.
  ///
  /// Returns null when there is nothing to draw, or when the atlas would
  /// exceed the texture limit — the caller falls back to the flat raster.
  static Future<RasterizedTextAtlas?> rasterizeAtlas({
    required TextOverlayModel overlay,
    required Size canvasSize,
    required double rasterScale,
  }) async {
    if (overlay.text.trim().isEmpty ||
        canvasSize.width <= 0 ||
        canvasSize.height <= 0) {
      return null;
    }

    try {
      final layout = TextOverlayLayout.measure(overlay, canvasSize);
      final boxSize = layout.boxSize;
      if (boxSize.width <= 0 || boxSize.height <= 0) return null;
      final renderScale = layout.renderScale;

      final shadowPadding = _bleedPadding(overlay, renderScale);
      final glyphBoxes = layoutTextGlyphs(
        overlay: overlay,
        canvasSize: canvasSize,
        shadowPadding: shadowPadding,
      );
      if (glyphBoxes.isEmpty) return null;

      final density = effectiveRasterScale(
        rasterScale: rasterScale,
        overlayScale: overlay.scale,
        canvasPxSize: boxSize,
      );

      // Pack cells into rows no wider than the texture limit.
      final cells = <Rect>[];
      var penX = 0.0;
      var penY = 0.0;
      var rowHeight = 0.0;
      var atlasWidth = 0.0;
      for (final glyph in glyphBoxes) {
        final w = glyph.paddedRect.width * density;
        final h = glyph.paddedRect.height * density;
        if (penX > 0 && penX + w > kMaxRasterSidePx) {
          penX = 0;
          penY += rowHeight;
          rowHeight = 0;
        }
        cells.add(Rect.fromLTWH(penX, penY, w, h));
        penX += w;
        rowHeight = math.max(rowHeight, h);
        atlasWidth = math.max(atlasWidth, penX);
      }
      final atlasHeight = penY + rowHeight;
      if (atlasWidth <= 0 ||
          atlasHeight <= 0 ||
          atlasWidth > kMaxRasterSidePx ||
          atlasHeight > kMaxRasterSidePx) {
        return null;
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final textAlign = TextOverlayLayout.textAlignFor(overlay);
      final fillPainter = TextOverlayLayout.textPainterFor(overlay, renderScale)
        ..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
      TextPainter? strokePainter;
      if (TextOverlayLayout.hasStroke(overlay)) {
        strokePainter = TextPainter(
          text: TextSpan(
            text: overlay.text,
            style: TextOverlayLayout.strokeStyleFor(overlay, renderScale),
          ),
          textDirection: TextDirection.ltr,
          textAlign: textAlign,
          textScaler: TextScaler.noScaling,
        )..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
      }

      // Each cell draws the *whole* text translated so that this glyph's
      // padded rect lands on the cell, clipped to the cell. Drawing the whole
      // run keeps kerning, ligatures and alignment identical to the flat
      // raster; the clip is what isolates one character.
      for (var i = 0; i < glyphBoxes.length; i++) {
        final glyph = glyphBoxes[i];
        final cell = cells[i];
        canvas.save();
        canvas.clipRect(cell);
        canvas.translate(cell.left, cell.top);
        canvas.scale(density);
        canvas.translate(-glyph.paddedRect.left, -glyph.paddedRect.top);
        strokePainter?.paint(canvas, layout.textOrigin);
        fillPainter.paint(canvas, layout.textOrigin);
        canvas.restore();
      }

      fillPainter.dispose();
      strokePainter?.dispose();

      final image = await recorder.endRecording().toImage(
            atlasWidth.ceil().clamp(1, kMaxRasterSidePx),
            atlasHeight.ceil().clamp(1, kMaxRasterSidePx),
          );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return null;

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/text_atlas_${overlay.id}_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());

      return RasterizedTextAtlas(
        pngPath: file.path,
        canvasPxSize: boxSize,
        atlasPxSize: Size(atlasWidth, atlasHeight),
        glyphs: [
          for (var i = 0; i < glyphBoxes.length; i++)
            RasterizedGlyph(
              atlasRect: cells[i],
              boxRect: glyphBoxes[i].paddedRect,
            ),
        ],
        backgroundRect: layout.hasBackground ? layout.backgroundRect : null,
        borderRadius: overlay.borderRadius * renderScale,
      );
    } catch (error) {
      debugPrint('[TextAtlas] ${overlay.id} failed: $error');
      return null;
    }
  }

  /// How far ink can extend past a glyph's box: the shadow's blur and its
  /// offset, plus half the stroke width, which straddles the glyph's edge.
  static double _bleedPadding(TextOverlayModel overlay, double renderScale) {
    var padding = 0.0;
    if (overlay.shadowColor != Colors.transparent &&
        overlay.shadowBlurRadius > 0) {
      final blur = overlay.shadowBlurRadius * renderScale;
      padding = math.max(padding, blur + blur / 2);
    }
    if (TextOverlayLayout.hasStroke(overlay)) {
      padding = math.max(padding, overlay.strokeWidth * renderScale / 2);
    }
    return padding;
  }
```

Add the import for the layout helpers at the top of the file:

```dart
import '../logic/text_glyph_layout.dart';
import '../logic/text_overlay_geometry.dart';
```

(`text_overlay_geometry.dart` is already imported; do not duplicate it.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/video_editor/services/text_overlay_rasterizer_test.dart`
Expected: PASS (7 tests, plus the 3 pre-existing `effectiveRasterScale` tests in `text_overlay_geometry_test.dart` still passing).

- [ ] **Step 5: Run the full suite and analyzer**

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all pass; no new analyzer errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/video_editor/services/text_overlay_rasterizer.dart test/features/video_editor/services/text_overlay_rasterizer_test.dart
git commit -m "feat(text): rasterise a glyph atlas alongside the flat raster

Each cell draws the whole text run translated and clipped to one
glyph, so kerning, ligatures and alignment stay identical to the flat
raster — measuring characters independently would drift. Cells are
padded by the shadow and stroke bleed so neither contaminates a
neighbouring cell.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Carry glyphs through the timeline contract

**Files:**
- Modify: `lib/features/video_editor/models/editor_timeline.dart:331-424`
- Test: `test/features/video_editor/models/editor_timeline_overlay_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (the model is standalone).
- Produces:
  - `class EditorTimelineGlyph { const EditorTimelineGlyph({required this.atlasLeft, required this.atlasTop, required this.atlasRight, required this.atlasBottom, required this.boxLeft, required this.boxTop, required this.boxRight, required this.boxBottom}); Map<String, dynamic> toJson(); }`
  - `EditorTimelineOverlay` gains `final List<EditorTimelineGlyph>? glyphs;` and `final double backgroundLeft/Top/Right/Bottom;` and `final double backgroundRadius;` — all optional, defaulting to null/0.
  - `kind` may now be `'text'`.
- Atlas coordinates are **0..1 fractions of the atlas**; box coordinates are **0..1 fractions of the text box**. No pixels cross the boundary.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/video_editor/models/editor_timeline_overlay_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';

void main() {
  EditorTimelineOverlay baseOverlay({
    String kind = 'image',
    List<EditorTimelineGlyph>? glyphs,
  }) {
    return EditorTimelineOverlay(
      id: 'o1',
      kind: kind,
      path: '/tmp/a.png',
      centerX: 0.5,
      centerY: 0.5,
      boxWidth: 0.4,
      boxHeight: 0.4,
      scale: 1,
      rotation: 0,
      opacity: 1,
      startSeconds: 0,
      endSeconds: 2,
      laneIndex: 0,
      slideOffsetX: 0,
      slideOffsetY: 0,
      glyphs: glyphs,
    );
  }

  group('EditorTimelineOverlay glyphs', () {
    test('an image overlay serialises no glyph array', () {
      expect(baseOverlay().toJson()['glyphs'], isNull);
    });

    test('a text overlay serialises its glyphs in order', () {
      final json = baseOverlay(
        kind: 'text',
        glyphs: const [
          EditorTimelineGlyph(
            atlasLeft: 0,
            atlasTop: 0,
            atlasRight: 0.5,
            atlasBottom: 1,
            boxLeft: 0.1,
            boxTop: 0.2,
            boxRight: 0.4,
            boxBottom: 0.8,
          ),
          EditorTimelineGlyph(
            atlasLeft: 0.5,
            atlasTop: 0,
            atlasRight: 1,
            atlasBottom: 1,
            boxLeft: 0.5,
            boxTop: 0.2,
            boxRight: 0.9,
            boxBottom: 0.8,
          ),
        ],
      ).toJson();

      final glyphs = json['glyphs'] as List;
      expect(glyphs.length, 2);
      expect((glyphs.first as Map)['atlasRight'], 0.5);
      expect((glyphs.last as Map)['boxLeft'], 0.5);
    });

    test('background rect and radius round-trip', () {
      final json = EditorTimelineOverlay(
        id: 'o1',
        kind: 'text',
        path: '/tmp/a.png',
        centerX: 0.5,
        centerY: 0.5,
        boxWidth: 0.4,
        boxHeight: 0.4,
        scale: 1,
        rotation: 0,
        opacity: 1,
        startSeconds: 0,
        endSeconds: 2,
        laneIndex: 0,
        slideOffsetX: 0,
        slideOffsetY: 0,
        backgroundLeft: 0.05,
        backgroundTop: 0.1,
        backgroundRight: 0.95,
        backgroundBottom: 0.9,
        backgroundRadius: 0.02,
      ).toJson();

      expect(json['backgroundLeft'], 0.05);
      expect(json['backgroundBottom'], 0.9);
      expect(json['backgroundRadius'], 0.02);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/video_editor/models/editor_timeline_overlay_test.dart`
Expected: FAIL — `Undefined class 'EditorTimelineGlyph'`

- [ ] **Step 3: Write minimal implementation**

In `lib/features/video_editor/models/editor_timeline.dart`, add before `class EditorTimelineOverlay`:

```dart
/// One glyph of a `text` overlay: where it is in the atlas, and where it is
/// drawn inside the text box.
///
/// Both rects are **fractions**, never pixels — atlas coordinates of the
/// sprite sheet, box coordinates of the text box — so the renderer never
/// inherits a device resolution. See the overlay section of CLAUDE.md.
class EditorTimelineGlyph {
  const EditorTimelineGlyph({
    required this.atlasLeft,
    required this.atlasTop,
    required this.atlasRight,
    required this.atlasBottom,
    required this.boxLeft,
    required this.boxTop,
    required this.boxRight,
    required this.boxBottom,
  });

  final double atlasLeft;
  final double atlasTop;
  final double atlasRight;
  final double atlasBottom;

  final double boxLeft;
  final double boxTop;
  final double boxRight;
  final double boxBottom;

  Map<String, dynamic> toJson() {
    return {
      'atlasLeft': atlasLeft,
      'atlasTop': atlasTop,
      'atlasRight': atlasRight,
      'atlasBottom': atlasBottom,
      'boxLeft': boxLeft,
      'boxTop': boxTop,
      'boxRight': boxRight,
      'boxBottom': boxBottom,
    };
  }
}
```

In `EditorTimelineOverlay`, add to the constructor's optional parameters (after `isMuted`):

```dart
    this.glyphs,
    this.backgroundLeft = 0,
    this.backgroundTop = 0,
    this.backgroundRight = 0,
    this.backgroundBottom = 0,
    this.backgroundRadius = 0,
```

Change the `kind` doc comment and add the fields after `isMuted`:

```dart
  /// `image`, `video`, or `text`.
  final String kind;
```

```dart
  /// Text overlays only: one entry per drawn character. A `text` overlay with
  /// no glyphs is drawn as a plain image, which is the fallback path.
  final List<EditorTimelineGlyph>? glyphs;

  /// Text overlays only: the background box, in text-box fractions, and its
  /// corner radius as a fraction of the box width. Drawn as one quad behind
  /// the glyphs — slicing it per glyph would make it move with the letters.
  final double backgroundLeft;
  final double backgroundTop;
  final double backgroundRight;
  final double backgroundBottom;
  final double backgroundRadius;
```

In `toJson()`, add before the closing brace of the returned map:

```dart
      'glyphs': glyphs?.map((glyph) => glyph.toJson()).toList(),
      'backgroundLeft': backgroundLeft,
      'backgroundTop': backgroundTop,
      'backgroundRight': backgroundRight,
      'backgroundBottom': backgroundBottom,
      'backgroundRadius': backgroundRadius,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/video_editor/models/editor_timeline_overlay_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Run the full suite and analyzer**

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all pass. The composer test suite must still pass unchanged — the new fields are optional, so existing overlays serialise as before apart from five new keys with null/zero values.

- [ ] **Step 6: Commit**

```bash
git add lib/features/video_editor/models/editor_timeline.dart test/features/video_editor/models/editor_timeline_overlay_test.dart
git commit -m "feat(timeline): a text overlay kind carrying per-glyph rects

Atlas and box coordinates are fractions, never pixels, so the renderer
does not inherit a device resolution. The background stays one quad
behind the glyphs rather than being sliced per character.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Kotlin parses the glyph table

**Files:**
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelineOverlay.kt`

**Interfaces:**
- Consumes: the JSON keys Task 3 emits — `glyphs` (a list of maps with `atlasLeft/Top/Right/Bottom`, `boxLeft/Top/Right/Bottom`), `backgroundLeft/Top/Right/Bottom`, `backgroundRadius`, and `kind == "text"`.
- Produces:
  - `internal data class NativeTimelineGlyph(val atlasLeft: Double, val atlasTop: Double, val atlasRight: Double, val atlasBottom: Double, val boxLeft: Double, val boxTop: Double, val boxRight: Double, val boxBottom: Double)`
  - `NativeTimelineOverlay` gains `val glyphs: List<NativeTimelineGlyph>`, `val backgroundLeft/Top/Right/Bottom: Double`, `val backgroundRadius: Double`, and `val isText: Boolean get() = kind == "text" && glyphs.isNotEmpty()`.

- [ ] **Step 1: Add the glyph data class**

In `NativeTimelineOverlay.kt`, above `internal data class NativeTimelineOverlay`:

```kotlin
/**
 * One glyph of a text overlay.
 *
 * Atlas coordinates are fractions of the sprite sheet; box coordinates are
 * fractions of the text box. Both arrive normalised — the Dart side converts
 * at the boundary so this side never sees a device pixel.
 */
internal data class NativeTimelineGlyph(
    val atlasLeft: Double,
    val atlasTop: Double,
    val atlasRight: Double,
    val atlasBottom: Double,
    val boxLeft: Double,
    val boxTop: Double,
    val boxRight: Double,
    val boxBottom: Double,
)
```

- [ ] **Step 2: Add the fields to the overlay**

Add to the `NativeTimelineOverlay` constructor, after `isMuted`:

```kotlin
    /** Text overlays only: one entry per drawn character. */
    val glyphs: List<NativeTimelineGlyph>,
    /** Text overlays only: the background box in text-box fractions. */
    val backgroundLeft: Double,
    val backgroundTop: Double,
    val backgroundRight: Double,
    val backgroundBottom: Double,
    val backgroundRadius: Double,
```

And beside `isVideo`:

```kotlin
    /**
     * A text overlay with glyphs to draw. A `text` overlay that arrived
     * without them (the atlas exceeded the texture limit) falls back to the
     * plain image path, which is why this checks both.
     */
    val isText: Boolean get() = kind == "text" && glyphs.isNotEmpty()
```

- [ ] **Step 3: Parse them in `fromMap`**

Inside `fromMap`, before the `return NativeTimelineOverlay(`:

```kotlin
            val glyphs = (map["glyphs"] as? List<*>)?.mapNotNull { entry ->
                val glyph = entry as? Map<*, *> ?: return@mapNotNull null
                NativeTimelineGlyph(
                    atlasLeft = glyph.number("atlasLeft") ?: return@mapNotNull null,
                    atlasTop = glyph.number("atlasTop") ?: return@mapNotNull null,
                    atlasRight = glyph.number("atlasRight") ?: return@mapNotNull null,
                    atlasBottom = glyph.number("atlasBottom") ?: return@mapNotNull null,
                    boxLeft = glyph.number("boxLeft") ?: return@mapNotNull null,
                    boxTop = glyph.number("boxTop") ?: return@mapNotNull null,
                    boxRight = glyph.number("boxRight") ?: return@mapNotNull null,
                    boxBottom = glyph.number("boxBottom") ?: return@mapNotNull null,
                )
            } ?: emptyList()
```

And in the constructor call, after `isMuted = ...`:

```kotlin
                glyphs = glyphs,
                backgroundLeft = map.number("backgroundLeft") ?: 0.0,
                backgroundTop = map.number("backgroundTop") ?: 0.0,
                backgroundRight = map.number("backgroundRight") ?: 0.0,
                backgroundBottom = map.number("backgroundBottom") ?: 0.0,
                backgroundRadius = map.number("backgroundRadius") ?: 0.0,
```

- [ ] **Step 4: Compile**

Run: `.\android\gradlew.bat -p android compileDebugKotlin`
Expected: BUILD SUCCESSFUL. If it fails with "No value passed for parameter 'glyphs'", another construction site of `NativeTimelineOverlay` exists — give it `glyphs = emptyList()` and zeros for the background fields.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelineOverlay.kt
git commit -m "feat(native): parse per-glyph rects off a text overlay

A text overlay that arrived without glyphs — the atlas exceeded the
texture limit — reports isText false and falls back to the plain image
path rather than drawing nothing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Draw glyph quads

Adds an exact-rect draw mode to the renderer and emits one draw per glyph.

**Files:**
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/OverlayRenderer.kt:39-53` and `:246-277`
- Modify: `android/app/src/main/kotlin/com/techfamz/slimshotai/export/VideoExportEngine.kt:820-862`

**Interfaces:**
- Consumes: `NativeTimelineOverlay.isText`, `.glyphs`, `NativeTimelineGlyph` (Task 4); `OverlayRenderer.Draw`, `.cachedImageTexture(path)`, `.imageTexture(path, bitmap)` (existing).
- Produces: `OverlayRenderer.Draw` gains `val srcRect: FloatArray?` (u0, v0, u1, v1 — null means the whole texture) and `val boxRect: FloatArray?` (left, top, right, bottom as text-box fractions — null means contain-fit the whole box, the existing behaviour).

- [ ] **Step 1: Extend the Draw record**

In `OverlayRenderer.kt`, add to `data class Draw` after `texMatrix`:

```kotlin
        /**
         * Sub-rect of the texture to sample (u0, v0, u1, v1), or null for the
         * whole texture. A glyph reads one cell of the atlas.
         */
        val srcRect: FloatArray? = null,
        /**
         * Where to place the quad inside the overlay's box, as box fractions
         * (left, top, right, bottom), or null to contain-fit the whole box —
         * which is what every image and video overlay does.
         */
        val boxRect: FloatArray? = null,
```

- [ ] **Step 2: Honour `boxRect` in `writeCorners`**

Replace the body of `writeCorners` up to the rotation block:

```kotlin
    private fun writeCorners(draw: Draw, canvasAspect: Double) {
        val halfW: Double
        val halfH: Double
        var offsetX = 0.0
        var offsetY = 0.0

        val boxRect = draw.boxRect
        if (boxRect != null) {
            // An exact placement inside the box: the quad covers this rect,
            // no contain-fit. A glyph's cell already has the right shape, so
            // fitting it again would letterbox a letter.
            val left = boxRect[0].toDouble()
            val top = boxRect[1].toDouble()
            val right = boxRect[2].toDouble()
            val bottom = boxRect[3].toDouble()
            halfW = 0.5 * draw.boxWidth * (right - left) * draw.scale
            halfH = 0.5 * draw.boxHeight * (bottom - top) * draw.scale
            // The rect's centre relative to the box's centre.
            offsetX = draw.boxWidth * ((left + right) / 2.0 - 0.5) * draw.scale
            offsetY = draw.boxHeight * ((top + bottom) / 2.0 - 0.5) * draw.scale
        } else {
            // Content fitted inside the box, preserving its own shape — the same
            // contain-fit `ConstrainedBox` + `Image` produce in the preview.
            val fitW = if (draw.contentAspect >= 1.0) 1.0 else draw.contentAspect
            val fitH = if (draw.contentAspect >= 1.0) 1.0 / draw.contentAspect else 1.0
            halfW = 0.5 * draw.boxWidth * fitW * draw.scale
            halfH = 0.5 * draw.boxHeight * fitH * draw.scale
        }

        // Clockwise rotation with y-down, in height units so x and y rotate
        // through the same metric.
        val cosR = cos(draw.rotation)
        val sinR = sin(draw.rotation)

        // Order matches the texcoord buffers: TL, TR, BL, BR.
        val cornersX = doubleArrayOf(-halfW, halfW, -halfW, halfW)
        val cornersY = doubleArrayOf(-halfH, -halfH, halfH, halfH)

        positions.clear()
        for (i in 0 until 4) {
            // The glyph's own offset rotates with the box, so a rotated text
            // keeps its letters in line rather than each spinning in place.
            val px = (cornersX[i] + offsetX) * canvasAspect
            val py = cornersY[i] + offsetY
            val rx = (px * cosR - py * sinR) / canvasAspect
            val ry = px * sinR + py * cosR

            val xFrac = draw.centerX + rx
            val yFrac = draw.centerY + ry
            positions.put((xFrac * 2.0 - 1.0).toFloat())
            positions.put((1.0 - yFrac * 2.0).toFloat())
        }
        positions.flip()
    }
```

- [ ] **Step 3: Sample the sub-rect**

Add a reusable buffer beside `positions`:

```kotlin
    private val glyphTexCoords: FloatBuffer =
        ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
```

And a helper:

```kotlin
    /** Texcoords for one atlas cell, in the TL, TR, BL, BR order the quad uses. */
    private fun writeGlyphTexCoords(srcRect: FloatArray): FloatBuffer {
        val u0 = srcRect[0]
        val v0 = srcRect[1]
        val u1 = srcRect[2]
        val v1 = srcRect[3]
        glyphTexCoords.clear()
        glyphTexCoords.put(u0); glyphTexCoords.put(v0)
        glyphTexCoords.put(u1); glyphTexCoords.put(v0)
        glyphTexCoords.put(u0); glyphTexCoords.put(v1)
        glyphTexCoords.put(u1); glyphTexCoords.put(v1)
        glyphTexCoords.flip()
        return glyphTexCoords
    }
```

In `draw(...)`, replace the bitmap branch's `drawQuad` call:

```kotlin
                val texCoords = draw.srcRect?.let { writeGlyphTexCoords(it) }
                    ?: texCoordsTopDown
                drawQuad(aPosition2d, aTexCoord2d, texCoords)
```

- [ ] **Step 4: Emit one draw per glyph**

In `VideoExportEngine.kt`'s `OverlayPass.drawsFor`, replace the dispatch:

```kotlin
                val resolved = if (overlay.isVideo) {
                    listOfNotNull(videoDraw(overlay, t, state))
                } else if (overlay.isText) {
                    textDraws(overlay, state)
                } else {
                    listOfNotNull(imageDraw(overlay, state))
                }
                draws.addAll(resolved)
```

(and change `val draw = ...; if (draw != null) draws.add(draw)` accordingly).

Add the method to `OverlayPass`:

```kotlin
        /**
         * One draw per glyph, all reading the overlay's atlas.
         *
         * The texture is uploaded once and every glyph samples its own cell,
         * so a 40-character text costs one upload and 40 quads — which is
         * nothing for a GPU, and is what lets a later stage animate each
         * character independently.
         */
        private fun textDraws(
            overlay: NativeTimelineOverlay,
            state: NativeTimelineOverlay.FrameState,
        ): List<OverlayRenderer.Draw> {
            val cached = renderer.overlays.cachedImageTexture(overlay.path)
            val (textureId, _) = cached ?: run {
                val bitmap = StillImageDecoder.decode(
                    overlay.path,
                    TEXT_ATLAS_MAX_PX,
                    TEXT_ATLAS_MAX_PX,
                )
                if (bitmap == null) {
                    diagnostics.failedOverlays++
                    return emptyList()
                }
                val uploaded = renderer.overlays.imageTexture(overlay.path, bitmap)
                bitmap.recycle()
                uploaded
            }

            return overlay.glyphs.map { glyph ->
                draw(
                    overlay,
                    state,
                    textureId,
                    isExternal = false,
                    contentAspect = 1.0,
                    texMatrix = null,
                ).copy(
                    srcRect = floatArrayOf(
                        glyph.atlasLeft.toFloat(),
                        glyph.atlasTop.toFloat(),
                        glyph.atlasRight.toFloat(),
                        glyph.atlasBottom.toFloat(),
                    ),
                    boxRect = floatArrayOf(
                        glyph.boxLeft.toFloat(),
                        glyph.boxTop.toFloat(),
                        glyph.boxRight.toFloat(),
                        glyph.boxBottom.toFloat(),
                    ),
                )
            }
        }
```

**Add the constant** beside `OVERLAY_IMAGE_MAX_PX` at the bottom of `VideoExportEngine.kt`:

```kotlin
/**
 * Largest side a text atlas is decoded at.
 *
 * Separate from [OVERLAY_IMAGE_MAX_PX] (1024) deliberately: that cap is
 * generous for a photo drawn into a small overlay box, but an atlas is
 * rasterised at export density — up to 4096 — and decoding it at 1024 would
 * downscale it, making exported text *blurrier* than the flat raster it
 * replaced. The atlas is already capped at the texture limit on the Dart
 * side, so this cap only has to not undercut it.
 */
private const val TEXT_ATLAS_MAX_PX = 4096
```

- [ ] **Step 5: Compile**

Run: `.\android\gradlew.bat -p android compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/OverlayRenderer.kt android/app/src/main/kotlin/com/techfamz/slimshotai/export/VideoExportEngine.kt
git commit -m "feat(native): draw a text overlay as one quad per glyph

Draw gains an exact-rect placement mode: a glyph's cell already has the
right shape, so contain-fitting it again would letterbox a letter. The
glyph's offset rotates with the box, so rotated text keeps its letters
in line rather than each spinning in place.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Route the export through the atlas

The last wiring step: build atlas overlays instead of flat ones, with a loud fallback.

**Files:**
- Modify: `lib/features/video_editor/services/native_timeline_preview_service.dart:229-310`
- Test: `test/features/video_editor/services/text_atlas_overlay_test.dart`

**Interfaces:**
- Consumes: `TextOverlayRasterizer.rasterizeAtlas(...)` and `RasterizedTextAtlas` (Task 2); `EditorTimelineGlyph` (Task 3); `textOverlayRenderScale`, `textOverlayCenter`, `textOverlayFitBox` (existing, `logic/text_overlay_geometry.dart`).
- Produces: `_rasterizeTextOverlays` returns the same record shape as today — `({List<EditorTimelineOverlay> overlays, List<String> tempFiles})` — so no caller changes.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/video_editor/services/text_atlas_overlay_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';
import 'package:slimshotai/features/video_editor/services/text_atlas_overlay.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('glyphsForAtlas', () {
    test('converts atlas and box pixels into fractions', () {
      const atlas = RasterizedTextAtlas(
        pngPath: '/tmp/a.png',
        canvasPxSize: Size(200, 100),
        atlasPxSize: Size(400, 50),
        glyphs: [
          RasterizedGlyph(
            atlasRect: Rect.fromLTWH(0, 0, 100, 25),
            boxRect: Rect.fromLTWH(20, 10, 40, 50),
          ),
        ],
        backgroundRect: null,
        borderRadius: 0,
      );

      final glyphs = glyphsForAtlas(atlas);
      expect(glyphs.length, 1);
      final g = glyphs.single;
      expect(g.atlasLeft, 0);
      expect(g.atlasRight, closeTo(0.25, 1e-9));
      expect(g.atlasBottom, closeTo(0.5, 1e-9));
      expect(g.boxLeft, closeTo(0.1, 1e-9));
      expect(g.boxTop, closeTo(0.1, 1e-9));
      expect(g.boxRight, closeTo(0.3, 1e-9));
      expect(g.boxBottom, closeTo(0.6, 1e-9));
    });

    test('a zero-sized atlas yields no glyphs rather than infinities', () {
      const atlas = RasterizedTextAtlas(
        pngPath: '/tmp/a.png',
        canvasPxSize: Size(200, 100),
        atlasPxSize: Size(0, 0),
        glyphs: [
          RasterizedGlyph(
            atlasRect: Rect.fromLTWH(0, 0, 10, 10),
            boxRect: Rect.fromLTWH(0, 0, 10, 10),
          ),
        ],
        backgroundRect: null,
        borderRadius: 0,
      );
      expect(glyphsForAtlas(atlas), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/video_editor/services/text_atlas_overlay_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../text_atlas_overlay.dart'`

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/video_editor/services/text_atlas_overlay.dart
import '../models/editor_timeline.dart';
import 'text_overlay_rasterizer.dart';

/// The atlas's glyph cells as timeline glyphs — pixels converted to fractions
/// at this boundary, so the renderer never sees a device resolution.
List<EditorTimelineGlyph> glyphsForAtlas(RasterizedTextAtlas atlas) {
  final aw = atlas.atlasPxSize.width;
  final ah = atlas.atlasPxSize.height;
  final bw = atlas.canvasPxSize.width;
  final bh = atlas.canvasPxSize.height;
  if (aw <= 0 || ah <= 0 || bw <= 0 || bh <= 0) return const [];

  return [
    for (final glyph in atlas.glyphs)
      EditorTimelineGlyph(
        atlasLeft: glyph.atlasRect.left / aw,
        atlasTop: glyph.atlasRect.top / ah,
        atlasRight: glyph.atlasRect.right / aw,
        atlasBottom: glyph.atlasRect.bottom / ah,
        boxLeft: glyph.boxRect.left / bw,
        boxTop: glyph.boxRect.top / bh,
        boxRight: glyph.boxRect.right / bw,
        boxBottom: glyph.boxRect.bottom / bh,
      ),
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/video_editor/services/text_atlas_overlay_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Wire it into the export**

In `native_timeline_preview_service.dart`, import `text_atlas_overlay.dart`, then inside the `for (final text in state.textOverlays)` loop replace the `rasterize` call with an atlas-first attempt:

```dart
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: text,
        canvasSize: canvas,
        rasterScale: rasterScale,
      );

      // The atlas is the animation-capable path. A text too large to fit the
      // texture limit falls back to the flat raster, which still exports
      // correctly — it just cannot animate per character.
      final RasterizedTextAtlas? usableAtlas =
          atlas != null && atlas.glyphs.isNotEmpty ? atlas : null;

      final String pngPath;
      final Size boxPxSize;
      List<EditorTimelineGlyph>? glyphs;
      if (usableAtlas != null) {
        pngPath = usableAtlas.pngPath;
        boxPxSize = usableAtlas.canvasPxSize;
        glyphs = glyphsForAtlas(usableAtlas);
      } else {
        final flat = await TextOverlayRasterizer.rasterize(
          overlay: text,
          canvasSize: canvas,
          rasterScale: rasterScale,
        );
        if (flat == null) continue;
        pngPath = flat.pngPath;
        boxPxSize = flat.canvasPxSize;
        glyphs = null;
      }
      tempFiles.add(pngPath);
```

Then replace the uses of `raster.pngPath` / `raster.canvasPxSize` in the `EditorTimelineOverlay` with `pngPath` / `boxPxSize`, set the kind, and pass the glyphs and background:

```dart
          kind: glyphs == null ? 'image' : 'text',
          path: pngPath,
          glyphs: glyphs,
          backgroundLeft: (usableAtlas?.backgroundRect?.left ?? 0) /
              (boxPxSize.width == 0 ? 1 : boxPxSize.width),
          backgroundTop: (usableAtlas?.backgroundRect?.top ?? 0) /
              (boxPxSize.height == 0 ? 1 : boxPxSize.height),
          backgroundRight: (usableAtlas?.backgroundRect?.right ?? 0) /
              (boxPxSize.width == 0 ? 1 : boxPxSize.width),
          backgroundBottom: (usableAtlas?.backgroundRect?.bottom ?? 0) /
              (boxPxSize.height == 0 ? 1 : boxPxSize.height),
          backgroundRadius: (usableAtlas?.borderRadius ?? 0) /
              (boxPxSize.width == 0 ? 1 : boxPxSize.width),
```

`boxWidth`/`boxHeight` keep using `textOverlayFitBox(boxPxSize)` exactly as today.

**Important:** the glyph draw path does not yet paint the background box — Task 5 draws glyphs only. So for this stage, an overlay **with a background** must take the flat path. Add that condition:

```dart
      // The glyph path draws letters only; a background box would vanish.
      // Backgrounds keep the flat raster until the background quad lands.
      final RasterizedTextAtlas? usableAtlas =
          atlas != null && atlas.glyphs.isNotEmpty && atlas.backgroundRect == null
              ? atlas
              : null;
```

- [ ] **Step 6: Run the full suite, analyzer and Kotlin compile**

Run: `flutter test`, `flutter analyze --no-pub`, `.\android\gradlew.bat -p android compileDebugKotlin`
Expected: all pass, no new analyzer errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/video_editor/services/text_atlas_overlay.dart lib/features/video_editor/services/native_timeline_preview_service.dart test/features/video_editor/services/text_atlas_overlay_test.dart
git commit -m "feat(export): route text through the glyph atlas

Atlas-first with a flat-raster fallback for text too large for the
texture limit, and for text with a background box until the background
quad lands. Pixels become fractions at this boundary so the renderer
never inherits a device resolution.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Device verification and documentation

This stage's whole point is that **nothing should look different**. That is the gate.

**Files:**
- Modify: `CLAUDE.md` (the text export section, around the "Text now exports natively" heading)

- [ ] **Step 1: Build and install**

Run: `flutter build apk --debug` then install, or `flutter run`.
Expected: builds clean.

- [ ] **Step 2: Export the comparison set**

Export each of these and compare against the same project exported from the previous commit:

1. Short single-line text, no background, no stroke — the base case.
2. Multi-line text (a manual line break) — proves line stacking.
3. Text with a stroke — proves stroke bleed padding.
4. Text with a shadow — proves shadow bleed padding.
5. Text with a background — **must take the flat path** (backgrounds are excluded this stage); confirm it still exports correctly.
6. Rotated and pinch-scaled text — proves the glyph offsets rotate with the box.
7. A very long text (200+ characters) — either atlases correctly or falls back; must not produce empty text.

Expected: 1, 2, 3, 4, 6, 7 are **visually identical** to the previous build. 5 is unchanged because it took the old path.

- [ ] **Step 3: If any case differs, stop and diagnose**

Do not proceed to Stage 2 with a mismatch. The likely causes, in order:
- Letters spaced wrong → `boxRect` fractions are being divided by the wrong dimension.
- Letters clipped → the bleed padding is too small, or `atlasRect` is off by the padding.
- Letters in the wrong place when rotated → the glyph offset is being applied after rotation instead of before.
- Text blurry → `OVERLAY_IMAGE_MAX_PX` is downscaling the atlas (see Task 5, Step 4's note).

- [ ] **Step 4: Update CLAUDE.md**

In the text export section, after the paragraph describing the flat raster, add:

```markdown
**Text exports as a glyph atlas** (Stage 1 of per-character animation; awaiting device
verification). `TextOverlayRasterizer.rasterizeAtlas` draws each inked character into its own
cell of one sprite sheet, and the timeline carries a `text` overlay kind holding per-glyph
atlas and box rects (fractions, never pixels). `OverlayRenderer.Draw` gained an exact-rect
placement mode (`srcRect` + `boxRect`): a glyph's cell already has the right shape, so
contain-fitting it the way an image overlay is fitted would letterbox a letter.

Each cell draws the **whole text run** translated and clipped to one glyph, rather than
painting characters individually — kerning and ligatures mean the width of "AV" is not the
width of "A" plus "V", so per-character painting would drift from the flat raster. Cells are
padded by the shadow blur and half the stroke width, both of which extend past a glyph's ink
and would otherwise bleed into the neighbouring cell.

**Two cases deliberately keep the flat raster**: text whose atlas would exceed the 4096px
texture limit, and text with a **background box** (the glyph pass draws letters only, so a
background would vanish — it becomes one quad behind the glyphs in a later stage). Both
fall back silently *by design* here because the output is identical either way; the moment
animation lands, a fallback means no per-character animation and must warn.
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: record the glyph atlas path and its two fallbacks

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Stage 1 exit criteria

- [ ] All seven device cases export identically to the previous build.
- [ ] `flutter analyze --no-pub` shows no new issues over the 48-issue baseline.
- [ ] `flutter test` passes, including the ~19 new tests.
- [ ] `.\android\gradlew.bat -p android compileDebugKotlin` succeeds.
- [ ] CLAUDE.md records the atlas path and both fallbacks.

Only then does Stage 2 (the curve table and the Kotlin port) begin. Its plan is written after this stage is device-verified, because the atlas's real behaviour may change decisions in it.
