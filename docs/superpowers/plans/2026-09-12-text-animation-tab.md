# Text Animation Tab (Stage 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The animation tab offers every animation the engine can play, in three categories, each tile previewing itself live, with one Speed slider that means what it says.

**Architecture:** The tab reads `kTextAnimations` directly — no second list. Each tile is the **same painter the canvas uses**, at small scale, on a looping local clock, so a tile cannot promise something the export will not deliver. Nothing new is added to the animation engine; this stage is entirely presentation.

**Tech Stack:** Flutter/Dart, Riverpod.

**Spec:** `docs/superpowers/specs/2026-09-11-text-animation-design.md`

**Depends on:** Stage 2 (`docs/superpowers/plans/2026-09-11-text-animation-engine.md`), complete and device-verified — text animates per character in preview and export, and the Speed multiplier reaches the renderer.

## Global Constraints

- **One definition, three consumers.** The tab must read `kTextAnimations`. A hardcoded list of names is exactly what this stage deletes; reintroducing one puts the UI back out of step with the engine.
- **`isSelectable: false` animations must not appear.** `colour_fill` and `colour_cycle_loop` time correctly but nothing draws `fillProgress`, so offering them would show an animation that does nothing.
- **Legacy ids resolve by slot** (`resolveTextAnimation(id, slot)`), never `textAnimationById`. A persisted `'fade'` means fade-in in the in-slot and fade-out in the out-slot.
- **Undo is manual and a gesture is one step.** `saveStateForUndo()` once per user action, never per slider frame — use `updateTextOverlayLive` for continuous changes.
- **Colours from `AppColors`**, Lucide icons, dark theme only.
- Analyzer baseline is exactly **48** pre-existing issues. Add none; fix none.
- Verify with `flutter analyze --no-pub`, `flutter test`.

## What this stage does NOT touch

The catalog, the Kotlin port, the fixture, the painter, the composer, and the export. If a tile
looks wrong, the fix is in the presentation layer or the bug is real and belongs to Stage 2 —
do not "correct" a curve to make a tile look better, because that silently changes the export.

---

### Task 1: Category queries on the catalog

The tab needs "every selectable animation in this category" and the model's current selection
resolved back to a catalog entry. Both belong beside the catalog, not in a widget.

**Files:**
- Modify: `lib/features/video_editor/logic/text_animation_catalog.dart`
- Test: `test/features/video_editor/logic/text_animation_catalog_test.dart` (extend)

**Interfaces:**
- Consumes: `kTextAnimations`, `TextAnimation`, `TextAnimationCategory`, `resolveTextAnimation` (all existing).
- Produces:
  - `List<TextAnimation> selectableTextAnimations(TextAnimationCategory category)` — catalog order, `isSelectable` only.
  - `String? textAnimationSlotValue(TextOverlayModel overlay, TextAnimationCategory slot)` — the id stored for that slot (`inAnimation` / `outAnimation` / `loopAnimation`), or null when it resolves to nothing.

- [ ] **Step 1: Write the failing tests**

```dart
  group('selectableTextAnimations', () {
    test('returns only selectable entries, in catalog order', () {
      for (final category in TextAnimationCategory.values) {
        final list = selectableTextAnimations(category);
        expect(list, isNotEmpty, reason: '$category must offer something');
        expect(
          list.every((a) => a.category == category && a.isSelectable),
          isTrue,
        );
        final catalogOrder = kTextAnimations
            .where((a) => a.category == category && a.isSelectable)
            .map((a) => a.id)
            .toList();
        expect(list.map((a) => a.id).toList(), catalogOrder);
      }
    });

    test('excludes the animations nothing draws', () {
      final ids = [
        for (final category in TextAnimationCategory.values)
          ...selectableTextAnimations(category).map((a) => a.id),
      ];
      expect(ids, isNot(contains('colour_fill')));
      expect(ids, isNot(contains('colour_cycle_loop')));
    });

    test('offers the per-glyph animations this stage exists to expose', () {
      final inIds =
          selectableTextAnimations(TextAnimationCategory.inAnim).map((a) => a.id);
      expect(inIds, containsAll(['typing', 'wave_in', 'bounce_in']));
    });
  });

  group('textAnimationSlotValue', () {
    TextOverlayModel overlay({
      String inAnim = 'none',
      String outAnim = 'none',
      String loop = 'none',
    }) =>
        TextOverlayModel(
          id: 't',
          text: 'hi',
          inAnimation: inAnim,
          outAnimation: outAnim,
          loopAnimation: loop,
        );

    test('reads the field belonging to each slot', () {
      final o = overlay(inAnim: 'typing', outAnim: 'fade_out', loop: 'wave_loop');
      expect(textAnimationSlotValue(o, TextAnimationCategory.inAnim), 'typing');
      expect(textAnimationSlotValue(o, TextAnimationCategory.outAnim), 'fade_out');
      expect(textAnimationSlotValue(o, TextAnimationCategory.loop), 'wave_loop');
    });

    test('a legacy id resolves to its slot variant', () {
      // 'fade' meant fadeIn in the in slot and fadeOut in the out slot, so the
      // tab must highlight a different tile for the same stored string.
      expect(
        textAnimationSlotValue(overlay(inAnim: 'fade'), TextAnimationCategory.inAnim),
        'fade_in',
      );
      expect(
        textAnimationSlotValue(overlay(outAnim: 'fade'), TextAnimationCategory.outAnim),
        'fade_out',
      );
    });

    test('an id that resolves to nothing reads as no selection', () {
      // A bare in-only id in the out slot played nothing in the old layer, so
      // no tile should look selected for it.
      expect(
        textAnimationSlotValue(overlay(outAnim: 'slide_up'), TextAnimationCategory.outAnim),
        isNull,
      );
      expect(
        textAnimationSlotValue(overlay(), TextAnimationCategory.inAnim),
        isNull,
      );
    });
  });
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/video_editor/logic/text_animation_catalog_test.dart`
Expected: FAIL — `selectableTextAnimations` undefined.

