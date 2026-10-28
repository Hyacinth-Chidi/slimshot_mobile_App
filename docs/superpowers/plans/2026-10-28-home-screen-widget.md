# Home Screen Widget and Icon Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Continue editing" home-screen widget that shows the last edit. Add a long-press menu on the app icon with New video and Compress video. Each tap runs Home's own handler, and never over work in progress.

**Architecture:**
- **The widget's data.** Dart sends the latest draft over `slimshot_ai/home_widget` whenever drafts change. Kotlin keeps it, with a small cover it prepares once. An `AppWidgetProvider` draws it from RemoteViews, so the widget draws even with the app closed.
- **Taps.** A widget tap starts `MainActivity` with an action. A menu item goes through an invisible trampoline activity first, because Android clears the app's whole task when a static shortcut is launched.
- **Routing.** Dart takes each action once and decides by one pure rule (`routeFor`) whether to act. Home then runs the handler its own button runs.

**Tech Stack:** Flutter/Dart (Riverpod, go_router, flutter_test); Kotlin (AppWidgetProvider, RemoteViews XML, static shortcuts, JUnit 4). No new packages.

**Spec:** `docs/superpowers/specs/2026-10-28-home-screen-widget-design.md`

## Global Constraints

- **Platform.** Android only. `minSdk` is 24 and the build has no core-library desugaring, so **no `java.time`**: use `Calendar`, `TimeZone` and `SimpleDateFormat`.
- **Dependencies.** No new packages, Dart or Gradle. No Jetpack Glance (`android.builtInKotlin=false`).
- **Names.**
  - Channel: `slimshot_ai/home_widget`.
  - Actions: `com.techfamz.slimshotai.action.CONTINUE` (extra `draftId`), `com.techfamz.slimshotai.action.NEW_VIDEO`, `com.techfamz.slimshotai.action.COMPRESS_VIDEO`.
  - Package: `com.techfamz.slimshotai` (no debug suffix).
- **Wire format.**
  - The edit: `{draftId, coverPath, editedAtMillis, clips, lengthSeconds}`. `coverPath` and `lengthSeconds` may be null; the whole map is null when there is no edit.
  - An action: `{action: 'continue' | 'new_video' | 'compress_video', draftId}`.
  - Kotlin reads Dart's numbers as `Number`: `editedAtMillis` arrives as a `Long`, `clips` as an `Int`.
- **Copy.**
  - Widget with an edit: "CONTINUE EDITING", then "Edited today", "Edited yesterday" or "Edited 12 Oct" (the locale's best `dMMM` pattern), then "1 clip" / "4 clips", and the button "Continue".
  - Widget before any edit: "SLIMSHOT", "No edits yet", "Your last edit will wait here", and the button "Start editing".
  - Toast: "That edit was deleted."
  - Widget label in the picker: "Continue editing". Menu items: "New video", "Compress video".
  - **Buttons are text only.**
- **Length.** Whole seconds by `round()`: `m:ss` under an hour, `h:mm:ss` from one hour ("0:42", "12:05", "1:02:03").
- **Redraws.** The widget redraws on every draft change and hourly (`updatePeriodMillis` 3600000), and at no other time.
- **Work in progress holds the app where it is.** In these cases a tap only brings the app forward:
  - an export, a compression or a privacy strip is running;
  - a result nobody has saved or shared is on screen;
  - a caption run is in progress;
  - the editor is in recording mode.

  The spec names export and compression; the rest is the same rule, applied as my call.
- **Expiry.** A draft expires after more than 20 whole days (`DraftService._maxAgeDays`). The widget applies the same rule.
- **The menu goes through `LaunchTrampolineActivity`** (`taskAffinity=""`, no display). Android launches a static shortcut with `NEW_TASK | CLEAR_TASK`, which would destroy a running `MainActivity`, and any export with it. The spec has the menu start `MainActivity` directly. This is a ruling that serves the spec's own rule that a tap must never abandon an export.
- **Colours,** as in the mockup:
  - card `#E018181B`, 1 dp edge `#14FFFFFF`, 24 dp corners;
  - kicker `#D8B4FE`, title `#FAFAFA`, sub line `#A1A1AA`;
  - button gradient `#9333EA` → `#6B21A8`;
  - placeholder: dashed `#73D8B4FE` on `#0AFFFFFF`;
  - menu icons: a `#D8B4FE` glyph on a `#3B0764` circle.
- **Checks.** `flutter analyze --no-pub` stays at 43. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A menu tap while the app is open must not restart the app.** Without the trampoline, Android's `CLEAR_TASK` destroys the editor, with its unsaved changes, and any export in progress. Checked on a device in Task 7.
2. **Reopening from Recents, or after the phone killed the app, must not repeat the tap that started it.**
   - `LaunchIntents.toWire` ignores an intent launched from history (a Task 6 test).
   - `MainActivity` reads its intent only when `savedInstanceState == null` (Task 7).
3. **A tap while the editor is open on another edit saves that edit first.** Home acts only once the editor has gone. Two editors at once would share one `videoEditorProvider` and one native preview. Covered by Task 3's `LaunchRouter` order test.
4. **Two draft changes close together must not leave the widget showing the older one.** For example, leaving the editor and then deleting that draft. An older read never overwrites a newer one (a Task 2 test).
5. **Dates across midnight, and a widget nobody has refreshed for weeks.** Dates use calendar days in `TimeZone.getDefault()`. An edit the app has expired draws as no edit. Both have Task 6 tests.

---

### Task 1: The edit's length saved with the draft

**Files:**
- Modify: `lib/core/models/draft_project.dart`
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart` (`saveDraft`, line 294)
- Test: `test/core/models/draft_project_edited_seconds_test.dart`

**Interfaces:**
- Produces: `DraftProject.editedSeconds` (`double?`), the project's own length. `toJson` writes it only when it is non-null.

- [ ] **Step 1: Write the failing tests.** `draft(...)` and `asset` are built as in `caption_model_test.dart`; `asset` is a 30 s video.

```dart
test('the edit length survives a round trip', () {
  expect(DraftProject.fromJson(draft(editedSeconds: 42.5).toJson()).editedSeconds, 42.5);
});

test('a draft without a length writes no key and loads without one', () {
  expect(draft().toJson().containsKey('editedSeconds'), isFalse);
  expect(DraftProject.fromJson(draft().toJson()).editedSeconds, isNull);
});

test("saving stores the project's own length, music past the clips included", () async {
  SharedPreferences.setMockInitialValues({});
  final n = VideoEditorNotifier(VideoEditorService())
    ..state = VideoEditorState(
      draftId: 'd1',
      assets: const [asset],
      segments: [VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5)],
      audioTracks: [AudioTrackModel(id: 'm', filePath: '/m.mp3', sourceDuration: 5,
          sourceStart: 0, sourceEnd: 5, timelineStart: 3)],
    );
  await n.saveDraft();
  expect((await DraftService.getDraftById('d1'))!.editedSeconds, closeTo(8.0, 1e-9));
});
```

- [ ] **Step 2: Run the tests to see them fail.**
  Run: `flutter test test/core/models/draft_project_edited_seconds_test.dart`
  Expected: a compile error, because `editedSeconds` is not defined.
- [ ] **Step 3: Implement.**
  - Add `final double? editedSeconds;` as an optional constructor parameter.
  - `toJson` adds `if (editedSeconds != null) 'editedSeconds': editedSeconds`.
  - `fromJson` reads `(json['editedSeconds'] as num?)?.toDouble()`.
  - `saveDraft` passes `editedSeconds: projectEndSeconds(...)` with the same six state lists that `totalEditedDurationProvider` passes.
- [ ] **Step 4: Run the tests to see them pass.**
  Run: `flutter test test/core/models/draft_project_edited_seconds_test.dart test/features/video_editor/logic/captions/caption_model_test.dart`
  Expected: all pass.
- [ ] **Step 5: Commit** with the message `feat(drafts): a draft keeps the edit's own length`.

