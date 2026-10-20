# Effects Track Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Effects become bars on the timeline's lanes — placed at the playhead, moved, trimmed,
stacked, keyframed — applied to the main video in preview and export alike, replacing the one
effect each clip carried.

**Architecture:** A Dart `EffectBarModel` list on the editor state shares the lanes with text,
photos, video overlays and audio (`lane_layout.dart`). One rule — which bars are drawn at an
instant, in lane order, within the 4-pass budget, at what intensity and shader progress — is
written in Dart (`effect_stack.dart`) and Kotlin (`EffectStack.kt`) and pinned together by a
fixture. The composer sends the bars as `effects`; the preview receives them on a light
`setEffects` channel, the export from the composed timeline. A Kotlin `EffectStackController`
builds every pass a timeline needs when the list arrives, so the render path only chooses among
built passes. Old drafts' clip effects become bars on load.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, Riverpod `StateNotifier`, Kotlin, OpenGL ES 2.0.

**Spec:** `docs/superpowers/specs/2026-10-20-effects-track-design.md`

## Global Constraints

- `flutter analyze --no-pub` stays at **44 issues**; `flutter test` fully green before every commit
  (read for `All tests passed!` and no `Failing tests`).
- Kotlin JVM tests: `cd android && ./gradlew.bat :app:testDebugUnitTest` (the `:app:` task, not the
  root one); results in `build/app/test-results/testDebugUnitTest/*.xml`.
- Colours from `AppColors`, never hard-coded; sheets open through `showEditorSheet`; UI copy
  minimal, no title echoing the tool.
- `copyWith` takes `Type? value` and `bool clearValue = false` for every nullable field;
  `toJson`/`fromJson` hand-written, `fromJson` never throws.
- Every timeline gesture is one undo step (`beginTimelineGesture` / `endTimelineGesture`); an
  action that changes nothing takes no step.
- Unknown effect ids degrade to no effect, never a crash.
- No `Random()`, frame counter or wall clock in anything an effect draws; the timeline clock only.
- Commits: `git commit -F <file>`, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  Never push.
- Values from the spec: new bar **3.0 s** (`kDefaultEffectBarSeconds`), minimum
  `kMinClipDurationSeconds`; `MAX_EFFECT_PASSES` / `kMaxEffectPasses` **4**; pass costs **blur 2,
  blur_in 2, glow 4, every other catalog effect 1**; toast copy **"<Label> is skipped: too many
  effects at once"**.

## Review Focus

1. **A bar whose effect id this build does not know** (a draft from a newer build): the project
   opens, the bar shows on the timeline as "Effect" and can be selected and deleted, and nothing is
   sent to the engine for it. Tests: Task 2 (model keeps the id), Task 5 (composer drops it),
   Task 7 (label fallback).
2. **A degenerate bar from a hand-edited draft** (end ≤ start, NaN, negative): read back as a bar
   of at least `kMinClipDurationSeconds` at a finite start; progress never divides by zero.
   Tests: Task 2, Task 3.
3. **Undo or redo across add → change → delete**: the selection never names a bar that is not
   there (the toolbar falls back to the main menu). Test: Task 4.
4. **A long migrated project with hundreds of bars of one effect, none overlapping**: one set of
   passes is built, not hundreds, and the payload is re-sent only when the bars change. Tests:
   Task 10 (controller), Task 11 (identity).
5. **The intensity slider dragged while playing**: playback pauses first, so a keyframed bar does
   not collect a trail of diamonds. Test: Task 4.

---

### Task 1: Pass costs, pinned on both sides

