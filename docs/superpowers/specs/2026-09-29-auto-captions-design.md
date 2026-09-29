# Auto Captions — Design

**Status:** awaiting approval. Nothing in this document is built.

Captions generated from a project's own sound, timed to the word, styled from presets and
highlighted word by word as they are spoken — preview and export drawn by the same rules. The
server half already works end to end (`slimshot_server`, ElevenLabs active: a 6.2s clip came back
in 7.4s with 13 word-timed words). This document is the app half.

**Out of scope here, planned for later:** sign-in, users and credits. Auto captions will become a
signed-in, credit-based feature — tapping it while signed out slides up a Google / email sign-in
sheet, while every other tool stays free. This design leaves exactly one place for that gate
(**Access gate** below) and builds nothing else of it.

## Build order

One spec, because all four stages share one data model — the words stored on each caption. Each
stage gets its own implementation plan, its own branch, and a device test before merge.

| Stage | Delivers | Device test proves |
| :--- | :--- | :--- |
| 1. **Generate** | Timeline sound → server → captions on a caption lane, in sync | Captions land on the right words through trims, speed and transitions; export is correct |
| 2. **Edit** | Batch edit list, word fixes that keep timing, split/merge, timing, re-cut, set-wide placement | A misheard word is fixed without the rest drifting |
| 3. **Word highlight** | The active word lights up — colour, pop, pill, karaoke, reveal, focus — in preview and export | The file highlights exactly as the canvas does |
| 4. **Caption styles** | Presets, the bundled default font, apply-to-all look | One tap restyles every caption |

Highlight comes before presets because presets are mostly highlight looks.

## What the user sees and does

1. **Text → Auto captions** — a third tool beside Add text and Templates in the root Text
   submenu (`_textMenu`). It is offered only when the build carries a server address
   (`SLIMSHOT_API_URL`); CLAUDE.md's rule is that auto captions is "not offered before it
   works".
2. **The caption sheet** (`showEditorSheet`, no title):
   - **Source** — Video sound (default) · Audio tracks · All.
   - **Language** — Auto detect (default), then a fixed list.
   - **Length** — Word · Phrase (default) · Line.
   - **Highlight** — style chips and a highlight colour (Stage 3).
   - **Style** — the presets grid (Stage 4; before it, one default look).
   - **Generate**.

   With a set already present, the Highlight and Style rows apply to it directly — no
   regeneration; only Source and Language need a new transcription.
3. **Progress** — a modal sheet: Preparing audio → Uploading → Listening → Placing, with Cancel.
4. **Captions appear** on their own lane as ordinary text bars, lower third on the canvas, one
   undo step. Generating again asks **"Replace captions?"** and swaps the whole set.
5. **Editing** (Stage 2) — a selected caption's menu gains **Captions**, opening the batch list;
   tapping a caption on the canvas still opens the normal text editor.

## Data model

**Captions are ordinary text overlays.** The alternatives — a dedicated caption track with its
own renderer, or a track expanded into text at draw time — each mean a second text pipeline or
two representations to keep in step. CLAUDE.md's emoji rule applies exactly: an emoji became a
text overlay and inherited the glyph atlas, animation, keyframes and export parity for free; a
caption does the same.

`TextOverlayModel` gains two optional fields, both omitted from JSON when absent, so a draft
without captions is byte-identical:

- **`captionSetId`** (`String?`) — which caption set this text belongs to. A string rather than
  a bool: v1 has one set per project, but a translated second set is the obvious next feature and
  an id costs nothing now against a migration later.
- **`captionWords`** (`List<CaptionWord>?`) — the words, in text order:

```dart
class CaptionWord {
  final int textStart;   // UTF-16 offset into TextOverlayModel.text, inclusive
  final int textEnd;     // UTF-16 offset, exclusive
  final Duration start;  // relative to the caption's startTime
  final Duration end;    // relative to the caption's startTime
}
```

UTF-16 offsets because `TextGlyphBox.charIndex` already is one: a glyph belongs to the word whose
`[textStart, textEnd)` contains its `charIndex`, with no second way of counting characters.
Times are **relative to the caption's start**, so dragging a caption bar moves its words with it.