- [ ] **Step 3: Implement both functions**

Keep them beside the catalog. `textAnimationSlotValue` must go through `resolveTextAnimation`
and return the **resolved** id, so the tab highlights the tile that will actually play.

- [ ] **Step 4: Run tests, then the full gates**

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all pass; 48 analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/video_editor/logic/text_animation_catalog.dart test/features/video_editor/logic/text_animation_catalog_test.dart
git commit -m "feat(text): category queries so the tab reads the catalog

The tab needs the selectable animations per category and the resolved
id for a slot; both belong beside the catalog rather than in a widget,
which is what keeps a second list from growing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: The live preview tile

One tile: a small looping animation of the user's own text, driven by the same painter the
canvas uses.

**Files:**
- Create: `lib/features/video_editor/widgets/text_overlay/text_animation_tile.dart`
- Test: `test/features/video_editor/widgets/text_animation_tile_test.dart`

**Interfaces:**
- Consumes: `TextAnimation`, `TextOverlayPainter` (or whatever `text_overlay_painter.dart` exposes — **read it first** and reuse it rather than writing a second painter), `TextOverlayModel`.
- Produces: `class TextAnimationTile extends StatefulWidget` taking `{required TextAnimation animation, required TextOverlayModel overlay, required bool isSelected, required VoidCallback onTap, Listenable? clock}`.

- [ ] **Step 1: Drive the existing painter**

Verified before writing this plan — `TextOverlayPainter` (in
`lib/features/video_editor/widgets/text_overlay/text_overlay_painter.dart`) takes exactly:

```dart
TextOverlayPainter({
  required TextOverlayModel overlay,
  required TextOverlayLayout layout,
  required Size canvasSize,
  required double positionSeconds,
});
```

So a tile builds a **synthetic overlay** — the user's styling, the truncated text, a start of
zero and an end covering the animation's natural duration — measures it with
`TextOverlayLayout.measure`, and sweeps `positionSeconds` from its clock. One loop of the clock
walks the animation from its start to its rest.

**A tile must not reimplement the painting.** A tile that draws its own approximation is worse
than no tile: it promises something the export will not deliver, which is the failure this
whole stage's architecture exists to prevent.

- [ ] **Step 2: Write the failing tests**

Widget tests, not goldens (brittle for animation). Assert behaviour:

```dart
  testWidgets('the tile shows the animation label', (tester) async { … });

  testWidgets('tapping reports the selection once', (tester) async {
    // One tap = one callback. A tile that fires per animation frame would
    // push an undo entry per frame.
  });

  testWidgets('a selected tile is visually distinct from an unselected one',
      (tester) async {
    // Pump both and assert their painted decoration differs, rather than
    // asserting a specific colour — the point is that a user can tell.
  });

  testWidgets('the tile repaints as its clock advances', (tester) async {
    // Drive the injected clock and assert the painter is asked to repaint,
    // which is what makes the preview live rather than a still frame.
  });

  testWidgets('an empty overlay falls back to sample text', (tester) async {
    // Text is created empty; a tile showing nothing teaches nothing.
  });
```

- [ ] **Step 3: Run them and watch them fail**

Run: `flutter test test/features/video_editor/widgets/text_animation_tile_test.dart`

- [ ] **Step 4: Implement the tile**

Rules:
- **Truncate the text** to ~8 grapheme clusters. Enough to show a per-glyph stagger, cheap to
  lay out, and a caption can be a paragraph. Use `characters`, not `substring` — Stage 1's
  emoji bug was exactly this mistake.
- **Take the clock as a `Listenable`** rather than owning a `Ticker`. The panel drives every
  tile from one clock (Task 3); a ticker per tile means twenty tickers.