**Files:**
- Modify: `lib/features/video_editor/logic/effects/effect_catalog.dart`
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/EffectPassCosts.kt`
- Create: `test/features/video_editor/logic/effects/effect_stack_fixture_test.dart` (costs half now;
  Task 3 adds the cases)
- Create: `test/fixtures/effect_stack_fixture.json`, copy at `android/app/src/test/resources/effect_stack_fixture.json`
- Create: `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/EffectPassCostsTest.kt`

**Interfaces:**
- Produces (Dart): `VideoEffect.passCost` (`int`, constructor default `1`); `const int kMaxEffectPasses = 4;`
- Produces (Kotlin): `internal object EffectPassCosts { fun costOf(effectId: String?): Int }` — `0`
  for null/blank/unknown. A pure table with **no GL import**: `EffectShaders.passesFor` builds GL
  programs eagerly and cannot run on the JVM.
- Produces (fixture): `{"passCosts": {"<id>": n, …}, "cases": []}` — `cases` filled by Task 3.

- [ ] **Step 1: Write the failing Dart test** — `effect_stack_fixture_test.dart`:
  `test('every catalog effect has the pass cost the fixture records')` reads
  `test/fixtures/effect_stack_fixture.json`; expects `passCosts` keys == the catalog's ids, and
  `effect.passCost` equal to each. `test('the costs the renderer builds')`:
  `videoEffectById('blur')!.passCost == 2`, `blur_in` 2, `glow` 4, `vignette` 1. With
  `UPDATE_EFFECT_FIXTURE=1` the test writes the fixture instead (the `overlay_motion_fixture_test`
  pattern) and also writes the Android resources copy.
- [ ] **Step 2: Run** `flutter test test/features/video_editor/logic/effects/effect_stack_fixture_test.dart`.
  Expected: FAIL (`passCost` not defined).
- [ ] **Step 3: Implement** `passCost` on `VideoEffect` (`blur`, `blur_in`: 2; `glow`: 4) and
  `kMaxEffectPasses`. Generate the fixture: `UPDATE_EFFECT_FIXTURE=1 flutter test <file>`.
- [ ] **Step 4: Run** the Dart test. Expected: PASS.
- [ ] **Step 5: Write the failing Kotlin test** — `EffectPassCostsTest`: for every entry of the
  resource fixture's `passCosts`, `EffectPassCosts.costOf(id)` equals it; `costOf("nope") == 0`;
  `costOf(null) == 0`. Read with `FixtureJson`.
- [ ] **Step 6: Run** `cd android && ./gradlew.bat :app:testDebugUnitTest --tests "*EffectPassCostsTest"`.
  Expected: FAIL (unresolved `EffectPassCosts`). Implement the table; re-run. Expected: PASS.
- [ ] **Step 7: Commit** `feat(effects): every effect states its pass cost, pinned on both sides`.

### Task 2: The bar model, the state, the lanes and the project's end

**Files:**
- Create: `lib/features/video_editor/models/effect_bar_model.dart`
- Create: `lib/features/video_editor/logic/timeline/project_end.dart`
- Modify: `lib/features/video_editor/models/video_editor_state.dart`,
  `lib/core/models/draft_project.dart`,
  `lib/features/video_editor/logic/timeline/lane_layout.dart` (`laneSpansOf`),
  `lib/features/video_editor/providers/video_editor_notifier.dart` (`_laneSpans`, `_applyLanes`,
  `saveDraft`, `loadDraft`, `totalEditedDurationProvider`),
  `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart` (`_projectEndSeconds`),
  `lib/features/video_editor/widgets/timeline/scrollable_timeline.dart` (`_totalEditedDuration`)
- Test: `test/features/video_editor/models/effect_bar_model_test.dart`,
  `test/features/video_editor/logic/timeline/project_end_test.dart`,
  `test/features/video_editor/logic/timeline/lane_layout_test.dart` (add cases)

**Interfaces:**
- Produces:
  ```dart
  class EffectBarModel {
    const EffectBarModel({required this.id, required this.effectId, required this.start,
        required this.end, this.laneIndex = 0,
        this.intensity = const AnimatableDouble(baseValue: 1.0)});
    final String id; final String effectId;
    final double start; final double end;   // timeline seconds
    final int laneIndex; final AnimatableDouble intensity;
    double get duration;                    // end - start
    EffectBarModel copyWith({String? id, String? effectId, double? start, double? end,
        int? laneIndex, AnimatableDouble? intensity});
    Map<String, dynamic> toJson();          // id, effectId, start, end, laneIndex, intensity
    factory EffectBarModel.fromJson(Map<String, dynamic> json);
  }
  ```
- Produces: `VideoEditorState.effectBars` (`List<EffectBarModel>`, default `const []`),
  `selectedEffectBarId` (`String?`, `clearSelectedEffectBarId`), getter `selectedEffectBar`.
- Produces: `double projectEndSeconds({required List<VideoSegment> segments, required
  List<AudioTrackModel> audios, required List<TextOverlayModel> texts, required
  List<ImageOverlayModel> images, required List<VideoOverlayModel> videos, required
  List<EffectBarModel> effects})` — the composer's `_projectEndSeconds`,
  `totalEditedDurationProvider` and `ScrollableTimeline._totalEditedDuration` all return it.
- Produces: `laneSpansOf(..., required List<EffectBarModel> effects)`.
- Produces: `DraftProject.effectBars` (`List<Map<String, dynamic>>`, key `effectBars`, omitted when
  empty, `[]` when absent).

- [ ] **Step 1: Write the failing tests.**
  - `effect_bar_model_test.dart`: round-trips through JSON (keyframed intensity included); keeps an
    unknown `effectId` as written (Review Focus 1); `fromJson` with `end <= start`, `NaN` or a
    negative start gives a finite start ≥ 0 and `end - start >= kMinClipDurationSeconds`, and never
    throws on a missing or mistyped field (Review Focus 2).
  - `project_end_test.dart`: `test('an effect bar past the last clip moves the end')` — one 5 s clip
    and a bar 6–9 → `9.0`; and each other kind still counts (audio, text, image, video overlay).
  - `lane_layout_test.dart`: `laneSpansOf` includes bars; `firstFreeLane` steps past a bar.
  - A notifier test (`test/features/video_editor/providers/effect_bar_lanes_test.dart`):
    `moveLaneItem` and `trimLaneItem` on a bar id move/trim it under the lane rules; a draft saved
    and loaded keeps its bars; a draft without bars writes no `effectBars` key.
- [ ] **Step 2: Run** each file. Expected: FAIL (undefined names).
- [ ] **Step 3: Implement** the model, the state fields (every `select*` clears
  `selectedEffectBarId`; `deselectAll` clears it), `projectEndSeconds` and its three callers,
  `laneSpansOf`, `_applyLanes` writing `effectBars`, `trimLaneItem` writing a bar's `start`/`end`,
  `normalizeLanes` on load covering bars, and draft save/load.
- [ ] **Step 4: Run** the tests, then `flutter test` and `flutter analyze --no-pub`. Expected: all
  pass, 44 issues.
- [ ] **Step 5: Commit** `feat(effects): effect bars share the lanes and count toward the project's end`.