---

### Task 2: The widget's data, sent on every draft change

**Files:**
- Create: `lib/features/home_widget/home_widget_sync.dart`
- Test: `test/features/home_widget/home_widget_sync_test.dart`

**Interfaces:**
- Consumes: `DraftProject.editedSeconds` (Task 1); `DraftService.getDrafts()`; `DraftRefreshNotifier.instance`.
- Produces:
  - `const String kHomeWidgetChannel = 'slimshot_ai/home_widget';`
  - `class HomeWidgetEdit { final String draftId; final String? coverPath; final DateTime editedAt; final int clips; final double? lengthSeconds; Map<String, Object?> toWire(); }`
  - `HomeWidgetEdit? lastEditOf(List<DraftProject> drafts)`:
    - picks the greatest `updatedAt`, whatever the list order;
    - `clips` is `segments.length`;
    - returns null when there are no drafts.
  - `class HomeWidgetSync { HomeWidgetSync({MethodChannel? channel, Future<List<DraftProject>> Function()? drafts}); void start(); Future<void> sync(); void dispose(); }`:
    - `start` syncs now and again on every `DraftRefreshNotifier` change.
    - `sync` sends `setLastEdit` with `lastEditOf(...)?.toWire()`.
    - `sync` drops its answer when a later `sync` began after it.
    - Every platform error is swallowed.

- [ ] **Step 1: Write the failing tests.**
  - `draft(...)` builds a `DraftProject` with `clips` clips.
  - `calls` records `(method, arguments)` from a mock handler on `MethodChannel(kHomeWidgetChannel)`.

