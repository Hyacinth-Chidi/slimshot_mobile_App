# Sound Effects Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The audio menu's **Effects** opens a sheet of server sound effects: category pills, tap a row to download and listen, **+** to put the sound on the timeline at the playhead; downloaded sounds live in an offline library.

**Architecture:** Three plain-Dart data units under `lib/features/sound_library/` (a catalogue client over `SlimshotApi`, a file library under app documents, a browse cache), one `ChangeNotifier` controller holding the sheet's state and rules, and a thin sheet widget under `widgets/panels/`. An added sound is an ordinary `AudioTrackModel` through `addAudioTrack`; nothing native changes.

**Tech Stack:** Flutter/Dart, `http` (+ `http/testing` `MockClient`), `path_provider`, `just_audio`, Riverpod `Provider`s.

**Spec:** `docs/superpowers/specs/2026-10-19-sound-effects-library-design.md`. Server contract: `../slimshot_server/docs/app-catalog-api.md`.

## Global Constraints

- The only hardcoded category name is `kSoundEffectsRoot = 'sound-effects'`; the client takes the root as a parameter.
- Public requests: no `Authorization` header (`SlimshotApi.sendPublic*`, never `send`).
- Never store a download `url`; fetch it at once, plain GET, no headers.
- Library: `<app documents>/sound_library/`, file `<id>.<format>`, written as `<id>.part` then renamed; cover `<id>.cover`; index `library.json` written via temp file + rename. Not temp, not `drafts/`.
- Browse cache: `<app support>/catalog_cache.json` — category list + first page per category only.
- Page size 30. Sheet height 0.7 of the screen, through `showEditorSheet`, no title.
- Duration text: `< 10s` after rounding to one decimal → `0.8s`; otherwise `m:ss`; `0` → no text.
- Toasts: `"Couldn't download <title>"` (error), `"<title> isn't available"` (403, error). Offline line: `"You're offline"` + `Retry`. Empty pill: `"No sounds here yet."`
- Colours from `AppColors` only (`panel_theme_test.dart` scans `widgets/panels/`); Lucide icons (`plus`, `pause`, `music` for the default cover — there is no waveform glyph).
- The default cover is a widget (stage colour + `music` icon), **not** a PNG: `pubspec.yaml` declares only `assets/` top level.
- `flutter analyze --no-pub` stays at 44 issues; full `flutter test` green before each commit.
- Commits: `git commit -F <file>`, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.

## Review Focus