### Task 3: Which bars are drawn — the Dart rule and its fixture

**Files:**
- Create: `lib/features/video_editor/logic/effects/effect_stack.dart`
- Create: `lib/features/video_editor/logic/effects/effect_bar_placement.dart`
- Test: `test/features/video_editor/logic/effects/effect_stack_test.dart`,
  `test/features/video_editor/logic/effects/effect_bar_placement_test.dart`; extend
  `effect_stack_fixture_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class ActiveEffectBar {           // one bar drawn at an instant
    final EffectBarModel bar;
    final double intensity;         // resolved at whole-bar progress, clamped 0..1
    final double progress;          // the shader's clock
  }
  double effectBarProgressAt(EffectBarModel bar, double seconds);           // whole bar, 0..1; 1.0 for a zero span
  double effectBarShaderProgressAt(EffectBarModel bar, double seconds);     // introSeconds window from bar.start when the catalog gives one, else whole bar; rests at 1
  List<ActiveEffectBar> effectBarsDrawnAt(List<EffectBarModel> bars, double seconds);
  Set<String> skippedEffectBarIds(List<EffectBarModel> bars);               // skipped at any instant
  EffectBarModel? newlySkippedEffectBar(List<EffectBarModel> before, List<EffectBarModel> after);
  const double kDefaultEffectBarSeconds = 3.0;
  ({double start, double end}) newEffectBarSpan({required double playhead, required double projectEnd});
  ```
- `effectBarsDrawnAt` rule (the algorithm the tests pin): bars with `start <= seconds < end` whose
  `effectId` the catalog knows, sorted by `laneIndex`; walk them adding each **whole** bar whose
  `passCost` still fits within `kMaxEffectPasses`, skipping one that does not and continuing.
- `skippedEffectBarIds` checks the midpoint of every interval between consecutive bar edges (the
  drawn set is constant inside each).
- `newEffectBarSpan`: `start = playhead.clamp(0, max(0, projectEnd - kMinClipDurationSeconds))`,
  `end = min(start + kDefaultEffectBarSeconds, projectEnd)`, and at least
  `kMinClipDurationSeconds` long.

- [ ] **Step 1: Write the failing tests** (`effect_stack_test.dart`):
  - two bars on lanes 2 and 0 at t → drawn in order lane 0, lane 2;
  - a bar is not drawn at its own `end` (half-open: adjacent bars never double at a seam);
  - `glow` (4) on lane 0 plus `vignette` on lane 1 → only glow; `blur` (2) lane 0, `glow` lane 1,
    `vignette` lane 2 → blur and vignette (glow skipped, the walk continues);
  - an unknown effect id → not drawn and costs nothing;
  - intensity: a bar keyframed 0 → 1 across 4–8 gives 0.5 at 6; an envelope resolves over the bar;
  - shader progress: `cinema_zoom` (timed) at `start + introSeconds/2` → 0.5, and 1.0 after its
    window; a static `vignette` gives whole-bar progress; a zero-length bar gives 1.0
    (Review Focus 2);
  - `newlySkippedEffectBar` returns the bar that became skipped, and null when it already was.
  - `effect_bar_placement_test.dart`: `(playhead 2, end 20) → (2, 5)`; `(18.5, 20) → (18.5, 20)`;
    `(19.99, 20) → (20 - kMinClipDurationSeconds, 20)`; `(25, 20) → (20 - kMin…, 20)`; a project
    shorter than the minimum still gives a bar of the minimum.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Extend the fixture test**: `cases` — about a dozen bar sets × instants covering the
  cases above, each recording `drawn: [{id, intensity, progress}]`; regenerate with
  `UPDATE_EFFECT_FIXTURE=1` (both copies).