```dart
test('the last edit is the latest saved, whatever the list order', () {
  final older = draft(id: 'a', updatedAt: DateTime(2026, 10, 1));
  final newer = draft(id: 'b', updatedAt: DateTime(2026, 10, 2));
  expect(lastEditOf([older, newer])!.draftId, 'b');
});

test('it carries the cover, the clip count and the saved length', () {
  final edit = lastEditOf([draft(id: 'a', thumbnailPath: '/c.jpg', clips: 3, editedSeconds: 42)])!;
  expect((edit.coverPath, edit.clips, edit.lengthSeconds), ('/c.jpg', 3, 42.0));
});

test('an old draft has no length, and no drafts is no edit', () {
  expect(lastEditOf([draft(id: 'a')])!.lengthSeconds, isNull);
  expect(lastEditOf(const []), isNull);
});

test('sync sends the edit, and null when there is none', () async {
  final d = draft(id: 'a', thumbnailPath: '/c.jpg', clips: 3, editedSeconds: 42);
  await HomeWidgetSync(channel: channel, drafts: () async => [d]).sync();
  await HomeWidgetSync(channel: channel, drafts: () async => const []).sync();
  expect(calls, [
    ('setLastEdit', {'draftId': 'a', 'coverPath': '/c.jpg',
        'editedAtMillis': d.updatedAt.millisecondsSinceEpoch, 'clips': 3, 'lengthSeconds': 42.0}),
    ('setLastEdit', null),
  ]);
});

test('every draft change sends again, the same cover included, until disposed', () async {
  final sync = HomeWidgetSync(channel: channel,
      drafts: () async => [draft(id: 'a', thumbnailPath: '/c.jpg')])..start();
  DraftRefreshNotifier.instance.refresh();
  await pumpEventQueue();
  sync.dispose();
  DraftRefreshNotifier.instance.refresh();
  await pumpEventQueue();
  expect(calls.map((c) => (c.$2 as Map)['coverPath']), ['/c.jpg', '/c.jpg']);
});

test('an older read never overwrites a newer one', () async {
  final reads = [Completer<List<DraftProject>>(), Completer<List<DraftProject>>()];
  var next = 0;
  final sync = HomeWidgetSync(channel: channel, drafts: () => reads[next++].future);
  final older = sync.sync();
  final newer = sync.sync();
  reads[1].complete([draft(id: 'new')]);
  await newer;
  reads[0].complete([draft(id: 'old')]);
  await older;
  expect(calls.map((c) => (c.$2 as Map)['draftId']), ['new']);
});

test('a phone without the channel is no error', () async {
  await HomeWidgetSync(channel: const MethodChannel('nowhere'), drafts: () async => const []).sync();
});
```

- [ ] **Step 2: Run the tests to see them fail.**
  Run: `flutter test test/features/home_widget/home_widget_sync_test.dart`
  Expected: a compile error.
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run the same command to see the tests pass.**
- [ ] **Step 5: Commit** with the message `feat(home widget): the last edit, sent to the widget on every draft change`.

---

### Task 3: Launch actions — read once, routed by one rule

**Files:**
- Create: `lib/features/home_widget/launch_actions.dart`
- Test: `test/features/home_widget/launch_actions_test.dart`

**Interfaces:**
- Consumes: `kHomeWidgetChannel` (Task 2).
- Produces:
  - **The actions.** `sealed class LaunchAction`, with `ContinueEdit(String draftId)`, `NewVideo()` and `CompressVideo()`. All are const with value equality. `static LaunchAction? fromWire(Object? message)` reads one from the wire.
  - **The rule.** `enum LaunchRoute { bringForward, waitForHome, goHome }` and `LaunchRoute routeFor(LaunchAction action, {required bool busy, required String? openDraftId, required bool onboardingSeen})`:
    - busy → `bringForward`;
    - a `ContinueEdit` for `openDraftId` → `bringForward`;
    - onboarding not seen → `waitForHome`;
    - otherwise → `goHome`.
  - **The holder.** `class LaunchActions extends ChangeNotifier { LaunchActions(); static final LaunchActions instance; LaunchAction? get pending; void post(LaunchAction action); LaunchAction? take(); }`
    - A post replaces whatever is pending (the last tap wins) and notifies.
    - `take` returns the pending action and clears it.
  - **The channel.** `class LaunchChannel { LaunchChannel({MethodChannel? channel, required void Function(LaunchAction) onAction}); Future<void> start(); void dispose(); }`
    - `start` sets the handler for `launchAction` calls **before** asking `takeLaunchAction` once.
    - Errors are swallowed.
  - **The router.** `class LaunchRouter { LaunchRouter({required bool Function() busy, required String? Function() openDraftId, required Future<bool> Function() onboardingSeen, required Future<void> Function() saveOpenEdit, required void Function() goHome, required Future<void> Function() untilEditorGone, LaunchActions? actions}); Future<void> handle(LaunchAction action); }`
    - `bringForward`: does nothing.
    - `waitForHome`: posts.
    - `goHome` with an edit open: saves it, goes Home, waits for the editor to go, then posts.
    - `goHome` with no edit open: goes Home, then posts.

- [ ] **Step 1: Write the failing tests.**

