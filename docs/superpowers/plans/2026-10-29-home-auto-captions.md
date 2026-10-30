# Auto captions from Home — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. The owner's standing
> rule is native execution with no subagents, the final review included (a self-review, said so in
> the final message). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home's first tool card, **Auto captions**, opens a video in the editor's own *captions
mode* (Ready → Generating → Done, with Edit words, Style, Colour, Export and ✎ to the full editor),
and Privacy Strip leaves the app.

**Architecture:** Captions mode is a flag on `VideoEditorScreen`, so the project, the preview
engine, the caption run, the styles and the export are the editor's own. Its build swaps the
editor's layout for a pure `CaptionsModeView` (tested without a device); its decisions live in
pure rules (`captions_mode.dart`); and the caption run moves out of `CaptionProgressSheet` into a
`CaptionRun` that the sheet and the new view both draw.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, Riverpod `StateNotifier`, go_router, image_picker,
the native Media3/GL preview and export engine (unchanged), Kotlin (one file deleted).

**Spec:** `docs/superpowers/specs/2026-10-29-home-auto-captions-design.md`

## Global Constraints

- Android first; `minSdk` 24; the low-end target — captions mode uses the editor's one preview
  engine and adds no decoder.
- Captions mode never saves a draft, at any step; nothing of it reaches Recent Edits until ✎.
- Credits are priced and charged exactly as in the editor: the silent quote; only a shortfall shows.
- No second caption pipeline, preview or export path. No ads or sign-in anywhere they do not
  already appear.
- Colours from `AppColors`, motion from `AppMotion`, glyphs from `lib/core/theme/lucide_icons.dart`,
  minimal copy (no explanatory line beside a control that shows its state).
- Tests first. `flutter analyze --no-pub` ends at or under the baseline of **43** issues, none in a
  file the task touched.
- Commits: stage files by name; every message ends with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; never push. Branch
  `feat/home-auto-captions`.

## Review Focus

1. **The phone's Back on Done**, not the ‹ button, with nothing kept → the same "Discard these
   captions?" question. Pinned in Task 4 ("the phone's Back is the back button").
