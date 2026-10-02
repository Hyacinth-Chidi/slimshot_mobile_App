# Auto Captions — Stage 3 (Word highlight) Implementation Plan

**Goal:** The word being spoken lights up — colour, pop, pill, karaoke, reveal, focus — drawn
by the same rules on the canvas and in the exported file.

**Spec:** `docs/superpowers/specs/2026-09-29-auto-captions-design.md`, "Stage 3 — Word
highlight". Stage 1 (timing) and the default look are device-verified; Stage 2 awaits its run.

**Executed inline by the author**, on `feat/auto-captions`, test first. Tasks, interfaces and
decisions here; the code is in the commits.

## Decisions

- **One catalog, three consumers.** `caption_highlight_catalog.dart` is a pure function
  `wordHighlightStateAt(style, t, words, index, span)`; the preview painter, the Kotlin port
  `CaptionHighlightCurves.kt` and (Stage 4) the preset tiles read it. A fixture pins the port.
- **One colour, not two.** `CaptionHighlight(style, color)`: the colour is what lights the word
  — the fill for Colour/Pop/Karaoke, the box for Pill. A second "pill colour" field was a second
  control for one look; Stage 4's presets pair text and pill colours as whole looks.
- **A word is active from its start until the next word starts**; the last until the caption
  ends. Before the first word nothing is active (the caption leads its word by 60ms).
- **Colour switches at the boundary; only scale, pill and opacity ramp** (`kHighlightRampSeconds`
  0.08). A glyph half in each look would cast its shadow twice.
- **Pop scales about the word's centre**, as per-glyph offsets — the word swells as one piece.
- **Karaoke is geometry.** The preview clips the base and highlight paints to complementary
  rects; the export splits the straddling glyph into two quads over the base and highlight
  cells — same linear mapping, no shader. Right-to-left words sweep right to left.
- **The atlas holds each glyph twice, plus a pill cell per word and a box cell.** The glyph
  table gains the highlight cell and the word index; the overlay gains the word spans and the
  style.
- **The background box becomes its own quad**, so a boxed text takes the atlas path and the
  boxed-text fallback (and the template rule it forced) is retired.
- Word times are clamped to the caption's span (Stage 2's known gap).

## Tasks

1. `CaptionHighlight` model on `TextOverlayModel` and `CaptionSettings`; `WordHighlightState`,
   `wordHighlightStateAt`, `wordIndexForChar`, `captionPillRect` in the catalog; fixture
   generator `tool/generate_caption_highlight_fixture.dart` + Dart pin test.
2. Preview: `TextOverlayPainter` per-glyph highlight path (pills → glyphs, karaoke clips, pop
   about the word).
3. Export: rasteriser highlight/pill/box cells; wire fields; Kotlin parse, `CaptionHighlightCurves`
   + fixture test, `OverlayDrawBuilder.textDraws` box/pill/highlight/karaoke draws; the boxed
   fallback retired.
4. Sheet: Highlight row (style chips + colour row) in `AutoCaptionSheet`, live on an existing set
   (`setCaptionHighlight`, one undo step), carried by `CaptionRequest`/`placeCaptions` for a new
   one.
5. CLAUDE.md, full verification, one fresh review.

## Review focus

1. A glyph whose word index cannot be resolved (punctuation between words, a hand-edited text)
   draws in the base look, never vanishes.
2. A caption whose words end after its span still highlights to the end and never indexes past
   the last word.
3. An ordinary text (no highlight, no words) exports **byte-identical** glyph JSON to before.
4. Karaoke at fill exactly 0 and exactly 1 draws one quad, not two.
5. A boxed text now exports through the atlas with its box behind every glyph.

## Device checklist

1. Generate captions, choose each highlight style in turn: the word being spoken lights up on the
   canvas, in time with the speech.
2. Export with Colour, Pop, Pill and Karaoke: the file matches the canvas.
3. A caption with a background box (Style tab) exports with the box behind the words.
4. Change the colour: every caption changes; one Undo puts it back.
5. Fix a word in the list: the highlight still lands on the right words.