```dart
test('the three actions read from the wire; anything else is nothing', () {
  expect(LaunchAction.fromWire({'action': 'continue', 'draftId': 'd1'}), const ContinueEdit('d1'));
  expect(LaunchAction.fromWire({'action': 'new_video'}), const NewVideo());
  expect(LaunchAction.fromWire({'action': 'compress_video'}), const CompressVideo());
  for (final junk in [null, 'x', {'action': 'continue'}, {'action': 'share'}]) {
    expect(LaunchAction.fromWire(junk), isNull, reason: '$junk');
  }
});

test('where a tap goes', () {
  LaunchRoute r(LaunchAction a, {bool busy = false, String? open, bool seen = true}) =>
      routeFor(a, busy: busy, openDraftId: open, onboardingSeen: seen);
  expect(r(const NewVideo()), LaunchRoute.goHome);
  expect(r(const NewVideo(), busy: true), LaunchRoute.bringForward);
  expect(r(const ContinueEdit('d1'), open: 'd1'), LaunchRoute.bringForward);
  expect(r(const ContinueEdit('d1'), open: 'd2'), LaunchRoute.goHome);
  expect(r(const CompressVideo(), seen: false), LaunchRoute.waitForHome);
  expect(r(const ContinueEdit('d1'), busy: true, seen: false), LaunchRoute.bringForward);
});

test('an action is taken once, and the last tap wins', () {
  var notified = 0;
  final actions = LaunchActions()..addListener(() => notified++);
  actions..post(const NewVideo())..post(const CompressVideo());
  expect(actions.take(), const CompressVideo());
  expect(actions.take(), isNull);
  expect(notified, 2);
});

test('the action the app started with, then later ones, reach onAction', () async {
  // The mock answers takeLaunchAction with {'action': 'new_video'}; the test then
  // sends a launchAction call {'action': 'compress_video'} through the channel.
  expect(received, [const NewVideo(), const CompressVideo()]);
});

test('a phone without the channel is no error', () async {
  await LaunchChannel(channel: const MethodChannel('nowhere'), onAction: (_) {}).start();
});

group('LaunchRouter', () {
  late List<String> log;
  late LaunchActions actions;
  LaunchRouter router({bool busy = false, String? open, bool seen = true}) => LaunchRouter(
      busy: () => busy, openDraftId: () => open, onboardingSeen: () async => seen,
      saveOpenEdit: () async => log.add('save'), goHome: () => log.add('home'),
      untilEditorGone: () async => log.add('gone'), actions: actions);
  setUp(() {
    log = [];
    actions = LaunchActions()..addListener(() => log.add('post'));
  });

  test('another edit open: saved, Home, the editor gone, then the action', () async {
    await router(open: 'd2').handle(const ContinueEdit('d1'));
    expect(log, ['save', 'home', 'gone', 'post']);
    expect(actions.take(), const ContinueEdit('d1'));
  });
  test('nothing open: Home, then the action', () async {
    await router().handle(const NewVideo());
    expect(log, ['home', 'post']);
  });
  test('busy, or Continue on the open edit: nothing at all', () async {
    await router(busy: true).handle(const NewVideo());
    await router(open: 'd1').handle(const ContinueEdit('d1'));
    expect(log, isEmpty);
    expect(actions.pending, isNull);
  });
  test('before onboarding: kept for Home, nowhere navigated', () async {
    await router(seen: false).handle(const CompressVideo());
    expect(log, ['post']);
  });
});
```

- [ ] **Step 2: Run the tests to see them fail.**
  Run: `flutter test test/features/home_widget/launch_actions_test.dart`
  Expected: a compile error.
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run the same command to see the tests pass.**
- [ ] **Step 5: Commit** with the message `feat(home widget): launch actions, read once and routed by one rule`.

---

### Task 4: Work in progress holds the app where it is

**Files:**
- Create: `lib/core/utils/held_work.dart`
- Modify:
  - `lib/core/utils/result_exit.dart`
  - `lib/screens/export_video_screen.dart`
  - `lib/screens/result_screen.dart`
  - `lib/screens/privacy_result_screen.dart`
  - `lib/features/video_editor/widgets/panels/caption_progress_sheet.dart`
  - `lib/features/audio_tools/record_controller.dart`
- Test:
  - `test/core/utils/result_exit_test.dart`
  - `test/screens/export_video_screen_test.dart`
  - `test/screens/result_files_test.dart`
  - `test/features/video_editor/widgets/auto_caption_sheets_test.dart`
  - `test/features/audio_tools/record_controller_test.dart`

**Interfaces:**
- Produces:
  - `class HeldWork { HeldWork(); static final HeldWork instance; bool get isHeld; void hold(Object holder); void release(Object holder); }`. It holds a set of holders.
  - `ResultExit({TempFileDeleter delete, HeldWork? held})` gains `void hold()` and `void release()`. A hold lasts until `markKept()` or `release()`.
  - `RecordController(..., HeldWork? held)` holds from `enter()` until Done or ✕ ends the mode, or until `dispose()`.
- Holders:
  - **The export screen** holds from `initState` (`_exit.hold()`). It releases when the export fails, when the result is kept, and in `dispose`.
  - **The compress and privacy result screens** hold from `initState` until the result is kept or `dispose`.
  - **`CaptionProgressSheet`** holds from `initState` to `dispose`, on `HeldWork.instance`.

- [ ] **Step 1: Write the failing tests.** The widget tests read `HeldWork.instance.isHeld` and use each file's existing harness.