Stage 3 adds **`highlight`** (`CaptionHighlight?`: style id, highlight colour, pill colour).

`VideoEditorState` gains **`captionSettings`** (`CaptionSettings?`, null until a set exists):
source, language, length, highlight (Stage 3), preset id (Stage 4) and the set's id. Persisted on the draft
(`DraftProject.captionSettings`, omitted when null), read defensively like every other field.
It is what Regenerate and Re-cut start from.

## Stage 1 — Generate

### Audio: the timeline's own mix

A new channel method, **`renderCaptionAudio`** (`timeline`, `outputPath`, `include`: any of
`clips` / `overlays` / `tracks`), renders the chosen sources through **`AudioExportMixer`** — the
export's mixer — as **mono 16 kHz AAC-LC at 48 kbps** in an M4A, starting at timeline 0.

That is the whole reason word times need no conversion: the server reports seconds from the
start of the uploaded audio, and the audio starts at timeline 0 and runs at timeline rate,
through trims, flat speed, speed curves and transition crossfades. The alternative — extracting
each file with FFmpeg and mapping times back — would be a second copy of the speed and trim
mapping, on a library the editor is being taken off.

- **`AudioExportMixer` takes a `MixConfig`** (sample rate, channels, bit rate, `unityGain`),
  defaulting to the export's current values (44100, 2, 128000, false) so the export is untouched.
  Mono is the mean of the left and right channels, summed before clipping.
- **Each chosen source plays at full level.** `unityGain` drops `masterVolume`, clip volume and
  its keyframes from the gain, keeping the transition crossfade (a timing rule, not a level). A
  muted clip's words were still spoken, and recognition wants every word at full level.
- **Source filter.** Video sound = clips + video overlays; Audio tracks = imported tracks; All =
  both. The renderer passes empty lists for what is excluded.
- **Reversed clips are skipped**: reversed speech has no words to caption.
- **Duration** is the end of the last included source, not the project tail.
- **Nothing to hear** (`prepare()` false) answers "No sound to caption" before any upload.
- Playback is paused; the lane surfaces are **not** detached — this is audio only.
- Progress arrives as `captionAudioProgress` events; `cancelCaptionAudio` stops it.

`CaptionAudioRenderer.kt` (in `export/`) owns the pass; the manager starts it on a background
thread like `startExport`.

### The server client

- **`SlimshotApi`** (`lib/core/services/slimshot_api.dart`) is the app's one server client, since
  captions are the first of several server features (fonts, sign-in). It owns:
  - the base URL, `const String.fromEnvironment('SLIMSHOT_API_URL')`;
  - **device registration**: `POST /api/app/v1/devices` once, token kept in
    `shared_preferences` (`slimshot_device_token`). An anonymous device token grants only
    caption jobs; secure storage arrives with sign-in, when a token becomes worth protecting;
  - **a 401 re-registers once and retries once**;
  - the response envelope (`{success, data}` / `{success:false, error:{code,message,traceId}}`),
    decoded into a typed `SlimshotApiException(code, message)`.
- **`CaptionService`** (`lib/features/video_editor/services/caption_service.dart`):
  - `POST /api/app/v1/captions`, multipart field `audio` as `audio/mp4`, optional `language`
    (omitted for Auto detect — the server then detects), header `Idempotency-Key`.
  - **One key per Generate tap, reused by Try again**, so a lost response resends to the same job
    rather than creating (and, later, charging for) a second.
  - Polls `GET /api/app/v1/captions/{jobId}` at the server's `pollAfterMs`; gives up after
    **10 minutes**. The server keeps finished results 180s, so polling never stops early.
  - Upload timeout 120s; poll request timeout 20s.
- Every failure is **one short message**, no title:

| Cause | Message |
| :--- | :--- |
| No network, timeout | No connection. Check your internet and try again. |
| `CAPTIONS_UNAVAILABLE` | Auto captions are unavailable right now. |
| `PROVIDER_FAILED`, `VALIDATION_FAILED` | Couldn't transcribe this audio. Try again. |
| `PAYLOAD_TOO_LARGE` | This video is too long for auto captions. |
| `NOT_FOUND` while polling | Captions expired before they arrived. Try again. |
| 10 minutes passed | Captions took too long. Try again. |
| Completed with no words | No speech found. |