- Keep the user's styling (colour, font, stroke) so a tile shows *their* text, but ignore
  their scale and rotation — a tile is a fixed box.

- [ ] **Step 5: Run tests, then the full gates**

- [ ] **Step 6: Commit**

```bash
git add lib/features/video_editor/widgets/text_overlay/text_animation_tile.dart test/features/video_editor/widgets/text_animation_tile_test.dart
git commit -m "feat(text): a live animation tile built from the canvas painter

A tile is the same painter the canvas uses, on a looping clock, so it
cannot promise an animation the export will not deliver.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The three-tab panel and the Speed slider

**Files:**
- Modify: `lib/features/video_editor/widgets/text_overlay/text_editor_dialog.dart`
- Test: `test/features/video_editor/widgets/text_animation_panel_test.dart`

**Interfaces:**
- Consumes: `selectableTextAnimations`, `textAnimationSlotValue` (Task 1); `TextAnimationTile` (Task 2); `TextOverlayModel.loopAnimation`/`loopSpeed`; `kTextAnimationNaturalSpeed`.

- [ ] **Step 1: Replace the hardcoded list and the two tabs**

Delete `_animationsList` entirely. Three category buttons — **In / Out / Loop** — replacing the
current two, each showing `selectableTextAnimations(category)` in a grid of tiles plus a
leading **None** tile.

Selecting writes the slot's field (`inAnimation` / `outAnimation` / `loopAnimation`) with the
animation's **catalog id**, through one `saveStateForUndo()` per tap.

- [ ] **Step 2: Make the slider a Speed control**

The slider currently reads `_inAnimationDuration`/`_outAnimationDuration` and is labelled in
seconds. Those fields now hold a **speed multiplier**; the slider must show and write that:
range 0.5×–3×, default `kTextAnimationNaturalSpeed`, labelled `1.4×` not `0.8s`. The loop tab
writes `loopSpeed`.

Show it only when that slot has an animation, as today.

**Continuous drag must not push an undo entry per frame** — `saveStateForUndo()` on drag start,
`updateTextOverlayLive` per change, as the canvas handles already do.

- [ ] **Step 3: One clock for every tile**

An `AnimationController` on the panel, repeating, passed to each tile. Only the visible
category's tiles are built, so switching tabs does not leave twenty animations running.

- [ ] **Step 4: Write the panel tests**

```dart
  testWidgets('offers three categories', (tester) async { … });

  testWidgets('shows every selectable animation for the active category',
      (tester) async {
    // Count tiles against selectableTextAnimations(category).length + 1 for
    // None, so adding a catalog entry cannot silently miss the tab.
  });

  testWidgets('never offers an animation nothing draws', (tester) async {
    // colour_fill must not appear anywhere in the panel.
  });

  testWidgets('selecting an animation writes the slot it belongs to',
      (tester) async { … });

  testWidgets('a legacy stored id highlights its resolved tile',
      (tester) async {
    // An overlay holding outAnimation:'fade' must show Fade out selected.
  });

  testWidgets('the speed slider reads and writes the multiplier',
      (tester) async {
    // Not seconds. A slider showing "0.8s" while the model holds a speed is
    // the bug this stage inherited.
  });
```

- [ ] **Step 5: Run tests, then the full gates**

- [ ] **Step 6: Commit**

```bash
git add lib/features/video_editor/widgets/text_overlay/text_editor_dialog.dart test/features/video_editor/widgets/text_animation_panel_test.dart
git commit -m "feat(text): three animation categories, live tiles, a real Speed slider

The tab reads the catalog instead of a hardcoded seven names, so every
animation the engine can play is offered and a new catalog entry cannot
silently miss the UI. The slider stops being labelled in seconds it
never controlled.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Device verification

- [ ] **Step 1: Build**

Run: `flutter build apk --debug`

- [ ] **Step 2: Verify on device**

1. Every category lists its animations, each tile animating its own preview.
2. `colour_fill` and `colour_cycle_loop` appear nowhere.
3. Picking typing / wave / bounce plays on the canvas, then exports matching.
4. The Speed slider changes the pace, and the change reaches the export.
5. A loop animation runs continuously between the in and out animations.
6. Opening a project saved before Stage 2 shows its original animation highlighted, and it
   still looks the way it did.
7. Text with no animation, an image overlay, and a video clip are all unchanged.

- [ ] **Step 3: Update CLAUDE.md**

Record that the tab reads the catalog, the one-clock rule, and that a tile is the canvas
painter.

## Stage 3 exit criteria

- [ ] The tab offers exactly `selectableTextAnimations(category)` per category — no second list.
- [ ] Tiles animate, and show the user's own text.
- [ ] The Speed slider reads and writes the multiplier, and reaches the export.
- [ ] Legacy projects highlight the right tile and look unchanged.
- [ ] `flutter test` and `flutter analyze --no-pub` (48) pass.