- [ ] **Step 5: Run** the three test files, then `flutter test`. Expected: PASS.
- [ ] **Step 6: Commit** `feat(effects): one rule for which bars draw, pinned by a fixture`.

### Task 4: Notifier — adding, changing, keyframing, copying and deleting bars

**Files:**
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart`,
  `lib/features/video_editor/models/video_editor_state.dart`
- Test: `test/features/video_editor/providers/effect_bar_commands_test.dart`,
  `test/features/video_editor/providers/effect_bar_keyframes_test.dart`

**Interfaces:**
- Consumes: Task 2's model and state, Task 3's `newEffectBarSpan`, `keyframe_core.dart`.
- Produces (notifier):
  ```dart
  String? addEffectBar(String effectId);                 // places, selects (only selection), menu 'effect_bar'; null + no step for an unknown id
  void setEffectBarEffect(String effectId);              // selected bar; drops keyframes; catalog defaultIntensity + defaultEnvelope; no step when unchanged/unknown
  void beginEffectBarIntensityEdit();                    // pauses, one snapshot; no-op with no bar selected
  void setEffectBarIntensityLive(double value);          // edit rule on the selected bar, clamped 0..1, non-finite ignored, no snapshot
  void selectEffectBar(String id);                       // only selection, currentMenuId 'effect_bar'
  void duplicateEffectBar();                             // straight after on its lane when free, else firstFreeLane below; same effect/intensity/keyframes; selected
  void deleteEffectBar();                                // removes, compacts lanes, menu back to 'root'
  ```
- Produces (state): `keyframeEffectBar` (the selected bar, null when a clip or overlay is
  selected); `hasKeyframeTarget`, `keyframeTargetProgress`, `keyframeDiamonds`,
  `playheadKeyframeProgress`, `keyframeCurveTargetProgress`, `keyframeCurve` include it;
  `double effectBarEditIntensity` (the `clipEditValue` rule: base without diamonds or off the bar,
  else the resolved value at the playhead).
- The existing keyframe commands (plus/minus, easing, diamond move) dispatch to the selected bar
  through one `_editSelectedEffectBarKeyframes`, ahead of the overlay dispatch, over
  `KeyframeParams` `{intensity: bar.intensity}`, tolerance `kKeyframeHitSeconds / bar.duration`
  capped at 0.5.

- [ ] **Step 1: Write the failing tests** (`effect_bar_commands_test.dart`):
  - `addEffectBar('blur')` at playhead 2 → one bar 2–5 on the first free lane, selected, its
    intensity `defaultIntensity` with blur's `ramp_out` envelope, one undo step; `addEffectBar('nope')`
    → nothing, no step;
  - `setEffectBarEffect` to the same id → no undo entry; to another → keyframes dropped, one step;
  - `duplicateEffectBar` → copy starts at the original's end on its lane when free; else on the
    nearest free lane below at the same time;
  - `deleteEffectBar` → bar gone, empty lane closed, selection cleared, menu `root`;
  - **Review Focus 3**: add → change → delete → undo → undo → redo: after each step
    `selectedEffectBarId` is null or names a bar in `effectBars`;
  - selecting a text clears `selectedEffectBarId`, and selecting a bar clears the others.
  - **bars live in timeline time**: deleting, trimming or reordering a clip leaves every bar's
    `start`/`end` unchanged.
- [ ] **Step 2: Write the failing keyframe tests** (`effect_bar_keyframes_test.dart`): no diamonds →
  `setEffectBarIntensityLive(0.3)` writes the base; plus at the playhead places a diamond carrying
  the value there; between two diamonds a write places a diamond first; trimming the bar keeps
  diamond progresses (the curve stretches); **Review Focus 5**: with `isPlaying` true,
  `beginEffectBarIntensityEdit()` sets it false before the first write.
- [ ] **Step 3: Run.** Expected: FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run** both files, then `flutter test`. Expected: PASS.
- [ ] **Step 6: Commit** `feat(effects): add, change, keyframe, copy and delete effect bars`.

### Task 5: The timeline contract carries bars, and clips stop carrying effects

**Files:**
- Modify: `lib/features/video_editor/models/editor_timeline.dart`,
  `lib/features/video_editor/logic/timeline/video_editor_timeline_composer.dart`
- Test: `test/features/video_editor/logic/timeline/video_editor_timeline_composer_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class EditorTimelineEffect {
    final String id; final String effectId; final double start; final double end;
    final int lane; final AnimatableDouble intensity; final double? introSeconds;
    Map<String, dynamic> toJson();   // introSeconds omitted when null
  }
  // EditorTimeline.effects (List<EditorTimelineEffect>, sorted by lane), JSON key 'effects'
  List<EditorTimelineEffect> composeEffects(VideoEditorState state);   // on the composer
  ```
- `EditorTimelineVideoClip` loses `effectId`, `effectIntensity`, `effectIntroSeconds`;
  `_canMergeForPlayback` loses its effect checks.

- [ ] **Step 1: Write the failing tests**: a bar composes with `introSeconds` from the catalog for
  `cinema_zoom` and none for `vignette`; bars sorted by lane; a bar with an unknown id is not sent
  (Review Focus 1); clip JSON carries no `effectId`/`effectIntensity`/`effectIntroSeconds`;
  `durationSeconds` counts a bar past the last clip; two adjacent clips that differed only in effect
  now merge for playback. Replace the existing per-clip effect composer tests.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the file, then `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(effects): the timeline sends effect bars; clips send no effect`.

### Task 6: The effects sheet works on bars; the menus change

**Files:**
- Modify: `lib/features/video_editor/widgets/panels/effects_panel.dart`,
  `lib/screens/video_editor_screen.dart` (`_rootMenu`, `_editMenu`, new `_effectBarMenu`, `_menus`,
  tool handlers), `lib/features/video_editor/logic/toolbar_visibility.dart` if a rule is needed
- Test: `test/features/video_editor/widgets/effects_panel_test.dart` (rewrite),
  `test/features/video_editor/widgets/editor_menu_test.dart`

**Interfaces:**
- Consumes: Task 4's notifier commands and `effectBarEditIntensity`.
- Produces: root menu `EditorTool(id: 'effects', label: 'Effects', icon: LucideIcons.sparkles)`
  right after `overlay`; `_effectBarMenu` id `effect_bar`: `effect_edit` ("Edit"),
  `duplicate` ("Copy"), `delete` ("Delete"); the `edit` (clip) menu without `effects`.
- Sheet behaviour: **no bar selected → a tap calls `addEffectBar`; a bar selected → a tap calls
  `setEffectBarEffect`.** No None tile (each grid's `itemCount` equals
  `effectsInCategory(c).length`). The intensity slider shows only with a bar selected, reads
  `effectBarEditIntensity`, calls `beginEffectBarIntensityEdit` on drag start and
  `setEffectBarIntensityLive` per change. Opens on the selected bar's category, else the first.
  The apply-to-all button is gone.
- Handlers: `effects` and `effect_edit` open the sheet through `showEditorSheet`; `duplicate` and
  `delete` act on the selected bar when `selectedEffectBarId != null`.

- [ ] **Step 1: Write the failing tests**: sheet — first tap adds and selects a bar at the
  playhead, a second tap changes it (still one bar), closing before any tap adds nothing, the slider
  appears after the first tap and a drag is one undo step, opened on a selected `glow` bar its
  Light tab is open and the Glow tile marked, no None tile; menu — the root has `effects` with a
  handler, the clip menu has no `effects`, the `effect_bar` menu is Edit · Copy · Delete with
  handlers (replace the pin that the root has no Effects entry).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both files, then `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(effects): Effects on the main menu adds bars; a bar has its own menu`.

### Task 7: Bars on the timeline

**Files:**
- Modify: `lib/features/video_editor/widgets/timeline/scrollable_timeline.dart`,
  `lib/features/video_editor/widgets/timeline/lane_gutter_icons.dart`,
  `lib/core/theme/app_colors.dart`, `lib/screens/video_editor_screen.dart` (wiring)
- Test: `test/features/video_editor/widgets/timeline_effect_bars_test.dart`,
  `test/features/video_editor/widgets/lane_trim_handles_test.dart` (add the bar)

**Interfaces:**
- Produces: `ScrollableTimeline({…, List<EffectBarModel> effectBars = const [], String?
  selectedEffectBarId, ValueChanged<String>? onEffectBarTapped, void Function(String id, Duration
  start, Duration end, {int? newLaneIndex})? onEffectBarChanged})`; the screen wires
  `onEffectBarChanged` to `_placeLaneItem` and `onEffectBarTapped` to `selectEffectBar`.
- Produces: `AppColors.effectTrack` (teal, `0xFF14B8A6`); `LaneGutterKind.effect` drawn with
  `LucideIcons.sparkles`; `laneGutterKinds(..., effects:)`.
- `_buildEffectTracks(lanesTop)` follows `_buildImageTracks`: square bar at
  `start * _pixelsPerSecond`, the effect's icon and label (`'Effect'` for an unknown id), long-press
  move, `_laneTrimHandle` on both ends (left inside at 0:00 — `_atTimelineStart`), snap targets from
  `_snapTargetsFor` (bars included through `laneSpansOf`), diamonds through
  `_overlayKeyframeDiamonds` for the selected bar, gesture bracketed by `onDragStart`/`onDragEnd`.
  Not built while `recordingTake != null`.

- [ ] **Step 1: Write the failing tests**: a bar 2–5 is drawn at `2 * kDefaultPixelsPerSecond`,
  `3 * …` wide, in `AppColors.effectTrack`, with "Blur"; an unknown id reads "Effect" (Review
  Focus 1); a tap reports its id; a long-press drag down a lane reports `newLaneIndex`; a trim
  handle reports a new end and no lane; the drag snaps to a text's start; a bar at 0:00 keeps its
  left handle inside; recording mode hides it; the gutter shows the effect glyph on its lane; a bar
  added while zoomed in is drawn at the zoom.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both files, then `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(effects): effect bars on the timeline`.

### Task 8: Old drafts convert; per-clip effects go (Dart)

**Files:**
- Create: `lib/features/video_editor/logic/effects/clip_effect_migration.dart`
- Modify: `lib/features/video_editor/models/video_segment.dart`,
  `lib/features/video_editor/logic/animation/clip_keyframes.dart`,
  `lib/features/video_editor/providers/video_editor_notifier.dart` (`loadDraft`; delete
  `setClipEffect`, `_nextEffectIntensity`, `applyEffectToAllClips`; freeze frame and replace clip
  stop copying an effect), `lib/features/video_editor/logic/clip_to_overlay.dart`
- Test: `test/features/video_editor/logic/effects/clip_effect_migration_test.dart`; update or
  delete `video_segment_effect_test.dart`, `video_segment_keyframe_test.dart`,
  `clip_keyframes_test.dart`, `clip_keyframe_edit_test.dart`, `apply_to_all_copy_test.dart`,
  `clip_to_overlay_test.dart`, `replace_clip_test.dart`, `effect_catalog_test.dart`

**Interfaces:**
- Produces:
  ```dart
  List<EffectBarModel> migrateClipEffects({
    required List<Map<String, dynamic>> rawSegments,   // the draft's clip JSON, which still holds effectId/effectIntensity
    required List<VideoSegment> segments,              // the same clips, parsed, for geometry
    required List<LaneSpan> occupied,                  // everything already on the lanes
  });
  ```
- Rule (spec, "Old projects"): clip *i* with an `effectId` → a bar from
  `starts[i] + window(i-1→i)` to `starts[i] + segments[i].duration`, where `starts =
  segmentTimelineStarts(segments)` and `window(i-1→i) = starts[i-1] + segments[i-1].duration -
  starts[i]` (0 for the first clip or a plain cut); same `effectId`, intensity base and envelope;
  each keyframe moved to the same timeline instant (`clipStart + p·duration`) and re-expressed as
  bar progress; keyframes before the bar's start dropped and, if any were, one pinned at 0 with the
  value resolved there; lane `firstFreeLane` against `occupied` plus the bars already made.
- `VideoSegment` stops reading and writing `effectId`/`effectIntensity`/`effectIntroSeconds`
  (`fromJson` ignores them); `ClipProperty.effectIntensity` is removed (six properties remain).

- [ ] **Step 1: Write the failing migration tests**: a lone clip 0–5 with `glow` → bar 0–5; a clip
  entered through a 1 s transition → bar starts at the window's end; keyframes 0 → 1 over a 10 s clip
  entered through a 2 s window land on the same instants and a pinned keyframe at the bar's start
  holds the value there; two adjacent effected clips → two bars on one lane, touching; a clip
  without an effect → no bar; an unknown id is carried as written; loading a draft that has both
  clip effects and `effectBars` keeps both and converts only the clip effects; a loaded-and-saved
  draft has no clip effect fields and converts nothing on the next load.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the migration and call it in `loadDraft` before `normalizeLanes`; then
  remove the per-clip effect code listed above, updating or deleting each listed test so it states
  the new truth (for example `clip_to_overlay_test`: an effect is no longer a loss).
- [ ] **Step 4: Run** `flutter test` and `flutter analyze --no-pub`. Expected: all pass, 44 issues.
- [ ] **Step 5: Commit** `feat(effects): old drafts' clip effects become bars; clips carry none`.

