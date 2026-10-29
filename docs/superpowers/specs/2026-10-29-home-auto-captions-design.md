# Auto captions from Home — design

2026-10-29. The flow and the screen were chosen from mockups (layout A, "Card"; the four-step
flow) and approved by the owner. This document is what a builder plans from.

## Intent

Auto captions is one of the most wanted features in short-form editing, and in SlimShot it sits
inside the editor (the main menu's Auto captions, or Text → Auto captions). Someone who only wants
a captioned clip has to learn the editor to get one. This puts it on Home: pick a video, generate,
choose a look, export — no timeline.

It takes the place of **Privacy Strip**, which leaves the app entirely (the owner's call).

## Goals

- Home's three tool cards become **Auto captions · Compress Video · Compress Photo**, in that order.
- A screen with no timeline: the video in a card; before the captions, Language, Length and
  Generate; while they are made, progress on the video and Cancel; after, the captions playing on
  the video, **Edit words**, a **Style** row, a **Colour** row and **Export**.
- **Captions identical to the editor's**: the same project model, preview, caption run, styles and
  export. The screen is the editor in a *captions mode*, the way recording mode is the editor with
  another face.
- **No draft, nothing in Recent Edits** for caption-only work (the owner's call): like a
  compression, it lives while the screen does. Captions someone paid for are protected another way
  — leaving the finished screen without an export asks first.
- **✎ opens the full editor** on the same project, without reloading it; from then on it is an
  ordinary editor project, saved as one.
- **Privacy Strip is removed** — its screens, logic, native reader, ad placement, tests and notes.

## Non-goals

- A second caption pipeline, preview or export path.
- New caption styles or highlights; controls for a caption's place or size (the editor has them).
- A timeline, trimming, several videos, music, the editor's tools.
- Export options (resolution, frame rate) on this screen.

## Anti-goals — failures even if it works

- Captions that look different here from the editor or the exported file.
- A user losing captions they paid credits for by leaving the screen.
- A screen that feels like the editor: a timeline, a toolbar, tool panels.
- Ads or sign-in anywhere they do not already appear.

## The flow (approved)

### 1. Home

The tool cards read **Auto captions · Compress Video · Compress Photo**. Auto captions takes Privacy
Strip's place, first of the three, with Lucide's `subtitles` glyph. A tap opens the gallery on
videos, **one video** (the same picker and permission handling as Compress video), then the screen.

### 2. Ready

- Top bar: back on the left, **"Auto captions"** centred (as Compress video's title is). No ✎ yet.
- The video in a card, sized to the project's 9:16 frame, plain dark around it — a caption's colour
  is judged against the footage, so no Home glow here (the editor's rule). A tap plays and pauses.
- **Language** (Auto detect, opening the same language list the editor's Auto captions sheet uses)
  and **Length** (Word · Phrase · Line, **Phrase** chosen). The audio is always the video's own sound —
  the editor's Source choice has nothing else to choose here.
- **Generate captions**, pinned at the foot.
- Generate goes through the editor's own door: sign-in and claim (`CaptionAccess.ensureAllowed`), the
  silent price check, the caption run. A video with no sound says so here and stays on Ready.

### 3. Generating

- The card dims under a progress ring with its percentage; under the card the run's stage
  ("Writing captions…", with the stage line the editor's progress sheet shows).
- **Cancel** in Generate's place. Cancel or Back stops the run exactly as closing the editor's
  progress sheet does.
- A shortfall shows **in place**, as the editor's progress sheet shows it: "Needs N credits · You
  have M" with the earning block (Watch an ad, Invite). A balance that comes to cover the price
  carries the run on by itself, as in the editor.

### 4. Done

- The captions play on the video — the editor's own preview and caption drawing, highlight
  included.
- **"Aa Edit words"**, a small chip under the card: the editor's caption list (`CaptionBatchSheet`),
  for a misheard word.
- **STYLE**: the nine caption styles as tiles in one scrolling row (the Caption style sheet's
  tiles), the one the set wears marked. A tap restyles the whole set, one undo step
  (`restyleCaptions`).
- **COLOUR**: the highlight colours (`kCaptionHighlightColors`), dimmed and deaf where the style
  lights in no colour, as in the Caption style sheet. A tap is one undo step
  (`setCaptionHighlight`).
- **Export**, pinned at the foot.
- **✎** at the top right: the full editor on this project, in place — from then on an ordinary
  editor project, saved to Recent Edits as any is.

### 5. Export

Export opens the existing export screen at **HD 1080, 30 fps** — the editor's own defaults — with no
options sheet. Everything after is as now: the export's interstitial now and then (never a first
export), Save, Share, Discard.

### Back and leaving

Captions mode never saves a draft, at any step.

- On Ready: leaves. The picked copy of the video is deleted, as Compress video deletes its picks.
- While generating: Back is Cancel.
- On Done, nothing exported yet: **"Discard these captions?"** — the app's discard question
  (`confirmDiscard`'s look), Cancel staying. Discard leaves, deleting the picked copy; the credits
  were spent on captions nobody kept, so they are asked about, never lost by a stray Back.
- On Done after an export: leaves without asking — the captions are in a file, and the export
  screen asked about that file before it let it go.
- After ✎: the editor's own rules (it saves on leaving), and the picked copy belongs to its
  draft.

## How — decided

- **Captions mode is a mode of `VideoEditorScreen`**, entered from its route (a route of its own,
  or a flag on the editor's). The editor's setup runs unchanged — the project from the picked video,
  the preview engine, the playback guard, the ads made ready (`AdService.prepare(export)`) — and its
  build shows the captions layout in place of the editor's: no timeline, toolbar or tool panels.
  Recording mode is the precedent: a state the editor's build reads.
- **The preview is the editor's** (the native preview texture and the caption layer), laid out
  inside the card.
- **The caption run is the editor's** (`_startAutoCaptions`'s pieces): the access check,
  `CaptionPipeline` with the video's sound, `placeCaptions` with `captionStyleForNewSet`. Not the
  options sheet (its choices are on Ready) and not the progress sheet's modal frame (the progress is
  drawn on the card) — the pipeline, its stages and its shortfall decision are reused, only drawn
  differently.
- **Saving**: captions mode never saves a draft — not on leaving, not on dispose (the editor saves
  on both today). Leaving it deletes the picked copy unless ✎ made it an editor project.
- **✎** leaves captions mode for the full editor on the same screen — no new route, no reload —
  and from then on the editor saves as it always does.
- **Edit words** opens `CaptionBatchSheet` as the editor does, on the set's first caption.

## Privacy Strip — removed (the owner's call)

Everything that exists only for it goes:

- Screens: `lib/screens/privacy_screen.dart`, `lib/screens/privacy_result_screen.dart`.
- `lib/features/privacy/**`: the JPEG metadata stripper, the metadata model, the provider, the
  services, the views.
- Routes `/privacy` and `/privacy/result`; `main.dart`'s use of `privacyProvider` in its "work in
  progress" check.
- Home's `_handlePrivacyStrip` and its card.
- Native: `privacy/PhotoMetadataReader.kt` and its registration in `MainActivity`
  (`slimshot_ai/photo_metadata`). Nothing outside Privacy Strip reads it.
- Ads: the `privacyStrip` placement (switch, pacing gap, rule). Photo compression's rule keeps its
  values (one second in, every compression however fast) as a constant of its own — today it is
  defined as Privacy Strip's.
- Tests: `test/features/privacy/**`, and the Privacy Strip cases in other tests (the home cards,
  the result files, the ad tests).
- CLAUDE.md: the Privacy Strip section and its mentions elsewhere.
- Kept: `PhotoInspector` (Compress photo uses it).

## Constraints

- Android first; `minSdk` 24; the low-end target (one preview decoder is all this needs).
- Credits: priced and charged exactly as in the editor (the silent quote; only a shortfall shows).
- The app's rules: colours from `AppColors`, motion from `AppMotion`, minimal copy, tests first, the
  analyzer at its baseline, Lucide glyphs.

## Left to the builder

Sizes and spacing (from mockup A); how captions mode threads through the editor's build; the
language list's presentation (the editor's own list, reused); the stage wording (the progress
sheet's own lines); test structure.

## Calls made in the design (the owner can overrule)

- Export at HD 1080 / 30 fps with no options.
- Leaving the finished screen with nothing exported asks "Discard these captions?" first.
- No ✎ on Ready: before the captions there is nothing the editor would add.
- One video per run.
- No "generate again" on this screen: the editor's Auto captions (through ✎) regenerates.
- A set emptied through Edit words takes the screen back to Ready.
- No undo buttons on this screen: another style is the way back, and the undo steps are kept for
  the editor.
- A run holds the app while it lasts (`HeldWork`), as the editor's progress sheet does, so a tap on
  the home screen widget cannot tear a paid run down.