1. **Switching pills while a page loads** — the late answer must not land in the pill now shown. (Task 4 test `stale page for a previous pill is dropped`.)
2. **Closing the sheet mid-download** — the download finishes into the library; nothing is added to the timeline, no notify after dispose. (Task 4 test `dispose during a download adds nothing and does not throw`.)
3. **Double tap on +** — exactly one track added. (Task 4 test `a second + while adding is ignored`.)
4. **A corrupt or truncated `library.json` / `catalog_cache.json`** — reads as empty, never throws, Downloaded still opens. (Task 2 and Task 3 tests.)
5. **Pull-to-refresh while a next page is in flight** — no duplicate rows. (Task 4 test `refresh during paging leaves no duplicate ids`.)

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/core/services/slimshot_api.dart` (modify) | add `sendPublicEnvelope` |
| `lib/features/sound_library/data/catalog_models.dart` | `CatalogCategory`, `CatalogSound`, `CatalogPage`, `DownloadTicket`, `LibrarySound`, `formatSoundDuration` |
| `lib/features/sound_library/data/catalog_client.dart` | the three endpoints |
| `lib/features/sound_library/data/sound_library.dart` | downloaded files + index |
| `lib/features/sound_library/data/catalog_cache.dart` | offline browse cache |
| `lib/features/sound_library/sound_effects_controller.dart` | sheet state and rules |
| `lib/features/sound_library/providers.dart` | Riverpod providers |
| `lib/features/video_editor/widgets/panels/sound_effects_sheet.dart` | the sheet |
| `lib/features/video_editor/providers/video_editor_notifier.dart` (modify) | `addLibrarySound` |
| `lib/features/video_editor/logic/toolbar_visibility.dart` (modify) | `sound_effects` case |
| `lib/screens/video_editor_screen.dart` (modify) | menu id + handler |

---

### Task 1: The catalogue client

**Files:**
- Modify: `lib/core/services/slimshot_api.dart`
- Create: `lib/features/sound_library/data/catalog_models.dart`, `lib/features/sound_library/data/catalog_client.dart`
- Test: `test/core/services/slimshot_api_test.dart` (add group), `test/features/sound_library/catalog_client_test.dart`, `test/features/sound_library/catalog_models_test.dart`

**Interfaces:**
- Produces:
  - `class ApiEnvelope { final Object? data; final Map<String, dynamic> meta; }`
  - `Future<ApiEnvelope> SlimshotApi.sendPublicEnvelope(http.BaseRequest Function() build, {Duration timeout})` — success envelope whole; error envelope → `SlimshotApiException(code, message, details)` exactly as `_decode`; anything else → `badResponse`. Refactor `_decode`'s error branch into a shared helper so the two cannot drift.
  - `const kSoundEffectsRoot = 'sound-effects';`
  - `CatalogCategory {String id, slug, name; List<CatalogCategory> children}` with `fromJson`/`toJson`.
  - `CatalogSound {String id, title; int durationMs; String? categorySlug, categoryName, coverUrl}` with `fromJson`/`toJson`; `static CatalogSound? tryParse(Object?)` → null when `id` or `title` missing/empty.
  - `CatalogPage {List<CatalogSound> items; String? nextCursor}`.
  - `DownloadTicket {String url, filename, format; int byteSize, durationMs}`.
  - `String? formatSoundDuration(int durationMs)`.
  - `class CatalogClient { CatalogClient(SlimshotApi api); Future<List<CatalogCategory>> categories(String root); Future<CatalogPage> sounds(String category, {String? cursor, int limit = 30}); Future<DownloadTicket> download(String id); }`
  - `int? retryAfterSeconds(SlimshotApiException e)` — reads `details['retryAfterSeconds']`.

- [ ] **Step 1: Write the failing tests**

`slimshot_api_test.dart`, group `public envelopes`:
- `keeps a list data and the meta` — MockClient returns `{"success":true,"data":[1,2],"meta":{"nextCursor":"c"}}`; expect `data == [1,2]`, `meta['nextCursor'] == 'c'`, and the request had no `Authorization` header.
- `an error envelope throws its code and details` — 429 body with `RATE_LIMITED`, `details.retryAfterSeconds 41`; expect `throwsCode('RATE_LIMITED')` and `retryAfterSeconds(e) == 41`.

`catalog_client_test.dart` (fixtures copied verbatim from contract §3.1–3.3):
- `categories asks for kind=audio and the root` — asserts query `kind=audio&root=sound-effects`, GET, and parses `UI` with one child `ui-clicks`.
- `sounds parses rows and the cursor` — two rows; second has `cover: null` → `coverUrl == null`; `nextCursor == 'cm2a2'`; query carries `category`, `limit=30`, and `cursor` only when given.
- `a row without id or title is dropped` — data `[{"title":"x"},{"id":"a","title":""},{valid}]` → one item.
- `download POSTs with no body and parses the ticket` — method POST, path `/api/app/v1/catalog/assets/cm2a1/download`, `format == 'mp3'`, `byteSize == 81234`.
- `404 surfaces NOT_FOUND`.

`catalog_models_test.dart`, `formatSoundDuration`: `400 → '0.4s'`, `9940 → '9.9s'`, `9960 → '0:10'`, `65000 → '1:05'`, `0 → null`, `4000 → '4.0s'`.

- [ ] **Step 2: Run** `flutter test test/core/services/slimshot_api_test.dart test/features/sound_library/` — Expected: FAIL (undefined names).

- [ ] **Step 3: Implement** the Interfaces above. Parse defensively (`(x as num?)?.toInt() ?? 0`, non-list `data` → empty list).

- [ ] **Step 4: Run** the same command — Expected: PASS. Then `flutter analyze --no-pub` — Expected: 44 issues.

- [ ] **Step 5: Commit** `feat(sounds): catalogue client for the server's sound library`.

---

### Task 2: The library on the phone

**Files:**
- Create: `lib/features/sound_library/data/sound_library.dart`
- Test: `test/features/sound_library/sound_library_test.dart`