- **Cleartext for the LAN test server, debug only**: `android/app/src/debug/AndroidManifest.xml`
  sets `android:usesCleartextTraffic="true"` on `<application>`. Release has no cleartext; the
  deployed server must be HTTPS.
- Tests drive both classes through `package:http/testing.dart`'s `MockClient` — no network.

### Access gate

`CaptionAccess.ensureAllowed(BuildContext) → Future<bool>`, called once after Generate and before
any audio is rendered. **It returns true today.** The sign-in sheet and the credit check replace
its body later; nothing else in this design changes when they do.

### Progress and cancel

A modal sheet — Preparing audio, Uploading, Listening, Placing — with Cancel. **Modal on
purpose**: the audio is a snapshot of the timeline, and a clip moved while the server listens
would put every later word in the wrong place. Cancel stops the render, aborts the upload, or
stops polling (the server job finishes and expires on its own).

### Words → captions

Pure functions in `logic/captions/`, tested first:

- **`rebuildTranscriptSpacing(text, words)`** — the server drops ElevenLabs' spacing tokens, so
  each word's leading separator is recovered by finding the words, in order, in the transcript
  `text`. Chinese and Japanese get no spaces inserted; a word not found falls back to one space.
- **`groupCaptionWords(words, length)`** breaks a caption:
  - after sentence-ending punctuation (`. ! ? …` and `。！？`);
  - before a word that follows a pause of **0.6s** or more (`kCaptionPauseBreakSeconds`);
  - at the length limit — **Word**: 1 word; **Phrase**: 3 words or 20 characters; **Line**: 7
    words or 32 characters (characters are grapheme clusters, separators included).
- **Timing**: a caption starts at its first word's start and ends at its last word's end plus a
  hold of up to **0.4s** (`kCaptionHoldSeconds`), never past the next caption's start — so a
  caption does not flicker off between two phrases. A caption shorter than **0.3s**
  (`kMinCaptionSeconds`) is extended into the following gap where there is room.
- All times are whole milliseconds, the precision a draft stores.

### Placement

- One **caption lane**: `firstFreeLane` over the whole caption range, from lane 0, so captions
  never land on top of existing text and all sit on one lane (lane rules keep them apart).
- **The default look** (Stages 1–3) is the Subtitle template's look — white, black outline, a
  soft shadow — with **no in/out animations**: a half-second fade on a one-second caption is most
  of its life.
- **Lower third**: the Subtitle template's placement. **Box width 85% of the canvas**
  (`boxWidth`, reference px) so every caption wraps at the same width.
- Every caption carries the set's `captionSetId` and its `captionWords`.
- **One undo step**, snapshotted when captions are placed — the modal progress means nothing
  else changed while the server listened.
- **Replace**: with a set present, Generate asks "Replace captions?"; yes removes every overlay
  of the set and places the new one, still one undo step.
- The timeline gutter shows `LucideIcons.subtitles` for a lane holding captions.

### Export safety

Two gaps a long caption set would hit, fixed in Stage 1 because Stage 1 is when a project first
carries a hundred texts:

- **Image textures are never freed during an export.** `OverlayRenderer.imageTextures` only
  empties on full release, so every text atlas of a two-minute captioned video would be resident
  at once — hundreds of MB on a low-end GPU. In export (the clock only moves forward), a texture
  is released once the export clock passes its overlay's end.
- **Fonts are not awaited before rasterising.** Nothing calls `GoogleFonts.pendingFonts()`, so a
  font still downloading when export starts is rasterised in the fallback face while the preview
  shows the real one. `exportVideo` awaits pending fonts before `_rasterizeTextOverlays`.

## Stage 2 — Edit

