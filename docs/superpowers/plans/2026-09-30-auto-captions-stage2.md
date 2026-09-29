# Auto Captions — Stage 2 (Edit) Implementation Plan

**Goal:** A generated caption set can be corrected: words fixed without losing their timing,
captions split, merged, deleted, re-cut to another length, and moved as one set.

**Spec:** `docs/superpowers/specs/2026-09-29-auto-captions-design.md`, "Stage 2 — Edit".

**Executed inline by the author of the plan**, on `feat/auto-captions`, test first. This plan
therefore records tasks, interfaces and decisions; the code is in the commits.

## Global constraints

As Stage 1: `flutter analyze --no-pub` at exactly 48; colours from `AppColors`; sheets through
`showEditorSheet`; one user action is one undo step; new keys omitted when absent; never push or
merge.

## Decisions

- **Retiming lives in the notifier, not in any one editor.** `updateTextOverlay` and
  `updateTextOverlayLive` retime a caption whenever its text changed, so the batch list, the text
  editor and anything added later keep timing the same way.
- **Set-wide placement is a delta, applied to every other caption's whole path.** The edited
  caption goes through the edit rule as any text does; the others take the same change in
  position, scale, rotation and opacity on their base values and on every keyframe value.
- **Box width is set-wide too** — it is what makes captions wrap alike.
- **The timeline Split tool stays off for text.** Splitting a caption is a list action.
- **A caption emptied in the list is removed when the list closes**, the rule the text editor
  already has for a text left empty.

## Tasks

1. **`retimeCaptionWords`** (`logic/captions/caption_retime.dart`): tokenise the new text
   (whitespace-separated; each character of a script written without spaces is its own word),
   align against the old words by longest common subsequence on normalised tokens, keep matched
   times, share the time between matched neighbours across an unmatched run by length.
2. **Caption edits** (`logic/captions/caption_edits.dart`), pure: `splitCaption`,
   `mergeCaptions`, `shiftCaptionStart`, `captionSpacedWords` + `recutCaptionDrafts`,
   `followCaptionMotion`.
3. **Notifier**: the retime hook; `trimLaneItem` keeps words on their instants; set-wide motion
   and box width; `splitCaptionAt`, `mergeCaptionWithNext`, `deleteAllCaptions`,
   `recutCaptions`, `removeEmptyCaptions`.
4. **UI**: `CaptionBatchSheet`; a `captions` tool on the selected text's menu, shown only for a
   caption (`isToolbarToolVisible`); the screen's handler with seek.
5. **CLAUDE.md**, full verification, one fresh review of the stage.

## Review focus

1. Editing one word in the middle of a caption leaves every other word's time untouched.
2. Deleting every word of a caption, then typing new ones, never throws and never leaves a word
   outside the caption's span.
3. Splitting at the very start or end of a caption's text does nothing rather than making an
   empty caption.
4. Merging the last caption (no next one) does nothing.
5. Moving one caption moves the set by the same amount, and one Undo puts the whole set back.

## Device checklist

1. Select a caption → **Captions** opens the list at that caption.
2. Tap a time → the playhead jumps there.
3. Fix a misheard word → the caption updates live; one Undo restores it.
4. Split, merge and delete a row; Delete all.
5. Change Length → the set is re-cut, keeping the fixes.
6. Drag one caption on the canvas → every caption moves; pinch → every caption resizes.
7. Trim a caption's left edge on the timeline → it still ends on its last word.
8. Export → the file matches the canvas.