**Interfaces:**
- Consumes: `CatalogSound`, `DownloadTicket` (Task 1).
- Produces:
  - `LibrarySound {String id, title, filePath; int durationMs; String? categorySlug, categoryName, coverPath; DateTime downloadedAt}` with `toJson`/`fromJson` (stores file *names*, resolves paths against the folder).
  - `class SoundLibrary { SoundLibrary({http.Client? client, Directory? root}); Future<List<LibrarySound>> load(); LibrarySound? find(String id); Future<LibrarySound> download(CatalogSound sound, DownloadTicket ticket, {void Function(double progress)? onProgress}); }`
  - `load()` newest first; drops entries whose file is missing; corrupt index → empty list.
  - `download` dedupes: a second call for an id already in flight returns the same `Future`. Streams the GET (`client.send`), writes `<id>.part`, renames to `<id>.<format>`, then fetches the cover (failure ignored), then writes the index. A non-200 or stream error deletes the `.part`, leaves no index entry, and throws `SoundDownloadFailed`.

- [ ] **Step 1: Write the failing tests** (temp `Directory.systemTemp.createTemp`, `MockClient.streaming`):
- `a download writes the file and indexes it` — file `<id>.mp3` exists with the bytes; `find(id)` non-null; no `.part` left.
- `progress reports received over byteSize` — last value `1.0`.
- `a failed stream leaves no file and no entry` — stream errors halfway; expect throws `SoundDownloadFailed`, no `.part`, no `.mp3`, `find(id) == null`.
- `two downloads of one id make one request` — call twice before awaiting; MockClient counter `== 1` for the sound url.
- `a cover that fails still downloads the sound` — cover url 500; entry present, `coverPath == null`.
- `the index survives a reload` — new `SoundLibrary(root:)`, `load()` returns the entry.
- `an entry whose file is gone is dropped on load`.
- `a corrupt index reads as empty` — write `{not json`; `load()` returns `[]`, no throw.

- [ ] **Step 2: Run** `flutter test test/features/sound_library/sound_library_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** per Interfaces; index write is temp file + `rename`.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(sounds): a library of downloaded sounds that works offline`.

---

### Task 3: The browse cache

**Files:**
- Create: `lib/features/sound_library/data/catalog_cache.dart`
- Test: `test/features/sound_library/catalog_cache_test.dart`

**Interfaces:**
- Consumes: `CatalogCategory`, `CatalogSound` (Task 1).
- Produces: `class CatalogCache { CatalogCache({Directory? root}); Future<void> load(); List<CatalogCategory> get categories; List<CatalogSound> firstPage(String category); Future<void> saveCategories(List<CatalogCategory>); Future<void> saveFirstPage(String category, List<CatalogSound>); }` — `root` defaults to `getApplicationSupportDirectory()`.

- [ ] **Step 1: Write the failing tests:** `round-trips categories and first pages` (new instance, `load()`, equal by ids/titles); `an unknown category has no page`; `a corrupt file reads as empty`.
- [ ] **Step 2: Run** `flutter test test/features/sound_library/catalog_cache_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement**; write via temp file + rename.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(sounds): keep the last pills and first pages for offline`.

---

### Task 4: The sheet's controller