```dart
// result_exit_test.dart
test('a result holds the app until it is kept, or released', () {
  final held = HeldWork();
  final kept = ResultExit(delete: delete, held: held)..hold();
  final gone = ResultExit(delete: delete, held: held)..hold();
  kept.markKept();
  expect(held.isHeld, isTrue);
  gone.release();
  expect(held.isHeld, isFalse);
});

// export_video_screen_test.dart, through openExport and the fake engine
testWidgets('an export holds the app while it runs and until it is kept', ...);
  // held while exporting; still held when it finishes; released once shared
testWidgets('a failed or cancelled export holds nothing', ...);

// result_files_test.dart
testWidgets('a compression result holds the app until it is shared', ...);
testWidgets("a strip's result holds the app until Discard takes it away", ...);

// auto_caption_sheets_test.dart
testWidgets('a caption run holds the app until its sheet closes', ...);
  // render never completes → held; Cancel → released

// record_controller_test.dart, through controller(held: held)
test('recording mode holds the app from enter until Done, ✕ or dispose', () async {
  final held = HeldWork();
  final done = controller(held: held);
  await done.enter();
  expect(held.isHeld, isTrue);
  await done.finish();
  expect(held.isHeld, isFalse);
  final cancelled = controller(held: held);
  await cancelled.enter();
  await cancelled.discard();
  expect(held.isHeld, isFalse);
  final dropped = controller(held: held);
  await dropped.enter();
  dropped.dispose();
  expect(held.isHeld, isFalse);
});
```

- [ ] **Step 2: Run the tests to see them fail.**
  Run: the five test files above, in one `flutter test` command.
  Expected: compile errors (`HeldWork` is not defined).
- [ ] **Step 3: Implement** the interfaces and holders above.
- [ ] **Step 4: Run the same command to see every test pass, the existing ones included.**
- [ ] **Step 5: Commit** with the message `feat: work in progress holds the app where it is`.

---

### Task 5: A tap reaches Home's own handlers

**Files:**
- Modify: `lib/screens/home_screen.dart`, `lib/main.dart`
- Test: `test/screens/home_launch_actions_test.dart`

**Interfaces:**
- Consumes:
  - Tasks 2–4;
  - `compressionProvider` and `privacyProvider` (neither is autoDispose);
  - `videoEditorProvider` (autoDispose, so read it only after `ref.exists`).
- **Home** (`_HomeScreenState`) runs `LaunchActions.instance.take()` on its first frame and on every notification:
  - `NewVideo` → `_handleEditVideo()`.
  - `CompressVideo` → `_handleCompressVideo()`.
  - `ContinueEdit(id)` → `DraftService.getDraftById(id)`, then:
    - if the draft is found: `_openDraft(draft)`, which is the draft card's own tap, extracted;
    - if it is gone: `ToastUtils.show(context, 'That edit was deleted.', isWarning: true)` and `DraftRefreshNotifier.instance.refresh()`.
- **The root** (`_SlimShotAppState`), when `SlimShotApp.enableHomeWidget` is on (new, default true):
  - starts `HomeWidgetSync` and `LaunchChannel(onAction: router.handle)` in `initState`, and disposes both;
  - wires the `LaunchRouter` with:
    - **busy:** `HeldWork.instance.isHeld || ref.read(compressionProvider).isProcessing || ref.read(privacyProvider).isProcessing`;
    - **openDraftId:** `ref.exists(videoEditorProvider) ? ref.read(videoEditorProvider).draftId : null`;
    - **onboardingSeen:** the `hasSeenOnboarding` value in `SharedPreferences`;
    - **saveOpenEdit:** `ref.read(videoEditorProvider.notifier).saveDraft()`. It is explicit because the editor's own save in `dispose` runs a frame after the screen has gone.
    - **goHome:** `appRouter.go('/home')`;
    - **untilEditorGone:** `await WidgetsBinding.instance.endOfFrame` while `ref.exists(videoEditorProvider)`, for at most 120 frames.

- [ ] **Step 1: Write the failing tests.**

  **Home alone.** Home runs in a test `GoRouter` inside a `ProviderScope`, with three routes:
  - `/home` → `HomeScreen`;
  - `/edit/video` → `Text('editor ${(state.extra as DraftProject).id}')`;
  - `/compress/video` → `Text('compress')`.

  It uses `home_cards_test.dart`'s fake picker, plus a counted `getVideo`.

```dart
testWidgets('New video opens the gallery, as its card does', ...);      // post(NewVideo()) → picker.picks == 1
testWidgets('Compress video opens the videos, as its card does', ...);  // post(CompressVideo()) → videoPicks == 1
testWidgets('Continue opens that edit', ...);                          // saved draft 'd1' → find.text('editor d1')
testWidgets('Continue on a deleted edit says so and stays Home', ...);  // find.text('That edit was deleted.')
testWidgets('an action posted before Home is up runs once it appears, once', ...);
```

  **The whole app.** Uses `home_cards_test.dart`'s harness, with a mock handler on `kHomeWidgetChannel`.

```dart
testWidgets('the action the app started with runs on Home', ...);   // takeLaunchAction → new_video → picks == 1
testWidgets('the widget is told the last edit at launch', ...);     // one setLastEdit, with null
testWidgets('while work is held, a tap only brings the app forward', ...);
  // HeldWork.instance.hold(this); a launchAction call → picks == 0; released in tearDown
```

- [ ] **Step 2: Run the tests to see them fail.**
  Run: `flutter test test/screens/home_launch_actions_test.dart`
  Expected: failures, because nothing runs the actions yet.
- [ ] **Step 3: Implement** as described above.
- [ ] **Step 4: Run the tests to see them pass.**
  Run: `flutter test test/screens/home_launch_actions_test.dart test/screens/home_cards_test.dart test/widget_test.dart test/launch_splash_test.dart test/screens/onboarding_screen_test.dart`
  Expected: all pass. The other tests run without the channel, and nothing must throw.
