# Auto Captions — Stage 4 (Caption styles) Implementation Plan

**Goal:** A caption set's whole look — typeface, colours, outline or box, shadow, motion and
word highlight — is one tap from a grid of presets, and a look edit on one caption reaches the
whole set.

**Spec:** `docs/superpowers/specs/2026-09-29-auto-captions-design.md`, "Stage 4 — Caption
styles". Stage 1 is device-verified; Stages 2 and 3 await their device run.

**Executed inline by the author**, on `feat/auto-captions`, test first. Tasks, interfaces and
decisions here; the code is in the commits.

## Decisions

- **The look has one definition: `TextLook`** (`logic/text_look.dart`). Font, fill, outline,
  box (colour, radius, padding), the five shadow fields, alignment, the three animations and
  their speeds. `TextLook.of(text)`, `look.applyTo(text)`, and `sameLookAs` — equality that
  ignores the speeds, which is what "is this text wearing that look" has always meant.
  `TextTemplate.restyle` and `isAppliedTo` become `look.applyTo` + the template's size and
  `look.sameLookAs`; their tests pass unchanged, which is what proves the refactor. A test
  sets every field of a text to a non-default value and requires `TextLook` to carry each one
  that is not on an explicit "not a look" list (words, timing, place, size, lane, caption,
  keyframes…), so a look field added later reaches templates and captions together or fails.
- **A preset is a look plus a highlight — no place, no size.** The spec's test list mentions
  placement; a preset that moved the set would undo the user's own placement every time they
  tried a style, and a caption's size is the canvas rule (`kCaptionFontFraction`). Ruling: a
  preset carries neither, and the test pins that instead.
- **`kCaptionPresets[0]` is the default look** — the one Stage 1 shipped, device-approved — so
  a set generated without touching the grid is exactly what it was.
- **Fonts**: presets may use any of `allFonts`. The default stays the bundled Montserrat Bold;
  a preset in a downloaded face waits for it at export like any text (`awaitExportFonts`).
  Tests inject presets in `kTestFontFamily`, the Templates tab's pattern.
- **The grid is the canvas painter** (`CaptionPresetTile` over `TextPreviewTile`): a synthetic
  caption in the preset's sample words, with word times spread over the tile's loop so the
  highlight plays. One clock for the grid, held while the sheet scrolls.
- **Choosing a preset, with a set present, restyles the set at once** — every caption's look
  and highlight, the settings' highlight — one undo step, none when nothing changes. Without a
  set it is the new set's look. The Highlight row follows the preset, so it can be tuned after.
- **The current preset is found, not remembered** (`isAppliedTo` on the set's first caption):
  a hand edit makes no tile current, which is the truth.
- **Regenerating keeps the set's look.** The sheet opens on the first caption's look, and a new
  set is built from it — hand tuning survives a regeneration.
- **Apply to all captions** (`VideoEditorState.captionLookToAll`, on by default, not persisted):
  in `_setText`, a caption whose look changed passes its `TextLook` to every caption of its set,
  inside the edit's own undo step. The text editor shows the `ApplyToAllToggle` for a caption
  only. **A template chosen on a caption keeps the caption's size** — size is the set's, and
  a template's size would make one caption larger than its neighbours.
- **New text starts in Montserrat Bold** (the spec's bundled default). Only where new text is
  made; the model's default and `fromJson` stay Roboto, so every draft opens as it was.

## Tasks

1. `TextLook` + the template refactor (coverage test; template tests unchanged).
2. `CaptionPreset`, `kCaptionPresets`, catalog test; `buildCaptionOverlays(look:)`;
   `CaptionRequest.look`; the default preset is the default look.
3. Notifier: `restyleCaptions(look, highlight)`; `captionLookToAll` and its propagation in
   `_setText`; a template on a caption keeps its size.
4. Sheet: the Style grid (count pinned to the catalog), live apply, request carries the look;
   the text editor's "Apply to all captions" toggle.
5. New text starts in Montserrat Bold.
6. CLAUDE.md, full verification, one fresh review.

## Review focus

1. A look field on `TextOverlayModel` that `TextLook` misses — caught by the coverage test.
2. A preset applied to a set mid-gesture or with keyframes: only look fields change, never
   motion tracks, words or timing.
3. Apply to all with a caption edited from the canvas (move, pinch) — those are motion, not
   look, and must not be broadcast twice (the set already moves as one).
4. A draft from before Stage 4 opens with its look untouched and its font as stored.
5. The grid's clock stops while the sheet scrolls and never leaks a ticker when the sheet closes.

## Device checklist

1. Generate captions with a preset other than the first: the set wears it, highlight included.
2. With a set present, tap through the presets: the whole set restyles; one Undo per tap.
3. Edit one caption's colour in the text editor: every caption follows; turn the toggle off and
   only that caption changes.
4. Regenerate after hand-tuning a look: the new set keeps it.
5. A new plain text starts in Montserrat Bold; an old draft's text keeps its font.