**Files:**
- Create: `lib/features/sound_library/sound_effects_controller.dart`, `lib/features/sound_library/providers.dart`
- Test: `test/features/sound_library/sound_effects_controller_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `abstract class SoundPreviewPlayer { Future<void> play(String path); Future<void> stop(); Future<double?> durationOf(String path); Future<void> dispose(); }` and `JustAudioPreviewPlayer` implementing it (untested plugin code, as `PluginRewardedAdPlayer` is).
  - `const kDownloadedPill = '__downloaded__';`
  - `class SoundEffectsController extends ChangeNotifier`, constructor `({required CatalogClient client, required SoundLibrary library, required CatalogCache cache, required SoundPreviewPlayer player, String root = kSoundEffectsRoot, DateTime Function() now = DateTime.now})`.
  - State getters: `List<String> pills` (`kDownloadedPill` first, then root children's slugs), `String pillName(String slug)`, `String selected`, `List<CatalogSound> sounds` (for Downloaded: library entries as `CatalogSound`s), `bool loading`, `bool offline`, `bool hasMore`, `bool inLibrary(String id)`, `double? progressOf(String id)` (null = not downloading), `String? playingId`.
  - Commands: `Future<void> open()` (cache first, then server; opens on first server pill else Downloaded), `Future<void> select(String pill)`, `Future<void> loadMore()`, `Future<void> refresh()`, `Future<void> retry()`, `Future<void> tapRow(CatalogSound s)` (listen), `Future<LibrarySound?> add(CatalogSound s)` (download if needed; null when refused or failed).
  - Event stream for the widget: `Stream<SoundSheetNotice> notices` with `SoundSheetNotice.downloadFailed(title)`, `.unavailable(title)`.
  - Providers in `providers.dart`: `catalogClientProvider` (over `accountApiProvider`), `soundLibraryProvider`, `catalogCacheProvider` — plain `Provider`s, app-wide (the library dedupes downloads across sheet openings).
- Rules the tests pin (spec §3, §3.1, §5):
  - Offline (`SocketException`, `TimeoutException`, `http.ClientException`, `badResponse`) → `offline = true`, cached rows kept.
  - 404 on categories → pills = `[kDownloadedPill]`, `offline == false`.
  - 404 on a list → reload pills; if the pill is gone, select Downloaded.
  - 429 → no automatic request until `now()` passes `retryAfterSeconds`; `retry()` inside the window waits for it (use an injectable delay: `Future<void> Function(Duration) wait = Future.delayed`).
  - Every response checks it still belongs to the request that is current (a request token per `select`/`refresh`), else it is dropped.
  - Rows are deduplicated by id when pages append.
  - `tapRow`: in library → stop if playing it, else play it; not in library and online → download, then play **only if** no other row was tapped meanwhile; offline and not in library → nothing.
  - `add`: one in flight at a time (a second call while one runs returns null); stops the preview; downloads through the same `SoundLibrary.download` (so a listen in flight is shared); 404 removes the row and emits `downloadFailed`; 403 emits `unavailable`; other failures emit `downloadFailed`. If the entry's `durationMs` is 0, fills it from `player.durationOf`; null duration → failure.
  - After `dispose()`: nothing notifies, nothing plays, an `add` in flight resolves to null.

- [ ] **Step 1: Write the failing tests** (fakes: a `MockClient` for the server and downloads, temp-dir `SoundLibrary` and `CatalogCache`, `FakePreviewPlayer` recording calls):
- `pills are Downloaded then the server's order`
- `cached rows show before the server answers`
- `offline keeps cached rows and says so`
- `a missing root shows Downloaded only, no error`
- `a vanished category falls back to Downloaded`
- `rate limited waits before asking again`
- `stale page for a previous pill is dropped`
- `refresh during paging leaves no duplicate ids`
- `loadMore stops at a null cursor`
- `tapping a row not in the library downloads then plays it`
- `tapping it again stops it`
- `tapping another row mid-download keeps the first unplayed`
- `+ on a library sound adds without a request`
- `+ on a new sound downloads then returns it`
- `a listen then a + on one sound makes one download`
- `a second + while adding is ignored`
- `+ when the sound was removed drops the row and says it failed`
- `+ on a gated sound says it is unavailable`
- `a zero duration is read from the file`
- `dispose during a download adds nothing and does not throw`

- [ ] **Step 2: Run** `flutter test test/features/sound_library/sound_effects_controller_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** per Interfaces and rules.
- [ ] **Step 4: Run** — Expected: PASS; full `flutter test` green; analyzer 44.
- [ ] **Step 5: Commit** `feat(sounds): the sound effects sheet's state and rules`.

---

### Task 5: Adding a library sound to the timeline

**Files:**
- Modify: `lib/features/video_editor/providers/video_editor_notifier.dart`
- Test: `test/features/video_editor/providers/add_library_sound_test.dart`

**Interfaces:**
- Consumes: `LibrarySound` (Task 2).
- Produces: `void VideoEditorNotifier.addLibrarySound(LibrarySound sound)` — builds an `AudioTrackModel` (new uuid, `filePath`, `sourceDuration = durationMs / 1000`, `sourceStart 0`, `sourceEnd` = duration, `timelineStart = state.currentPlaybackPosition`) and calls `addAudioTrack`.