2. **A run stopped (Cancel, Back, the screen closing) whose words land afterwards** → never placed,
   no Done step, no notification from a disposed run. Pinned in Task 1 ("a stopped run never
   delivers its late words").
3. **Generate tapped twice, or again while the sign-in sheet is up** → one run, one charge. Pinned
   in Task 1 ("start twice is one run") and Task 4 ("Generate is off while a run is being
   started"); Task 5 passes `onGenerate: null` while one is starting or running.
4. **An export discarded on the export screen** → Back on Done still asks; only a saved or shared
   export counts. Pinned in Task 3 ("a discarded export closes saying nothing was kept") and Task 2
   ("Back … asks on Done until an export is kept").
5. **A tap on the home screen widget while captions are being made or sit unkept** → the app only
   comes forward; after ✎ the editor's own rules. Pinned in Task 1 ("holds the app from start until
   it is stopped") and Task 2 ("the app is held on Done until an export is kept, and never after ✎").

---

### Task 1: The caption run, apart from the sheet that draws it

**Files:**
- Create: `lib/features/video_editor/services/caption_run.dart`
- Create: `test/support/caption_pipelines.dart`
- Create: `test/features/video_editor/services/caption_run_test.dart`
- Modify: `lib/features/video_editor/widgets/panels/caption_progress_sheet.dart` (the state class)
- Regression, unchanged: `test/features/video_editor/widgets/auto_caption_sheets_test.dart`

**Interfaces:**
- Consumes: `CaptionPipeline.run(request, onProgress:, onShortfall:)` and `.cancel()`,
  `CaptionCancelled`, `captionErrorMessage(Object)` (`services/caption_errors.dart`), `HeldWork`,
  `CreditQuote`.
- Produces:

```dart
// lib/features/video_editor/services/caption_run.dart
class CaptionRun extends ChangeNotifier {
  CaptionRun({required CaptionPipeline pipeline, required this.request, HeldWork? heldWork});
  final CaptionRequest request;
  CaptionStage get stage;          // preparing at first
  double? get progress;            // 0 at first; null while the stage reports none
  Object? get failure;             // what stopped it, while shown
  String? get error;               // captionErrorMessage(failure)
  CreditQuote? get shortfall;      // while the balance does not cover the price
  List<CaptionDraft>? get drafts;  // set once, when the words land
  void start();                    // takes the hold and runs; a second call does nothing
  void retry();                    // after a failure: the same pipeline, so the same upload key
  void earned(int balance);        // enough carries the run on; too little updates the shortfall
  @override
  void dispose();                  // cancels an unfinished run, answers a pending shortfall
                                   // false, lets the hold go; notifies nothing afterwards
}
String captionStageLabel(CaptionStage stage); // the sheet's lines
```

```dart
// test/support/caption_pipelines.dart
const kHelloTranscript;  // CaptionTranscript 'Hello', one word 0.2–0.5 s
const kSoundRendered;    // CaptionAudioResult, hasSound true, 1 s
const kCoveredQuote;     // CreditQuote(credits: 0, balance: 94, enough: true)
CaptionPipeline fakeCaptionPipeline({
  required Future<CaptionAudioResult> Function(void Function(double) onProgress) render,
  Future<CaptionTranscript> Function()? transcript,       // default kHelloTranscript
  Future<CaptionJobStart> Function(String key)? upload,   // default an instant job
  CreditQuote quote = kCoveredQuote,
  void Function()? onCancel,
  String Function()? newKey,
});
```

- [ ] **Step 1: Write the failing tests** in `caption_run_test.dart`. Every run is made with
  `heldWork: HeldWork()`, so no test shares the app's.

```dart
test('reports each stage, then the words')
  // render pending: stage preparing, progress 0 · render done: stage listening, progress null
  // · transcript done: drafts!.single.text == 'Hello'; the listener heard each change
test('a failure gives its line; retry runs again under the same upload key')
  // upload throws const SlimshotApiException(SlimshotApiException.network) once:
  // failure is SlimshotApiException, error == captionErrorMessage(failure)
  // · retry(): error null, then drafts set; keys the uploads saw == ['k1', 'k1']
test('a shortfall waits; earning enough carries the run on')
  // quote CreditQuote(credits: 30, balance: 0, enough: false): shortfall!.credits == 30,
  // uploads 0 · earned(30): shortfall null, then drafts set, uploads 1
test('earning too little updates the shortfall and waits')
  // earned(10): shortfall!.balance == 10, uploads 0
test('stopped on its shortfall, a run uploads nothing')
  // dispose() while shortfall != null; drain microtasks: uploads 0, nothing thrown
test('a stopped run never delivers its late words')
  // transcript pending · dispose() · complete the transcript: drafts null, no listener call
  // after dispose, onCancel called once
test('holds the app from start until it is stopped')
  // held.isHeld: false before start(), true after, false after dispose()
test('start twice is one run')
  // start(); start(): render called once
test("the stage lines are the sheet's")
  // preparing 'Preparing audio', uploading 'Listening', listening 'Listening',
  // placing 'Placing captions'
```

- [ ] **Step 2: Run** `flutter test test/features/video_editor/services/caption_run_test.dart`
  Expected: FAIL — compilation error, `CaptionRun` / `caption_run.dart` not found.
- [ ] **Step 3: Implement `CaptionRun` and `captionStageLabel`.** The bodies are today's
  `_CaptionProgressSheetState` `_run`, `_retry`, `_earned`, `_showShortfall` and `dispose`, moved
  over: `setState` becomes `notifyListeners()` behind a disposed flag, `CaptionCancelled` stays
  silent, the hold is `heldWork ?? HeldWork.instance` from `start()` to `dispose()`.
- [ ] **Step 4: Run the same command.** Expected: All tests passed.
- [ ] **Step 5: Put `CaptionProgressSheet` on the run.** Constructor, keys and copy unchanged.
  `initState` makes `CaptionRun(pipeline: widget.pipeline, request: widget.request)`, listens,
  starts; the listener pops with `run.drafts` once they land, else `setState`; Try again is
  `run.retry`; the earn block's `onEarned` is `run.earned`; `dispose` disposes the run; `_label`
  goes for `captionStageLabel`.
- [ ] **Step 6: Run** `flutter test test/features/video_editor/widgets/auto_caption_sheets_test.dart test/features/video_editor/services/`
  Expected: All tests passed (the sheet's tests untouched).
- [ ] **Step 7: Commit** — `refactor(captions): the caption run, apart from the sheet that draws it`.

### Task 2: Captions mode's rules

**Files:**
- Create: `lib/features/video_editor/logic/captions/captions_mode.dart`
- Test: `test/features/video_editor/logic/captions/captions_mode_test.dart`

**Interfaces:**
- Consumes: `CaptionFailure` (`services/caption_errors.dart`).
- Produces:

```dart
enum CaptionsStep { ready, generating, done }
CaptionsStep captionsStepFor({required bool running, required bool hasCaptions});
/// Only a soundless video: nothing was uploaded and trying again cannot help.
bool runFailureReturnsToReady(Object? failure);
enum CaptionsBack { leave, stopRun, askDiscard }
class CaptionsModeSession {
  bool exportKept = false;      // an export of the captions was saved or shared
  bool openedInEditor = false;  // ✎: an ordinary editor project from here on
  CaptionsBack backAt(CaptionsStep step);
  bool holdsWorkAt(CaptionsStep step);  // the run holds itself while Generating
  List<String> picksToDeleteOnLeave(List<String> picks);
}
```

- [ ] **Step 1: Write the failing tests.**

```dart
test('a run is Generating; captions without one are Done; neither is Ready')
  // (running, hasCaptions): (t,f) generating · (t,t) generating · (f,t) done · (f,f) ready
test('a set emptied through Edit words is Ready again')       // (f,f) → ready
test('only a soundless video goes back to Ready')
  // CaptionFailure(noSound) true · CaptionFailure(noSpeech) false
  // · SlimshotApiException(network) false · null false
test('Back leaves Ready, stops a run, and asks on Done until an export is kept')
  // ready leave · generating stopRun · done askDiscard · exportKept = true → done leave
test('the app is held on Done until an export is kept, and never after ✎')
  // done true · ready false · generating false · exportKept → done false
  // · a session with openedInEditor → false at every step
test("leaving deletes the picks, unless ✎ made them an editor project's")
  // ['/cache/a/v.mp4'] → same list · openedInEditor → []
```

- [ ] **Step 2: Run** `flutter test test/features/video_editor/logic/captions/captions_mode_test.dart`
  Expected: FAIL — `captions_mode.dart` not found.
- [ ] **Step 3: Implement** the file to the interface above.
- [ ] **Step 4: Run the same command.** Expected: All tests passed.
- [ ] **Step 5: Commit** — `feat(captions): the rules of captions mode`.

### Task 3: An export says whether its file was kept; the captions' discard question

**Files:**
- Modify: `lib/core/utils/result_exit.dart` (a `kept` getter)
- Modify: `lib/screens/export_video_screen.dart` (`_cancelExport`, `_close`)
- Modify: `lib/core/widgets/discard_dialog.dart`
- Test: `test/core/utils/result_exit_test.dart`, `test/screens/export_video_screen_test.dart`,
  `test/core/widgets/discard_dialog_test.dart`

**Interfaces:**
- Produces: `bool get kept` on `ResultExit`. `ExportVideoScreen`'s route completes with `true` when
  its file was saved or shared before it closed, `false` otherwise (cancelled, discarded, failed).
  `const String kDiscardCaptionsQuestion = 'Discard these captions?'` and
  `Future<bool> confirmDiscardCaptions(BuildContext context)` — `confirmDiscard`'s dialog with that
  question (both through one private builder taking the question).

- [ ] **Step 1: Write the failing tests.** In the export test, `openExport` records what
  `Navigator.push<bool>` completes with in a `results` list.

```dart
test('kept is false until something is kept')          // false; markKept() → true
testWidgets('a shared export closes saying it was kept')            // results == [true]
testWidgets('a discarded export closes saying nothing was kept')    // ✕, Discard → [false]
testWidgets('a cancelled export says nothing was kept')  // exporting, the phone's Back → [false]
testWidgets('the captions question: Discard is yes, Cancel stays')
  // 'Discard these captions?' shown; Discard → true; Cancel → false
```

- [ ] **Step 2: Run** `flutter test test/core/utils/result_exit_test.dart test/screens/export_video_screen_test.dart test/core/widgets/discard_dialog_test.dart`
  Expected: FAIL — `kept` and `confirmDiscardCaptions` undefined.
- [ ] **Step 3: Implement.** `_close` pops with `_exit.kept`; `_cancelExport` pops with `false`.
- [ ] **Step 4: Run the same command.** Expected: All tests passed.
- [ ] **Step 5: Commit** — `feat(export): the export says whether its file was kept`.

### Task 4: The captions screen's view

**Files:**
- Modify: `lib/features/video_editor/widgets/panels/caption_sheet_parts.dart` (two pill rows)
- Modify: `lib/features/video_editor/widgets/panels/auto_caption_sheet.dart` (uses them)
- Modify: `lib/features/compression/widgets/compress_scaffold.dart` (`CompressProgressRing`)
- Create: `lib/features/video_editor/widgets/captions_mode/captions_mode_view.dart`
- Test: `test/features/video_editor/widgets/captions_mode_view_test.dart`; regression
  `auto_caption_sheets_test.dart` and `test/features/compression/`

**Interfaces:**
- Consumes: Task 1 `CaptionRun`, `captionStageLabel`, `fakeCaptionPipeline`; Task 2 `CaptionsStep`;
  `shortfallLine`; `CaptionPresetTile`; `CaptionColorRow`; `captionHighlightUsesColor`;
  `kCaptionHighlightColors`; `kCaptionPresets`; `kTextPreviewGrid`;
  `holdPreviewClockWhileScrolling`; `CompressTopBar`, `CompressGlassIconAction`,
  `CompressBottomBar`, `CompressPrimaryButton`, `CompressGlassButton`, `SheetSectionLabel`.
- Produces:

```dart
// caption_sheet_parts.dart — AutoCaptionSheet's two rows, values, labels and keys unchanged
class CaptionLanguagePills extends StatelessWidget {
  const CaptionLanguagePills({super.key, required String? selected, required ValueChanged<String?> onSelected});
}
class CaptionLengthPills extends StatelessWidget {
  const CaptionLengthPills({super.key, required CaptionLength selected, required ValueChanged<CaptionLength> onSelected});
}
// compress_scaffold.dart: CompressProgressRing(double? progress, String? batchLine)
//   null progress → an indeterminate ring with no number

// captions_mode_view.dart
const double kCaptionsCardHeightFraction = 0.45;
class CaptionsModeView extends StatefulWidget {
  const CaptionsModeView({
    super.key,
    required CaptionsStep step,
    required Widget preview,            // the editor's canvas
    required double aspectRatio,        // the project's frame
    required VoidCallback onBack,       // ‹ and the phone's Back
    required String? language,          // null: Auto detect
    required CaptionLength length,
    required ValueChanged<String?> onLanguage,
    required ValueChanged<CaptionLength> onLength,
    required VoidCallback? onGenerate,  // null: off
    String? notice,                     // a line under the card on Ready
    CaptionRun? run,                    // Generating's
    required VoidCallback onCancel,
    Widget Function(CreditQuote quote, void Function(int balance) onEarned)? earnCredits,
    required ({TextLook look, CaptionHighlight highlight}) style,  // what the set wears
    required ValueChanged<CaptionPreset> onPreset,
    required ValueChanged<Color> onColor,
    required VoidCallback onEditWords,
    required VoidCallback? onExport,    // null while an export opens
    required VoidCallback onOpenEditor,
    List<CaptionPreset> presets = kCaptionPresets,
  });
}
```

Keys: `captions_back` (the top bar's `backKey`), `captions_title`, `captions_open_editor`,
`captions_card`, `captions_generate`, `captions_notice`, `captions_ring`, `captions_writing`,
`caption_progress_stage`, `caption_error`, `caption_price`, `captions_cancel`, `captions_retry`,
`captions_edit_words`, `captions_style_<preset.id>`, `captions_color_<i>`, `captions_export`; the
pills keep `caption_language_<code|auto>` and `caption_length_<name>`.

The layout, from mockup A:
- A `Scaffold` on `AppColors.background` — plain dark, no Home light — in a
  `PopScope(canPop: false)` whose pop calls `onBack`.
- `CompressTopBar(title: 'Auto captions')`; its trailing on Done only:
  `CompressGlassIconAction(icon: LucideIcons.pencil, label: 'Open in editor')`.
- A scrolling body. The card: `kCaptionsCardHeightFraction` of the screen's height, width by
  `aspectRatio`, both shrunk to fit the width less 16 px gutters; centred; corners 16; holding
  `preview`. On Generating a 50% black scrim over it and `CompressProgressRing` (progress × 100,
  or null) centred.
- Ready: `SheetSectionLabel('Language')` + `CaptionLanguagePills`, `SheetSectionLabel('Length')` +
  `CaptionLengthPills`; `notice` under the card when set (13 px, `textSecondary`).
- Generating: "Writing captions…" (15 px, w700, `textPrimary`) and the stage line (13 px,
  `textSecondary`) under the card; on a failure the error line in their place; on a shortfall
  `shortfallLine(credits, balance)` and `earnCredits(quote, run.earned)`.
- Done: an "Edit words" chip (`LucideIcons.caseSensitive`) under the card;
  `SheetSectionLabel('Style')` + one scrolling row of `CaptionPresetTile`s, 96 wide at
  `kTextPreviewGrid.childAspectRatio`, 10 apart, the selected one whose
  `look.sameLookAs(style.look) && highlight == style.highlight`; `SheetSectionLabel('Colour')` +
  `CaptionColorRow(enabled: captionHighlightUsesColor(style.highlight.style))`.
- Pinned `CompressBottomBar`: Ready "Generate captions" (`LucideIcons.subtitles`); Generating
  "Cancel" (glass), with "Try again" (primary, `LucideIcons.rotateCcw`) beside it on a failure;
  Done "Export" (`LucideIcons.download`).
- The tiles' clock: one `AnimationController` (1800 ms, repeating) running only on Done, held
  while the style row scrolls (`holdPreviewClockWhileScrolling`).

- [ ] **Step 1: Write the failing tests.** A `pumpView` helper on a 390×844 phone, with
  `preview: const ColoredBox(key: Key('preview'), color: Colors.blue)` and recording callbacks.
  Done tests pump frames — the tiles loop, so `pumpAndSettle` would time out.

```dart
testWidgets('Ready: the title, Language and Length on the defaults, Generate — no ✎, no styles')
  // caption_language_auto, caption_length_phrase shown; tap caption_length_word → [word];
  // tap caption_language_fr (ensureVisible) → ['fr']; tap captions_generate → 1;
  // captions_open_editor and CaptionPresetTile: findsNothing
testWidgets('Ready settles: no tile animates off Done')      // pumpAndSettle() completes
testWidgets('Generate is off while a run is being started')  // onGenerate null → tap → 0
testWidgets('Ready says why a run came back')                // notice 'No sound to caption.' shown
testWidgets('Generating: the ring and its percentage over the picture, the stage, Cancel')
  // render reports 0.5: '50%' inside captions_card, 'Writing captions…', 'Preparing audio',
  // the preview still there; tap captions_cancel → 1; captions_open_editor findsNothing
testWidgets('a stage with no number spins without one')
  // render done: 'Listening' shown, no text containing '%'
testWidgets('a failure shows its line, Cancel and Try again')
  // render throws PlatformException(code: 'x'):
  // caption_error == captionErrorMessage(PlatformException(code: 'x'));
  // tap captions_retry → 'Preparing audio' again
testWidgets('a shortfall says how many, with the ways to earn, in place')
  // quote 30 / 0: caption_price == shortfallLine(30, 0); earnCredits' Text('earn') shown;
  // captions_cancel shown
testWidgets('Done: Edit words, the styles with the current one marked, the colours, Export and ✎')
  // style = presets.first's look and highlight → only captions_style_<first.id> isSelected;
  // tap captions_style_<presets[1].id> → [presets[1]]; tap captions_color_2 →
  // [kCaptionHighlightColors[2]]; captions_edit_words, captions_export, captions_open_editor → 1 each
testWidgets('the colours are dimmed and deaf where the style lights in no colour')
  // highlight CaptionHighlight(style: CaptionHighlightStyle.reveal): tap captions_color_0 → []
testWidgets("the phone's Back is the back button")
  // tester.binding.handlePopRoute() → backs 1; tap captions_back → 2
testWidgets("the card keeps the project's frame")
  // captions_card width / height within 1e-2 of 9 / 16
testWidgets('no step overflows a small phone with large text')
  // each step on 320×568 at TextScaler.linear(1.3): tester.takeException() isNull
```

- [ ] **Step 2: Run** `flutter test test/features/video_editor/widgets/captions_mode_view_test.dart`
  Expected: FAIL — `captions_mode_view.dart` not found.
- [ ] **Step 3: Move AutoCaptionSheet's Language and Length rows into `CaptionLanguagePills` and
  `CaptionLengthPills`**, and make `CompressProgressRing`'s progress nullable.
- [ ] **Step 4: Implement `CaptionsModeView`** to the layout above.
- [ ] **Step 5: Run** `flutter test test/features/video_editor/widgets/ test/features/compression/`
  Expected: All tests passed.
- [ ] **Step 6: Commit** — `feat(captions): the captions screen's view`.

### Task 5: Captions mode in the editor

**Files:**
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart` (`saveDraft`, a setter)
- Modify: `lib/screens/video_editor_screen.dart`
- Modify: `lib/main.dart` (one route)
- Test: `test/features/video_editor/providers/draft_saving_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: `void VideoEditorNotifier.setSavesDraft(bool value)` — `saveDraft()` writes nothing
  while it is false; true by default. `VideoEditorScreen({…, bool captionsMode = false})`. The route
  `/edit/captions`, taking an `XFile` extra, opens `VideoEditorScreen(initialMedia: [file],
  captionsMode: true)` with the editor's page transition.

The screen is not widget-testable (no test pumps `VideoEditorScreen`: it needs the native engine),
so every decision it makes is one of Tasks 1–4's, tested there; this task wires them.

- [ ] **Step 1: Write the failing test.**

```dart
test('a project that keeps no draft writes none, and writes once it does')
  // state as in draft_project_edited_seconds_test (draftId 'd1', one asset and clip);
  // setSavesDraft(false); await saveDraft(): DraftService.getDraftById('d1') isNull;
  // setSavesDraft(true); await saveDraft(): isNotNull
```

- [ ] **Step 2: Run** `flutter test test/features/video_editor/providers/draft_saving_test.dart`
  Expected: FAIL — `setSavesDraft` undefined.
- [ ] **Step 3: Implement `setSavesDraft`.** A notifier field, not state: an undo snapshot must
  never turn saving back off after ✎.
- [ ] **Step 4: Run the same command.** Expected: All tests passed.
- [ ] **Step 5: Share the run's pieces.** Out of `_startAutoCaptions`, which then uses both with
  its behaviour unchanged: `({CaptionPipeline pipeline, void Function() close}) _newCaptionPipeline()`
  and `void _placeCaptionDrafts(List<CaptionDraft> drafts, CaptionRequest request)` (the
  `captionStyleForNewSet` read, the `CaptionSettings`, `placeCaptions`).
- [ ] **Step 6: `_exportVideo()` returns `Future<bool>`**: it awaits the export route, clears
  `isExporting`, and returns whether the file was kept (`false` on every early return and error).
- [ ] **Step 7: Captions mode.** `widget.captionsMode` sets `setSavesDraft(false)` in `initState`
  before `_loadMedia`, and seeds `_captionsMode`. State: `_captionsSession` (Task 2), `_captionRun`
  and its `close`, `_startingCaptions`, `_captionsLanguage` (null), `_captionsLength` (phrase),
  `_captionsNotice`, `_previewKey` (a `GlobalKey`). The step is
  `captionsStepFor(running: _captionRun != null, hasCaptions: state.hasCaptions)`.

| Handler | Does |
| :--- | :--- |
| `_generateCaptions` | Off while starting or running. `CaptionAccess.ensureAllowed`; pauses as `_startAutoCaptions` does; a `CaptionRun` on `_newCaptionPipeline()` with `CaptionRequest(source: video, language, length)`; listens; clears the notice; starts. |
| `_onCaptionRunChanged` | Drafts landed: end the run, `_placeCaptionDrafts`, park the playhead on the first caption's start (`updatePlaybackPosition` + `_seekNativePreviewToTimeline`), paused; prefetch `captionPresetFontNames(kCaptionPresets)`; sync the hold. A failure `runFailureReturnsToReady` accepts: end the run, show its `error` as the notice. Otherwise `setState`. |
| `_endCaptionRun` | Remove the listener, dispose the run, `close()` the client, refresh the account (`accountProvider.notifier.refresh()`), clear it. Cancel and Back while Generating. |
| `_captionsBack` | `_captionsSession.backAt(step)`: `stopRun` → `_endCaptionRun`; `askDiscard` → `confirmDiscardCaptions`, staying on no; then pop the route. |
| `_exportCaptions` | `exportKept \|= await _exportVideo()` — the editor's own defaults, HD 1080 at 30 fps, which captions mode never changes and offers no sheet for; sync the hold. Off while `isExporting`. |
| Edit words | `_showCaptionList()` — nothing is selected, so the list opens on the set's first caption; in captions mode it then `deselectAll()`s (a row tap selects) and syncs the hold (an emptied set is Ready again). |
| Style / Colour | `restyleCaptions(preset.look, preset.highlight)` / `setCaptionHighlight(style.highlight.copyWith(color: c))`; `style` is `captionStyleForNewSet(state.textOverlays)`. |
| `_openCaptionsInEditor` | `setSavesDraft(true)`, `openedInEditor = true`, sync the hold, `_captionsMode = false`. |
| `_syncCaptionsHold` | `HeldWork.instance` holds or releases `_captionsSession` per `holdsWorkAt(step)`. |

- [ ] **Step 8: The build.** One `_previewCanvas()` (the existing `VideoPreviewCanvas`, now with
  `key: _previewKey`) for both layouts, so ✎ moves the canvas rather than rebuilding it. After the
  build's listeners, `if (_captionsMode) return CaptionsModeView(…)` with
  `preview: GestureDetector(onTap: _togglePreview, child: IgnorePointer(child: _previewCanvas()))`,
  `aspectRatio` the project's, `onGenerate` null while there is no clip, while starting or while
  a run exists, and `earnCredits: (quote, onEarned) => EarnCreditsBlock(onEarned: onEarned)`.
- [ ] **Step 9: Dispose.** End a run without `setState`; release `_captionsSession`; when
  `widget.captionsMode`, `FileUtils.deleteTempFiles(_captionsSession.picksToDeleteOnLeave(picks))`.
- [ ] **Step 10: The route** `/edit/captions` in `main.dart`, beside `/edit/video`.
- [ ] **Step 11: Verify.** `flutter analyze --no-pub` → ≤ 43 issues, none in a touched file;
  `flutter test` → All tests passed; `flutter build apk --debug` → "Built
  build\app\outputs\flutter-apk\app-debug.apk".
- [ ] **Step 12: Commit** — `feat(captions): the editor's captions mode`.

### Task 6: Home — Auto captions in Privacy Strip's place

**Files:**
- Modify: `lib/screens/home_screen.dart` (the tool row; `_handleAutoCaptions`; `_handlePrivacyStrip` deleted)
- Test: `test/screens/home_cards_test.dart`

**Interfaces:**
- Consumes: the `/edit/captions` route (Task 5); `MediaPickerService.pickVideo()`.
- Produces: the card `ValueKey('home_auto_captions')`, title `'Auto\ncaptions'`, glyph
  `LucideIcons.subtitles`, first of the three, delays 250/300/350 in the new order.
  `_handleAutoCaptions` is `_handleCompressVideo`'s shape: one video, the same permission dialog
  (message "Please grant storage access to pick a video for captions."), pushing `/edit/captions`.

- [ ] **Step 1: Write the failing tests.** `_FakePicker` gains a `getVideo` override (the platform
  signature: `{required ImageSource source, CameraDevice preferredCameraDevice = CameraDevice.rear,
  Duration? maxDuration}`) that counts `videoPicks` and returns null.

```dart
testWidgets('the tools read Auto captions, Compress Video, Compress Photo, in that order')
  // left edges of the three titles strictly increase in that order; 'Privacy\nStrip' findsNothing
testWidgets('Auto captions wears the subtitles glyph')
testWidgets('a tap on Auto captions asks the gallery for one video')
  // videoPicks 1; with nothing picked the location stays /home
```
  The corner-tap loop keeps only Compress Photo; the solid-tiles test's titles become
  `['Auto\ncaptions', 'Compress\nVideo', 'Compress\nPhoto']`.
- [ ] **Step 2: Run** `flutter test test/screens/home_cards_test.dart` → Expected: FAIL (no Auto
  captions card).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the same command.** Expected: All tests passed.
- [ ] **Step 5: Commit** — `feat(home): Auto captions takes Privacy Strip's place`.

### Task 7: Privacy Strip leaves the app

**Files:**
- Create: `test/no_privacy_strip_test.dart`
- Delete: `lib/screens/privacy_screen.dart`, `lib/screens/privacy_result_screen.dart`,
  `lib/features/privacy/` (8 files), `test/features/privacy/` (4 files),
  `android/app/src/main/kotlin/com/techfamz/slimshotai/privacy/PhotoMetadataReader.kt`
- Modify: `lib/main.dart` (imports, `/privacy` and `/privacy/result`, `_holdsWork`'s
  `privacyProvider` check), `MainActivity.kt` (the reader's field, registration, release),
  `lib/core/services/ad_pacing.dart`, `ad_service.dart`, `work_ad.dart`,
  `lib/core/utils/result_exit.dart` (doc comment)
- Modify tests: `test/core/services/ad_pacing_test.dart`, `ad_service_test.dart`,
  `work_ad_test.dart`, `test/screens/result_files_test.dart`, `test/core/utils/result_exit_test.dart`
  (comment), `test/core/utils/file_utils_test.dart` (the `slimshot_temp_privacy_9a.jpg` fixture
  becomes `slimshot_temp_photo_9a.jpg`)

**Interfaces:**
- Produces: `AdPlacement` without `privacyStrip`; `AdService` without `privacyStripAds`;
  `kPhotoCompressionAdRule` a constant of its own with today's values —
  `WorkAdRule(leadIn: Duration(seconds: 1), evenIfQuick: true)`; `kPrivacyStripAdRule` gone.
  `PhotoInspector` (`features/compression/logic/`) stays.

- [ ] **Step 1: Write the failing guard test** — it reads every `.dart` under `lib/` and every
  `.kt`/`.xml` under `android/app/src/main/` and fails on `privacyStrip`, `PhotoMetadata`,
  `photo_metadata`, `features/privacy`, `PrivacyScreen`, `PrivacyResultScreen` or `'/privacy`
  (with the quote, so Settings' policy URL passes).
- [ ] **Step 2: Run** `flutter test test/no_privacy_strip_test.dart` → Expected: FAIL, naming
  `lib/main.dart` among others.
- [ ] **Step 3: Delete and edit** the files above. In the ad tests, Privacy Strip's cases go and
  photo compression's keep their assertions against `kPhotoCompressionAdRule` and
  `AdPlacement.photoCompression` (a second in, every job however fast, six minutes apart);
  `result_files_test` loses the strip's tests, imports and picks case.
- [ ] **Step 4: Run** `flutter test test/no_privacy_strip_test.dart test/core/ test/screens/`
  Expected: All tests passed.
- [ ] **Step 5: Run** `(cd android && ./gradlew :app:compileDebugKotlin)` → Expected:
  BUILD SUCCESSFUL.
- [ ] **Step 6: Commit** — `feat: Privacy Strip leaves the app`.

### Task 8: The notes, and the whole branch checked

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: CLAUDE.md.** A section "Auto captions from Home — the editor in captions mode"
  after the caption styles (Stage 4) section, **awaiting device verification**: the mode, the
  rules (no draft, the discard question and what counts as kept, Back per step, ✎, the hold), the
  view and the run shared with the progress sheet, and the device checks — Home order; a video
  with and one without sound; a shortfall carried on by an ad; Cancel mid-run; a style and a
  colour; Edit words, including emptying the set; Export, Save, Back without asking; Back with
  nothing kept; ✎ then leaving (the edit in Recent Edits); a home-widget tap on Done. The Privacy
  Strip section goes, and its mentions (`HeldWork`'s list, the temporary files section, Home's
  tool cards) are rewritten.
- [ ] **Step 2: Verify the branch.** `flutter analyze --no-pub` → ≤ 43 issues, none in a touched
  file; `flutter test` → All tests passed; `flutter build apk --debug` → the APK is built.
- [ ] **Step 3: Commit** — `docs: Auto captions from Home; Privacy Strip gone`.