- **Batch edit sheet** (`CaptionBatchSheet`), from the selected caption's **Captions** tool,
  opened scrolled to that caption. Taller than the preview sheets (the audio library's 0.7):
  it is a list to read and type into, and it rides above the keyboard.
  - One row per caption: its start time (`0:04.2`) and a text field.
  - **Tap the time** → the playhead jumps there and the caption is selected.
  - **Type** → the caption updates live; **one undo step per field focus**.
  - **Split at the cursor** (snapped to the nearest word boundary), **merge with the next**, and
    **delete**, as row actions. The timeline Split tool stays off for text — the user's earlier
    decision; splitting a caption is a list action only.
  - **Delete all captions** in the header, one undo step.
- **`retimeCaptionWords(oldText, oldWords, newText)`** keeps timing through a word fix. Old and
  new words are aligned by longest common subsequence on normalised tokens (lower case,
  punctuation stripped). Matched words keep their times exactly; an unmatched run shares the time
  between its matched neighbours, weighted by length; with no match at all, the words share the
  caption's span. Words are whitespace-separated, except that each character of a script written
  without spaces (CJK) is its own word — matching what the provider returns for those languages.
  **The normal text editor uses the same function**, so a fix made either way keeps timing.
- **Merge** joins the texts with the separator `rebuildTranscriptSpacing` would use (a space,
  none between two CJK characters); the words follow, rebased to the merged start.
- **Trim**: moving a caption's left edge by Δ shifts every word by −Δ, so each word stays at the
  same moment in the video. A right trim changes nothing. A move changes nothing (times are
  relative).
- **Re-cut**: changing Length after generating regroups every word of the set — edits included —
  with `groupCaptionWords`, keeping the look and placement of the set's first caption. One undo
  step.
- **Set-wide placement**: moving, pinching, rotating or resizing the box of one caption on the
  canvas applies the same change to every caption in its set, one undo step — a caption that sits
  somewhere else each second reads as a fault. A keyframed caption moves its whole path, as a
  duplicate's nudge does. Keyframes themselves stay per caption.
- Changing Source or Language needs a new transcription: it is Generate again, with Replace.

## Stage 3 — Word highlight

### One catalog, three consumers

`logic/captions/caption_highlight_catalog.dart` defines each style as a **pure function**
`stateAt(t, words, i)` → `WordHighlightState` (`highlighted` bool, `fill` 0..1, `scale`,
`opacity` 0..1, `pill` 0..1), `t` in caption-relative seconds. The preview painter, the Kotlin
port and the preset tiles read it; nothing else describes a highlight — the text-animation
catalog's rule.

A word is **active from its start until the next word starts** (the last word: until its end
plus the hold), so the highlight never drops out in the gap between two words.

| Style | What it does |
| :--- | :--- |
| None | Nothing. |
| Colour | The active word is drawn in the highlight colour. |
| Pop | Colour, plus the word scales to 115% and settles back over 0.25s. |
| Pill | A rounded box in the pill colour behind the active word, fading in over 0.08s. |
| Karaoke | The highlight colour sweeps across each word over its spoken span; spoken words stay lit. |
| Reveal | Words appear as they are spoken (0.08s fade). |
| Focus | Words not being spoken are dimmed to 50%. |

**Colour switches exactly at the word boundary, never blended.** A glyph drawn half in each look
would cast its shadow twice. Ramps (0.08s, `kHighlightRampSeconds`) apply only to scale, pill and
opacity, which have one drawing each.

The highlight **combines with the caption's in/out/loop animations**: opacity multiplies, scale
multiplies, offsets add. Pop scales about the **word's** centre, converted to per-glyph offsets,
so the word swells as one piece rather than each letter in place.

**Right-to-left words** (a first strong character in Hebrew/Arabic ranges) sweep right to left.

**Choosing one**: the caption sheet's Highlight row — the seven styles as chips, and a colour row
(the pill colour for Pill) — writes `highlight` on every caption in the set, one undo step. New
captions are generated with the set's current highlight. Stage 4's presets set the same fields.

### Preview

`TextOverlayPainter` takes its per-glyph path whenever a caption's highlight style is not None.
Each glyph finds its word by `charIndex`. Order: box → pills → glyphs. A highlighted glyph is
painted from the overlay with its fill colour replaced by the highlight colour (outline and
shadow unchanged). Karaoke paints the base glyph clipped to the unswept side and the highlight
glyph clipped to the swept side — complementary clips, so no shadow is drawn twice.

### Export

- The atlas stores each glyph **twice** — base look and highlight look, identical cell sizes —
  plus **one pill cell per word** (a rounded rect at the word's ink bounds plus padding, in the
  pill colour) and **one box cell** (below).
- The glyph table gains the highlight cell's atlas rect and the glyph's word index; the overlay
  gains the word timings and the highlight settings.
- Kotlin `CaptionHighlightCurves.kt` ports the catalog, pinned to Dart by
  `test/fixtures/caption_highlight_fixture.json` (copy under `android/app/src/test/resources/`),
  regenerated by a `tool/` script — the text-animation fixture's mechanism, with its caveat: it
  catches divergence tomorrow, never a wrong curve today.
- **Karaoke is geometry, not a shader**: a glyph straddling the sweep line becomes two quads — base
  on one side, highlight on the other — through the exact-rect `srcRect`/`boxRect` placement
  `OverlayRenderer.Draw` already has.

### The background box becomes its own quad

Today a text with a background box exports through the flat raster, because the glyph pass draws
letters only — and so cannot animate letter by letter, and would not highlight. The box is now
**one atlas cell**, drawn at `layout.backgroundRect` before the glyphs with the overlay's
whole-block state, exactly as the preview already draws it (one rect behind every glyph that does
not move with the letters). Boxed caption styles highlight; and the limit lifts for all text —
the boxed-text fallback warning goes, and the template catalog's "a boxed template uses only
whole-block animations" rule is retired with its test.

## Stage 4 — Caption styles

- **A bundled default font.** Montserrat Bold (SIL OFL), registered as its own family,
  `Montserrat Bold`, in `customBundledFonts`, and the default for new text and new captions.
  Bundled because the default must look the same on every phone, online or not; today's default,
  Roboto, is fetched at runtime and falls back to whatever the phone's system face is. **Drafts
  keep Roboto**: `fromJson` still reads a missing font as `Roboto`. No weight field is added: a
  weight is a family of its own. Every other font stays download-on-demand from the server.
- **`kCaptionPresets`** — a look plus a highlight style and its colours. The caption sheet shows
  them as a grid of `TextPreviewTile`s (three to a row, `kTextPreviewGrid`) playing sample words
  with synthetic timings, the clock held while the grid scrolls. The set's current preset is
  highlighted by `isAppliedTo`, not remembered. A test pins every preset: font in `allFonts`,
  highlight id resolves, placement on canvas, shadow within the Style tab's ranges.
- **Choosing a preset restyles the whole set**, one undo step.
- **Apply to all captions.** For a caption, the text editor shows an `ApplyToAllToggle`
  ("Apply to all captions", on by default); while on, look edits reach every caption in the set.
- **The look has one definition.** `TextLook.of(overlay)` / `look.applyTo(overlay)` replaces the
  field list `TextTemplate.restyle` and `isAppliedTo` spell out today, and captions reuse it — so
  a look field added later reaches templates and captions together.

## Persistence

`captionSetId`, `captionWords` and `highlight` serialise on the text overlay and are omitted
when absent; `captionSettings` on the draft is omitted when null. Defensive on read: a malformed
word is dropped, never thrown on; offsets are clamped into the text; `end < start` is clamped.

## Testing

- **Pure logic, test first**: spacing rebuild, grouping (every break rule, every limit, hold,
  minimum), retiming (fix one word, insert, delete, rewrite, CJK), trim compensation, re-cut,
  highlight curves at every boundary.
- **Server client** against `MockClient`: registration, token reuse, 401 re-register, upload
  shape (field, content type, key), key reuse on retry, poll to completion, every error code,
  timeout.
- **Kotlin**: `MixConfig` (export defaults unchanged, mono downmix, unity gain keeps the
  crossfade), highlight port against the fixture, texture release on the export clock.
- **Widgets**: the caption sheet, progress and cancel, the Auto captions tool hidden without a
  server address, the batch list, the presets grid counted against the catalog.
- **Mutation checks** on the tests that could pass vacuously, as usual.
- Each stage ends with a device checklist; the stage is not merged until it passes.

## Out of scope

- Sign-in, users, credits — only the access gate's hook exists.
- Translation / bilingual captions, filler-word removal, speaker labels, keyword emphasis, auto
  emoji.
- Captions following later clip edits: once placed they are text on the timeline, as in CapCut.
- More than one caption set per project.
- The timeline Split tool for text.
- Trimming silence before upload to save cost — a credits-phase optimisation.