- [ ] **Step 1: Write the failing tests:** `lands at the playhead with its full length`; `takes a free lane when the playhead's lane is busy` (an audio track already covering the playhead on lane 0 → new track on lane 1); `is one undo step and selected` (undo removes it; `selectedAudioId` is its id).
- [ ] **Step 2: Run** — Expected: FAIL. **Step 3: Implement.** **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(sounds): a library sound goes on the timeline at the playhead`.

---

### Task 6: The sheet

**Files:**
- Create: `lib/features/video_editor/widgets/panels/sound_effects_sheet.dart`
- Test: `test/features/video_editor/widgets/sound_effects_sheet_test.dart`

**Interfaces:**
- Consumes: `SoundEffectsController` (Task 4), `formatSoundDuration` (Task 1).
- Produces: `class SoundEffectsSheet extends StatefulWidget { const SoundEffectsSheet({required SoundEffectsController controller, required void Function(LibrarySound) onAdd}); }` — owns nothing but layout; calls `controller.open()` in `initState`, `controller.dispose()` in `dispose`; on a `LibrarySound` from `add` calls `onAdd` then `Navigator.pop`. Notices → `ToastUtils.show(..., isError: true)` with the Global Constraints copy.
- Layout (spec §3): grab handle (`white24`), scrolling pill row (`primaryStart` over `border` when chosen; first pill labelled `Downloaded`), offline line, `RefreshIndicator` list, rows 48px cover (rounded 8, `AppColors.previewStage`; network image with the default-cover widget as error/placeholder; `Image.file` for a library cover), title one line ellipsised `textPrimary`, duration `textSecondary`, trailing `plus` / progress ring; a ring over the cover while a listen downloads; `pause` over the cover while playing; rows not in the library dimmed when offline. Skeletons: three grey rows while `loading && sounds.isEmpty`.

- [ ] **Step 1: Write the failing tests** (a controller over fakes from Task 4's test support — move those fakes to `test/features/sound_library/support.dart`):
- `shows Downloaded first and the server pills after`
- `a row shows title, duration and a plus`
- `tapping + adds, closes, and calls onAdd once`
- `tapping a row plays it and shows pause`
- `offline shows the line and Retry calls retry`
- `an empty pill says so`
- `a failed download toasts` (use `settleToast`)
- `no overflow at 320px with text at 1.3x` (long titles, all states)
- [ ] **Step 2: Run** — Expected: FAIL. **Step 3: Implement.** **Step 4: Run** this file and `test/features/video_editor/widgets/panel_theme_test.dart` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(sounds): the sound effects sheet`.

---

### Task 7: Wire it into the editor, then the docs

**Files:**
- Modify: `lib/screens/video_editor_screen.dart` (`_audioMenu` entry, handler), `lib/features/video_editor/logic/toolbar_visibility.dart`, `test/features/video_editor/widgets/editor_menu_test.dart`, `test/features/video_editor/logic/toolbar_visibility_test.dart`, `CLAUDE.md`, `docs/roadmap.md`

**Interfaces:**
- Consumes: Tasks 4–6.
- Produces: audio menu `EditorTool(id: 'sound_effects', label: 'Effects', icon: LucideIcons.sparkles)`; `isToolbarToolVisible(..., required bool hasCatalogServer)` returning it for `sound_effects`; the screen passes `SlimshotApi.isConfigured`. The handler builds a `SoundEffectsController` from the providers and `JustAudioPreviewPlayer()`, opens `showEditorSheet(builder: (_) => SoundEffectsSheet(controller: c, onAdd: notifier.addLibrarySound))`. The `effects` handler's `currentMenuId == 'edit'` gate and its comment about the audio menu go (the id no longer collides).

- [ ] **Step 1: Update the failing tests:** `editor_menu_test.dart` line 181 → `_audioMenu` contains `id: 'sound_effects'` and not `id: 'effects'`; the handler `tool.id == 'sound_effects'` opens `SoundEffectsSheet`. `toolbar_visibility_test.dart`: `sound_effects` hidden without a server, shown with one.
- [ ] **Step 2: Run** both — Expected: FAIL. **Step 3: Implement.** **Step 4: Run** full `flutter test`, `flutter analyze --no-pub` (44), and `flutter build apk --debug --dart-define-from-file=env/env.json` — Expected: green, 44, build succeeds.
- [ ] **Step 5: Docs.** CLAUDE.md: a "Sound effects library" section (awaiting device verification) — the one hardcoded root, tap to listen / + to add and why (download is the preview; counts as a download), the library folder and why not temp or `drafts/`, the browse cache, no delete; remove the "audio menu's `effects` entry stays" sentence from Rules to protect. Roadmap: Stage 3 status. Commit `feat(sounds): Effects on the audio menu opens the sound library`.

## Self-review notes

- Spec §1 → Task 7; §2.1 → Task 1; §2.2 → Task 2; §2.3 → Task 3; §3/§3.1/§5 → Tasks 4, 6; §4 → Tasks 4 (duration fill), 5; §6 → every task.
- Ruling recorded here: the default cover is a widget, not `assets/images/sound_cover_default.png` as the spec says — `pubspec.yaml` lists only `assets/`, and a widget needs no asset declaration. Cost if wrong: swap for an image later.