- [ ] **Step 5: Commit** with the message `feat(home widget): a tap runs Home's own button, never over work in progress`.

---

### Task 6: Android — the widget

**Files** (in `android/app/src/main/kotlin/com/techfamz/slimshotai/homewidget/`):

- **Create `WidgetText.kt`:** `object WidgetText { fun edited(editedAtMillis: Long, nowMillis: Long, zone: TimeZone, locale: Locale, datePattern: String): String; fun length(seconds: Double): String; fun clips(count: Int): String }`.
  - "Today" and "yesterday" are calendar days in `zone`.
  - The widget passes `DateFormat.getBestDateTimePattern(locale, "dMMM")` as `datePattern`.
- **Create `DraftAge.kt`:** `object DraftAge { const val MAX_DAYS = 20; fun expired(editedAtMillis: Long, nowMillis: Long): Boolean }`.
  - A draft is expired when more than `MAX_DAYS` whole days have passed (by `Long` division). This is `DraftService._maxAgeDays`'s rule, and each file names the other in a comment.
- **Create `CoverCrop.kt`:** `object CoverCrop { fun centre(srcW: Int, srcH: Int): IntArray /* left, top, width, height */; fun output(cropW: Int, cropH: Int, maxH: Int = 320): IntArray /* width, height */ }`.
  - The crop is 9:16. The cut side is rounded with `Math.round`, and the offsets are integer halves.
  - The output is never upscaled.
- **Create `LaunchIntents.kt`:**
  - the three action constants, and `EXTRA_DRAFT_ID = "draftId"`;
  - `fun forMainActivity(context: Context, action: String, draftId: String?): Intent`, with flags `NEW_TASK | CLEAR_TOP | SINGLE_TOP`, so a running `MainActivity` gets `onNewIntent` rather than a second instance starting;
  - `fun toWire(action: String?, draftId: String?, launchedFromHistory: Boolean): Map<String, Any?>?`.
- **Create `HomeWidgetStore.kt`:**
  - a `SharedPreferences` file named "slimshot_home_widget";
  - `data class StoredEdit(val draftId: String, val editedAtMillis: Long, val clips: Int, val lengthSeconds: Double?)`;
  - `fun save(context: Context, edit: StoredEdit)`, `fun read(context: Context): StoredEdit?`, `fun clear(context: Context)`;
  - `fun coverFile(context: Context): File`, which is `filesDir/home_widget_cover.png`.
- **Create `CoverPicture.kt`:** `fun prepare(source: File, out: File): Boolean`. It:
  1. decodes the bounds first, then decodes with an `inSampleSize` that keeps at least twice the output size;
  2. crops with `CoverCrop` and scales;
  3. rounds the corners at `height × 14 / 110`;
  4. writes a PNG to a temp file and renames it onto `out`.

  When the source will not decode, it returns false and deletes `out`.
- **Create `ContinueEditingWidget.kt`:** `class ContinueEditingWidget : AppWidgetProvider`, whose `onUpdate` calls `updateAll`. `companion object { fun updateAll(context: Context) }` draws one of two states:
  - **An edit that is stored and not expired:**
    - The cover is set with `setImageViewBitmap`, decoded from `coverFile`. A URI will not do: the launcher cannot read the app's private files, and it may cache a URI.
    - Without a cover file, it shows the placeholder without its plus.
    - The length chip shows only when a length is known.
    - Taps send `CONTINUE` with the draft id.
  - **Otherwise, the empty state.** Taps send `NEW_VIDEO`.

  Taps use `PendingIntent.getActivity(…, FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE)`, with request codes 1 (Continue) and 2 (New video).
- **Create the resources:**
  - `layout/widget_continue_editing.xml`:
    - the root carries `@android:id/background`;
    - every text is one line with `ellipsize="end"`, in `sans-serif-medium`, except the sub line in `sans-serif`;
    - the cover is 62 × 110 dp;
    - text sizes are 9.5 / 15 / 11 / 12 sp.
  - `layout/widget_continue_editing_preview.xml`: a sample with `@drawable/widget_preview_cover`, "Edited today", "4 clips" and "0:42".
  - Drawables:
    - `drawable/widget_card.xml`, `widget_button.xml`, `widget_chip.xml`, `widget_placeholder.xml`, `ic_widget_plus.xml`;
    - `drawable-nodpi/widget_preview_cover.jpg`, made from `assets/home/new_video_left.webp` at most 320 px tall;
    - `drawable-nodpi/widget_preview.png`, the preview card, for Android 11 and older.
  - `xml/continue_editing_widget_info.xml`:
    - `minWidth` 250dp, `minHeight` 110dp;
    - `targetCellWidth` 4, `targetCellHeight` 2;
    - `resizeMode` none, `widgetCategory` home_screen;
    - `updatePeriodMillis` 3600000;
    - `initialLayout`, `previewLayout`, `previewImage` and `description`.
  - `values/strings.xml`, holding the copy.