### Task 9: Kotlin — parsing bars and the same drawing rule

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/NativeTimelineEffect.kt`,
  `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/EffectStack.kt`
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/EffectStackTest.kt`,
  `NativeTimelineEffectTest.kt`

**Interfaces:**
- Produces:
  ```kotlin
  internal data class NativeTimelineEffect(val id: String, val effectId: String, val start: Double,
      val end: Double, val lane: Int, val intensity: AnimatableDouble, val introSeconds: Double?) {
      companion object { fun fromMap(map: Map<*, *>): NativeTimelineEffect?; fun listFrom(timeline: Map<String, Any?>): List<NativeTimelineEffect> }
  }
  internal data class ActiveEffect(val bar: NativeTimelineEffect, val intensity: Double, val progress: Double)
  internal object EffectStack {
      fun drawnAt(bars: List<NativeTimelineEffect>, seconds: Double): List<ActiveEffect>
      fun peakInstances(bars: List<NativeTimelineEffect>): Map<String, Int>   // per effectId, most bars drawn at once
  }
  ```
- `drawnAt` is Task 3's rule exactly, with `EffectPassCosts.costOf`; intensity via
  `AnimatableDouble.resolveAt(wholeBarProgress)` clamped 0..1; progress over `introSeconds` from
  `start` when present.

- [ ] **Step 1: Write the failing tests**: `EffectStackTest` replays every fixture case and
  matches ids, intensities and progresses (1e-6); `peakInstances` — three non-overlapping `blur`
  bars → `{blur: 1}`, two overlapping `vignette` bars → `{vignette: 2}`, a bar skipped for budget is
  not counted. `NativeTimelineEffectTest`: parses the composer's map (keyframed intensity, absent
  `introSeconds`); a map missing `effectId` → null; `end <= start` clamped to the minimum.
- [ ] **Step 2: Run** `cd android && ./gradlew.bat :app:testDebugUnitTest --tests "*EffectStack*" --tests "*NativeTimelineEffect*"`.
  Expected: FAIL (unresolved).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat(effects): Kotlin reads effect bars and draws them by the shared rule`.

### Task 10: Kotlin — the stack controller, both engines, the channel

**Files:**
- Create: `android/app/src/main/kotlin/com/techfamz/slimshotai/nativepreview/gl/effects/EffectStackController.kt`
- Delete: `…/gl/effects/ClipEffectController.kt`,
  `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/ClipEffectProgressTest.kt`
- Modify: `…/nativepreview/gl/TransitionRenderer.kt` (implements `EffectPassSink`),
  `…/nativepreview/TimelinePlaybackEngine.kt`, `…/export/VideoExportEngine.kt`,
  `…/nativepreview/NativeTimelinePreviewManager.kt`, `…/nativepreview/NativeTimelineClip.kt`
  (remove `effectId`, `effectIntensity`, `effectIntroSeconds`, `effectProgressAt`,
  `effectIntensityAt`), `ClipFlipTest.kt`, `LaneFitTest.kt`
- Test: `android/app/src/test/kotlin/com/techfamz/slimshotai/nativepreview/EffectStackControllerTest.kt`

**Interfaces:**
- Produces:
  ```kotlin
  internal interface EffectPassSink {
      fun setEffectPasses(passes: List<EffectPass>)
      fun <T> callOnGlThread(block: () -> T): T     // inline when already on the GL thread
      fun redrawEffects()                           // TransitionRenderer: requestRender()
  }
  internal class EffectStackController(
      private val sink: EffectPassSink,
      private val build: (String) -> List<EffectPass> = EffectShaders::passesFor,
      private val release: (List<EffectPass>) -> Unit = EffectShaders::releasePasses,
  ) {
      fun setBars(bars: List<NativeTimelineEffect>)  // builds EffectStack.peakInstances(bars) instances per effectId in one GL hop; releases surplus
      fun apply(active: List<ActiveEffect>)          // assigns built instances; pushes intensity/progress; setEffectPasses only when the ordered list changes, else redrawEffects() when a uniform changed
      fun reassert()                                 // re-sets the current list (after an export)
      fun clear(); fun release(); fun forget()
  }
  ```
- **`apply` never calls `build`.** A bar whose instance is missing (cannot happen after `setBars`)
  is skipped rather than built in the render path.
- Preview engine: `setEffects(list)` → `controller.setBars`; `tick` calls
  `applyEffects(overlayClockNow)` **after** `applyOverlays`; `setOverlayClock` does too (the tail);
  the reset path calls `clear()`, `release()` calls `forget()`, `reattachSurfacesAfterExport` calls
  `reassert()`; `applyClipEffect` is deleted. `tick` returns while `exportOwnsRenderer` holds, as it
  does.
- Export: `Request.effects: List<NativeTimelineEffect>` from `NativeTimelineEffect.listFrom(timeline)`;
  its own controller, `setBars` before the first frame, `apply(EffectStack.drawnAt(effects, t))`
  **every frame including the tail**; `clear()` + `release()` in `finally` before `endExport`; the
  `effectClip` resolution is deleted.
- Manager: `"setEffects"` parses `effects` like `"setOverlays"` (a `pendingEffects` held until the
  engine exists).

- [ ] **Step 1: Write the failing tests** (`EffectStackControllerTest`, fake sink and fake passes
  recording intensity/progress): 200 non-overlapping `blur` bars → `build("blur")` called once
  (Review Focus 4); two overlapping `vignette` bars → twice; `apply` called through a whole
  timeline never calls `build`; the same active list applied twice → `setEffectPasses` once;
  intensity-only change → no `setEffectPasses`, one `redrawEffects`; `setBars` dropping a bar →
  `release` for its surplus instance; `reassert` re-sets the current list; each pass receives its
  bar's intensity and progress before `setEffectPasses` hands it over.
- [ ] **Step 2: Run** `cd android && ./gradlew.bat :app:testDebugUnitTest --tests "*EffectStackController*"`.
  Expected: FAIL.
- [ ] **Step 3: Implement** the controller, then the engine, export and manager changes; delete the
  old controller and its test; update `ClipFlipTest`/`LaneFitTest` constructors.
- [ ] **Step 4: Run** the whole Kotlin suite (`:app:testDebugUnitTest`) and
  `cd android && ./gradlew.bat :app:compileDebugKotlin`. Expected: all pass, compiles.
- [ ] **Step 5: Commit** `feat(effects): the engines draw effect bars, with no program built in the render path`.

### Task 11: The preview hears bars live; the budget toast

**Files:**
- Modify: `lib/features/video_editor/services/native_timeline_preview_service.dart`,
  `lib/screens/video_editor_screen.dart`
- Test: `test/features/video_editor/services/native_timeline_preview_effects_test.dart`,
  `test/features/video_editor/widgets/effect_budget_toast_test.dart`

**Interfaces:**
- Produces: `List<Map<String, dynamic>> effectPayload(VideoEditorState state)` (the composer's
  `composeEffects` as JSON), `Future<void> sendEffectPayload(List<Map<String, dynamic>> payload)`
  (`setEffects` with `{'effects': payload}`).
- Screen: `_syncNativeEffects(state)` called wherever `_syncNativeOverlays` is, sending only when
  `state.effectBars` is not the identical list last sent (an untouched list keeps its identity
  through `copyWith`), and during gestures too (`_syncNativePreviewTimeline` is skipped there,
  this must not be). A `ref.listen` on `effectBars` shows
  `ToastUtils.show(context, '<Label> is skipped: too many effects at once')` when
  `newlySkippedEffectBar(previous, next)` is non-null.

- [ ] **Step 1: Write the failing tests**: the payload matches `composeEffects`; a position change
  does not re-send (identity); a bar drag re-sends per frame; adding `glow` over a bar of `blur`
  toasts "Glow is skipped: too many effects at once" once, and a later unrelated edit does not
  toast again.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both files, then `flutter test` and `flutter analyze --no-pub`. Expected: all
  pass, 44 issues.
- [ ] **Step 5: Commit** `feat(effects): the preview follows bars live; a skipped effect is named`.

### Task 12: Notes, and the device checklist

**Files:**
- Modify: `CLAUDE.md` (a new "Effects track" section; the per-clip effects section's transition
  rule, the `effectIntensity` keyframable property, the Apply-to-all line and the
  "Rules to protect" note about the root menu's `effects` entry brought up to date),
  `docs/roadmap.md` (item 16 built, awaiting device verification; Whole frame and one overlay
  named as next), the spec's status line.

- [ ] **Step 1: Write the notes**, stating what is device-only: bars on the right frames in preview
  and export, two stacked bars, a bar across a transition, an intro from the bar's start, no hitch
  crossing bar edges, an old project with effects unchanged, a bar in the tail, live drag/trim.
- [ ] **Step 2: Run** `flutter test`, `flutter analyze --no-pub`, and the Kotlin suite. Expected:
  all pass, 44 issues.
- [ ] **Step 3: Commit** `docs(effects): the effects track in the working notes`.