- **Modify `AndroidManifest.xml`:** add `<receiver android:name=".homewidget.ContinueEditingWidget" android:exported="false">` with the `APPWIDGET_UPDATE` action and the `android.appwidget.provider` meta-data.
- **Test** (in `android/app/src/test/kotlin/com/techfamz/slimshotai/homewidget/`): `WidgetTextTest.kt`, `DraftAgeTest.kt`, `CoverCropTest.kt`, `LaunchIntentsTest.kt`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
// WidgetTextTest
private val lagos = TimeZone.getTimeZone("Africa/Lagos")
private fun at(zone: TimeZone, y: Int, m: Int, d: Int, h: Int, min: Int) =
    Calendar.getInstance(zone).apply { clear(); set(y, m - 1, d, h, min) }.timeInMillis
private fun edited(then: Long, now: Long) = WidgetText.edited(then, now, lagos, Locale.UK, "d MMM")

@Test fun todayAndYesterdayAreCalendarDays() {
    assertEquals("Edited today", edited(at(lagos, 2026, 10, 28, 0, 1), at(lagos, 2026, 10, 28, 23, 59)))
    assertEquals("Edited yesterday", edited(at(lagos, 2026, 10, 27, 23, 59), at(lagos, 2026, 10, 28, 0, 1)))
    assertEquals("Edited 12 Oct", edited(at(lagos, 2026, 10, 12, 9, 0), at(lagos, 2026, 10, 28, 9, 0)))
}
@Test fun theDayIsThePhonesNotUtcs() {
    // 23:30 UTC on the 27th is 00:30 on the 28th in Lagos.
    val utc = TimeZone.getTimeZone("UTC")
    assertEquals("Edited today", edited(at(utc, 2026, 10, 27, 23, 30), at(lagos, 2026, 10, 28, 10, 0)))
}
@Test fun lengths() = assertEquals(listOf("0:42", "12:05", "1:02:03", "0:00"),
    listOf(41.6, 725.0, 3723.0, 0.2).map(WidgetText::length))
@Test fun clips() {
    assertEquals("1 clip", WidgetText.clips(1))
    assertEquals("4 clips", WidgetText.clips(4))
}

// DraftAgeTest
private val day = 86_400_000L
@Test fun expiresAfterMoreThanTwentyWholeDays() {
    assertFalse(DraftAge.expired(0, 21 * day - 1))
    assertTrue(DraftAge.expired(0, 21 * day))
    assertFalse(DraftAge.expired(day, 0)) // a clock set back
}

// CoverCropTest
@Test fun crops() {
    assertArrayEquals(intArrayOf(0, 0, 1080, 1920), CoverCrop.centre(1080, 1920))
    assertArrayEquals(intArrayOf(656, 0, 608, 1080), CoverCrop.centre(1920, 1080))
    assertArrayEquals(intArrayOf(218, 0, 563, 1000), CoverCrop.centre(1000, 1000))
    assertArrayEquals(intArrayOf(0, 555, 500, 889), CoverCrop.centre(500, 2000))
}
@Test fun outputs() {
    assertArrayEquals(intArrayOf(180, 320), CoverCrop.output(1080, 1920))
    assertArrayEquals(intArrayOf(90, 160), CoverCrop.output(90, 160))
}

// LaunchIntentsTest
@Test fun wire() {
    assertEquals(mapOf("action" to "continue", "draftId" to "d1"),
        LaunchIntents.toWire(LaunchIntents.CONTINUE, "d1", launchedFromHistory = false))
    assertEquals(mapOf("action" to "new_video", "draftId" to null),
        LaunchIntents.toWire(LaunchIntents.NEW_VIDEO, null, launchedFromHistory = false))
    assertEquals(mapOf("action" to "compress_video", "draftId" to null),
        LaunchIntents.toWire(LaunchIntents.COMPRESS_VIDEO, null, launchedFromHistory = false))
    assertNull(LaunchIntents.toWire(LaunchIntents.CONTINUE, null, launchedFromHistory = false))
    assertNull(LaunchIntents.toWire("android.intent.action.SEND", null, launchedFromHistory = false))
    assertNull(LaunchIntents.toWire(null, null, launchedFromHistory = false))
}
@Test fun aTapIsNotRepeatedFromRecents() =
    assertNull(LaunchIntents.toWire(LaunchIntents.NEW_VIDEO, null, launchedFromHistory = true))
```

- [ ] **Step 2: Run the tests to see them fail.**
  Run: `.\android\gradlew.bat -p android testDebugUnitTest --tests "*homewidget*"`
  Expected: compilation fails with unresolved references.
- [ ] **Step 3: Implement** the files above.
- [ ] **Step 4: Run the checks to see them pass.**
  - Run the same tests: they pass.
  - Run `.\android\gradlew.bat -p android compileDebugKotlin`: it succeeds.
  - Run `flutter build apk --debug`: it succeeds.
- [ ] **Step 5: Commit** with the message `feat(home widget): the Continue editing widget on Android`.

---

### Task 7: Android — taps reach the app, and the icon's menu

**Files:**
- **Create `homewidget/LaunchMailbox.kt`:** `class LaunchMailbox(start: Map<String, Any?>?) { fun take(): Map<String, Any?>?; fun arrive(action: Map<String, Any?>): Map<String, Any?>? }`.
  - `take` marks Dart as listening and hands out whatever is kept, once.
  - `arrive` returns the action to send now. Before Dart listens, it keeps the action for `take` instead, and the last one wins.
- **Create `homewidget/HomeWidgetChannel.kt`:** `class HomeWidgetChannel(context: Context, channel: MethodChannel, start: Map<String, Any?>?) : MethodChannel.MethodCallHandler`, with `companion object { const val channelName = "slimshot_ai/home_widget" }`.
  - **`setLastEdit`** answers at once. Then, in order, on one background thread:
    1. It always re-prepares the cover, or deletes it when there is none, so a new cover for the same edit shows.
    2. It saves or clears the store.
    3. It calls `ContinueEditingWidget.updateAll`.
  - **`takeLaunchAction`** answers from the mailbox.
  - **`fun deliver(action: Map<String, Any?>)`** sends a `launchAction` call when the mailbox says so.
  - **`fun release()`** shuts its thread down after the queued work.
- **Create `homewidget/LaunchTrampolineActivity.kt`:** in `onCreate`, for one of the three actions, call `startActivity(LaunchIntents.forMainActivity(this, action, draftId))`; then `finish()`.
- **Modify `MainActivity.kt`:**
  - Before `super.onCreate`, keep `LaunchIntents.toWire(intent?.action, intent?.getStringExtra(EXTRA_DRAFT_ID), launchedFromHistory = ...)` when `savedInstanceState == null`, and null otherwise. `launchedFromHistory` is whether the intent carries `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`.
  - In `configureFlutterEngine`, register a `HomeWidgetChannel` with it.
  - In `onNewIntent`, call `setIntent(intent)`, then `deliver` a non-null `toWire(..., false)`.
  - In `onDestroy`, call `release()`.
- **Create `res/xml/shortcuts.xml`** with two shortcuts, `new_video` and `compress_video`. Each has:
  - `targetPackage` `com.techfamz.slimshotai`;
  - `targetClass` `com.techfamz.slimshotai.homewidget.LaunchTrampolineActivity`;
  - its action;
  - `@string` labels;
  - its icon, `ic_shortcut_new_video` or `ic_shortcut_compress_video` (a vector: the glyph on its circle).
- **Modify `AndroidManifest.xml`:**
  - Declare the trampoline with `android:exported="false"`, `android:taskAffinity=""`, `android:excludeFromRecents="true"` and `android:theme="@android:style/Theme.NoDisplay"`.
  - In `MainActivity`, add `<meta-data android:name="android.app.shortcuts" android:resource="@xml/shortcuts"/>`.
- **Test:** `homewidget/LaunchMailboxTest.kt`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
private val newVideo = mapOf<String, Any?>("action" to "new_video", "draftId" to null)
private val compress = mapOf<String, Any?>("action" to "compress_video", "draftId" to null)

@Test fun theStartActionIsTakenOnce() {
    val box = LaunchMailbox(newVideo)
    assertEquals(newVideo, box.take())
    assertNull(box.take())
}
@Test fun anActionBeforeDartListensIsKeptAndTheLastWins() {
    val box = LaunchMailbox(null)
    assertNull(box.arrive(newVideo))
    assertNull(box.arrive(compress))
    assertEquals(compress, box.take())
}
@Test fun onceDartListensActionsPassStraightOn() {
    val box = LaunchMailbox(null)
    box.take()
    assertEquals(newVideo, box.arrive(newVideo))
    assertNull(box.take())
}
```

- [ ] **Step 2: Run the tests to see them fail.**
  Run: `.\android\gradlew.bat -p android testDebugUnitTest --tests "*homewidget*"`
  Expected: compilation fails.
- [ ] **Step 3: Implement** the files above.
- [ ] **Step 4: Run the checks to see them pass.**
  - Run the same tests: they pass.
  - Run `.\android\gradlew.bat -p android compileDebugKotlin`: it succeeds.
  - Run `flutter build apk --debug`: it succeeds.
- [ ] **Step 5: Commit** with the message `feat(home widget): taps reach the app, and the icon's menu`.

---

### Task 8: Documentation and the whole suite

**Files:**
- Modify: `CLAUDE.md`. Add a section "The home screen widget and the icon's menu", marked **awaiting device verification**. It covers:
  - what the widget shows;
  - the rules: Home's own handlers, an action taken once, held work, the explicit save before leaving the editor, and the trampoline and why it exists;
  - `editedSeconds` against `durationSeconds`;
  - the expiry rule shared with `DraftService`;
  - the device checks.

- [ ] **Step 1: Write the section.**
- [ ] **Step 2: Verify everything.**
  - `flutter test`: all pass.
  - `flutter analyze --no-pub`: 43 issues.
  - `.\android\gradlew.bat -p android testDebugUnitTest`: all pass.
  - `flutter build apk --debug`: it succeeds.
- [ ] **Step 3: Commit** with the message `docs: the home screen widget and the icon's menu`.

**Device checks:**
- **The widget's look:**
  - with an edit and without one;
  - at the largest text size;
  - Android 12+ corners;
  - the picker preview.
- **The widget's behaviour:**
  - Continue opens the edit shown;
  - the card follows an edit, a new cover and a delete.
- **The menu:** both shortcuts, from a cold start and with the app open, including during an export, which must keep running.
- **Taps from every state:**
  - from the editor on another edit: the edit is saved;
  - from a result nobody saved: the app only comes forward;
  - after rotating;
  - reopened from Recents after backing out: nothing repeats.
