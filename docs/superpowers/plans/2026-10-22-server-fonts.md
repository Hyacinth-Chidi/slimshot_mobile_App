# Fonts from the Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `google_fonts` with fonts downloaded from SlimShot's server, shown in the text
editor's Font tab as one CapCut-style grid, with only Montserrat Bold, Bebas Neue and Poppins
bundled.

**Architecture:** A new `lib/features/fonts/` feature mirrors the sound library: a client for the
catalogue's font endpoints, a library of files on the phone, a cache of the saved lists and their
preview images, a registry that hands font bytes to Flutter's text engine, a service that makes a
named font available, and a grid controller plus widget for the Font tab. A text keeps naming its
font in `fontFamily` (family, plus style when not Regular), so drafts, templates and caption
styles are untouched; `getFontStyle` becomes a plain `TextStyle(fontFamily:)`.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, Riverpod, `http` + `MockClient` in tests,
`path_provider`, `dart:ui` `loadFontFromList`.

**Spec:** `docs/superpowers/specs/2026-10-22-server-fonts-design.md`. Server contract:
`../slimshot_server/docs/app-catalog-api.md` §8.

## Global Constraints

- Endpoints, under `SlimshotApi.uri('/catalog...')`, all public (`sendPublicEnvelope`):
  `GET /catalog/fonts?category=<slug>` (one list, no paging), `GET /catalog/fonts/<id>`,
  `GET /catalog/fonts/by-family/<url-encoded familyName>`, `POST /catalog/assets/<id>/download`.
- Category slugs: `trending`, then `more-fonts`. A 404 for one means that list is empty.
- Font item fields: `id`, `displayName`, `familyName`, `styleName`, `version`, `format`
  (`ttf`|`otf`), `preview {url, width, height}` (480×160, white on transparent, shown on a dark
  tile). Download ticket: `url` (valid 10 minutes, never stored), `expiresAt`, `filename`,
  `format`, `byteSize`, `version`.
- 429 `RATE_LIMITED` carries `details.retryAfterSeconds`; wait that long before the next
  automatic request.
- **A font's name:** `familyName` when `styleName` is Regular (case-insensitive, trimmed),
  otherwise `'$familyName $styleName'`. It is what `TextOverlayModel.fontFamily` holds and what the
  font is registered under. Names compare case-insensitively when de-duplicating.
- System is the name `Roboto`. Bundled names: `Montserrat Bold`, `Bebas Neue`, `Poppins`.
- Files: `<documents>/font_library/<id>-v<version>.<format>` (written as `.part`, renamed when
  whole) and `library.json` (written through a temp file). Lists:
  `<app support>/font_catalog.json`. Previews: `<app support>/font_previews/`.
- The saved list is refetched when the Font tab opens if older than **5 minutes**, and on
  pull-to-refresh.
- No request to Google. `google_fonts` leaves `pubspec.yaml`. The draft format does not change.
- `getFontStyle` stays synchronous.
- Copy: "No internet connection", "Couldn't download this font",
  "A font in this project couldn't be downloaded".
- Colours from `AppColors`; a selected tile is `primaryStart` over `border`; toasts through
  `ToastUtils`.
- `flutter analyze --no-pub` gains no issues (44 today). Every commit runs `flutter test` on the
  touched tests; the last task runs the whole suite and the Kotlin suite.

## Review Focus

1. **A downloaded file the text engine refuses** (a truncated file, an error page saved as a
   font): registration answers false, the text keeps drawing in System, nothing throws, and the
   next request downloads again. Test in Task 6.
2. **A server font named like a bundled one in another case** ("bebas neue"): it does not show
   twice. Test in Task 8.
3. **The text editor closed while a font downloads**: the download finishes, nothing is applied
   to a closed sheet. Test in Task 8.
4. **A build with no server address**: the grid shows System and the bundled fonts, makes no
   request and raises no notice. Test in Task 8.
5. **A rate-limited list (429)**: the saved list stays on screen and no request is made until
   `retryAfterSeconds` has passed. Test in Task 8.

---

### Task 1: The test font moves off Ariana Violeta

Ariana Violeta leaves the app (Task 11), and `kTestFontFamily` measures text in tests with it.

**Files:**
- Modify: `test/support/test_fonts.dart` (`kTestFontFamily` → `'Montserrat Bold'`, comment updated)
- Modify: any test whose assertion is a number measured with the old font (found by the run)

**Interfaces:**
- Produces: `kTestFontFamily == 'Montserrat Bold'` for every later task.

- [ ] **Step 1: Change `kTestFontFamily` to `'Montserrat Bold'`** (a bundled asset that stays).
- [ ] **Step 2: Run the whole suite**
  Run: `flutter test > <workspace>/t1.txt 2>&1; tail -5 <workspace>/t1.txt`
  Expected: the failures, if any, are assertions on measured pixel counts or widths.
- [ ] **Step 3: For each failure,** if the test's own comment says the number is measured
  (the reassembly halo counts, shadow reach measurements), re-measure with Montserrat Bold and
  update the number and its comment. A failure that is not a measured number is a real
  behaviour difference: stop and debug it (superpowers:systematic-debugging).
- [ ] **Step 4: Run the whole suite** — Expected: all pass.
- [ ] **Step 5: Commit** — `test: measure text with Montserrat Bold, a font that stays`

### Task 2: The interface font and the bundled set leave Google Fonts

**Files:**
- Create: `assets/fonts/PlusJakartaSans-Medium.ttf`, `-SemiBold.ttf`, `-ExtraBold.ttf`,
  `assets/fonts/BebasNeue-Regular.ttf`, `assets/fonts/Poppins-Regular.ttf`
- Create: `lib/core/theme/app_fonts.dart`
- Modify: `pubspec.yaml` (`fonts:`), `lib/core/theme/app_theme.dart`,
  `lib/core/widgets/gradient_button.dart`, `lib/screens/history_screen.dart`,
  `lib/screens/home_screen.dart`, `lib/screens/main_shell_screen.dart`,
  `lib/screens/onboarding_screen.dart`, `lib/screens/update_screen.dart`,
  `lib/screens/workspace_screen.dart`, `lib/core/legal/third_party_licences.dart`
- Test: `test/core/theme/app_fonts_test.dart`, `test/core/legal/third_party_licences_test.dart`

**Interfaces:**
- Produces: `const String kInterfaceFontFamily = 'Plus Jakarta Sans';` in `app_fonts.dart`.
- Produces: pubspec families `Plus Jakarta Sans` (weights 400, 500, 600, 700, 800), `Bebas Neue`,
  `Poppins` (and `Montserrat Bold` as today).

- [ ] **Step 1: Fetch the files.** Static OFL TTFs: Plus Jakarta Sans Medium, SemiBold and
  ExtraBold from `github.com/tokotype/PlusJakartaSans` (its static `ttf` folder);
  `BebasNeue-Regular.ttf` and `Poppins-Regular.ttf` from `github.com/google/fonts`
  (`ofl/bebasneue/`, `ofl/poppins/`). Check each with the name-table probe used for the
  bundled fonts (family, style, and the nameID 0 copyright line, which Step 6 needs).
- [ ] **Step 2: Write the failing tests.**
  `app_fonts_test.dart`: `'the theme reads the bundled interface font'` —
  `AppTheme.darkTheme.textTheme.bodyMedium!.fontFamily`
  equals `kInterfaceFontFamily`, and no text style in it has a `fontFamily` naming a Google
  Fonts generated family (they look like `'PlusJakartaSans_regular'`).
  `third_party_licences_test.dart`: `'the bundled fonts carry their OFL notices'` — after
  `registerThirdPartyLicences()`, `LicenseRegistry.licenses` has entries whose `packages` include
  `Montserrat`, `Bebas Neue`, `Poppins` and `Plus Jakarta Sans`, each paragraph text containing
  `SIL Open Font License`.
- [ ] **Step 3: Run them** — Expected: FAIL (no `app_fonts.dart`, no font notices).
- [ ] **Step 4: Implement.** pubspec families as above. `app_theme.dart`: the theme's base text
  theme `.apply(fontFamily: kInterfaceFontFamily)` in place of
  `GoogleFonts.plusJakartaSansTextTheme`, keeping every weight it sets. Every
  `GoogleFonts.plusJakartaSans(...)` call becomes `TextStyle(fontFamily: kInterfaceFontFamily, ...)`
  with the same arguments. `third_party_licences.dart`: one OFL 1.1 notice per font family,
  the copyright line from its file, registered in `registerThirdPartyLicences()` beside the GL
  Transitions notice.
- [ ] **Step 5: Run the two tests and the screens' existing tests**
  (`test/screens/`, `test/core/`) — Expected: PASS.
- [ ] **Step 6: Commit** — `feat(fonts): bundle the interface font and the editor's three fonts`

### Task 3: The font catalogue's models and client

**Files:**
- Create: `lib/features/fonts/data/font_models.dart`, `lib/features/fonts/data/font_client.dart`
- Test: `test/features/fonts/font_models_test.dart`, `test/features/fonts/font_client_test.dart`,
  `test/features/fonts/support.dart` (a `FakeFontServer` built like
  `test/features/sound_library/support.dart`'s `FakeCatalogServer`: keys `fonts:<slug>`,
  `font:<id>`, `family:<name>`, `download:<id>`, `file:<id>`, `preview:<id>`; `gates`,
  `overrides`, `hits`)

**Interfaces:**
- Produces:
  - `String fontNameFor(String familyName, String styleName)`
  - `class ServerFont { id, displayName, familyName, styleName, int version, String format, String? previewUrl; String get name; static ServerFont? tryParse(Object? json); Map<String, Object?> toJson(); }`
  - `List<ServerFont> parseServerFonts(Object? data)` (skips rows that do not parse)
  - `class FontDownloadTicket { url, filename, format, int byteSize, int version; static FontDownloadTicket? tryParse(Object? json); }`
  - `const String kTrendingFontsCategory = 'trending'; const String kMoreFontsCategory = 'more-fonts';`
  - `class FontClient { FontClient(SlimshotApi api); Future<List<ServerFont>> list(String category); Future<ServerFont> byId(String id); Future<ServerFont> byFamily(String familyName); Future<FontDownloadTicket> download(String id); }`

- [ ] **Step 1: Write the failing tests.**
  `font_models_test.dart`:
  - `'a Regular face is named by its family'`: `fontNameFor('Playfair Display', 'Regular') == 'Playfair Display'`; `fontNameFor('Inter', ' regular ') == 'Inter'`.
  - `'any other face adds its style'`: `fontNameFor('Lato', 'Bold') == 'Lato Bold'`; `fontNameFor('Lato', 'Bold Italic') == 'Lato Bold Italic'`.
  - `'a row missing id or family is skipped, a missing preview is not'`.
  - `'toJson round-trips'`.
  `font_client_test.dart`:
  - `'list asks for the category'` (request path `/api/app/v1/catalog/fonts`, query `category=trending`).
  - `'by family encodes the name'` (path ends `/fonts/by-family/Playfair%20Display`).
  - `'download posts to the asset and reads the version'` (POST, ticket `version == 2`).
  - `'a 404 is a NOT_FOUND exception'`.
- [ ] **Step 2: Run them** — `flutter test test/features/fonts` — Expected: FAIL (files missing).
- [ ] **Step 3: Implement** the models and the client over `SlimshotApi.sendPublicEnvelope`, the
  way `CatalogClient` does; a ticket or item that does not parse throws
  `SlimshotApiException(SlimshotApiException.badResponse, ...)`.
- [ ] **Step 4: Run them** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(fonts): the font catalogue's models and client`

### Task 4: Fonts on the phone

**Files:**
- Create: `lib/features/fonts/data/font_library.dart`
- Test: `test/features/fonts/font_library_test.dart`

**Interfaces:**
- Consumes: `ServerFont`, `FontDownloadTicket` (Task 3).
- Produces:
  - `class LibraryFont { name, id, displayName, familyName, styleName, int version, String filePath }`
  - `class FontDownloadFailed implements Exception { String message; bool offline; }`
  - `class FontLibrary { FontLibrary({http.Client? client, Directory? root}); Future<List<LibraryFont>> load(); LibraryFont? find(String name); Future<LibraryFont> download(ServerFont font, FontDownloadTicket ticket, {void Function(double progress)? onProgress}); }`
  — `find` compares names case-insensitively and answers from what `load` read.

- [ ] **Step 1: Write the failing tests** (a temp `root`, a `MockClient`):
  - `'a download lands as a file and an index entry'` (file `<id>-v1.ttf` exists, `find('Lato Bold')` has it).
  - `'a new instance on the same folder finds it'`.
  - `'a half-written file is never taken for a font'` (a `.part` left in the folder, no entry).
  - `'an entry whose file is gone is dropped'`.
  - `'two downloads of one font share one request'` (the fake counts one `file:` hit).
  - `'a higher version replaces the entry and removes the old file'`.
  - `'no connection is an offline failure'` (`http.ClientException` → `offline == true`).
- [ ] **Step 2: Run them** — Expected: FAIL.
- [ ] **Step 3: Implement** after `SoundLibrary`: `<documents>/font_library/`, `.part` then rename,
  `library.json` through a `.tmp` rename with one write at a time, file names (not paths) in
  the index. The old version's file is deleted only after the index naming the new one is written.
- [ ] **Step 4: Run them** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(fonts): a library of fonts kept on the phone`

### Task 5: The saved lists and their preview images

**Files:**
- Create: `lib/features/fonts/data/font_catalog_cache.dart`, `lib/features/fonts/data/font_preview_cache.dart`
- Test: `test/features/fonts/font_catalog_cache_test.dart`, `test/features/fonts/font_preview_cache_test.dart`

**Interfaces:**
- Produces:
  - `class SavedFontLists { List<ServerFont> trending; List<ServerFont> more; DateTime fetchedAt; }`
  - `class FontCatalogCache { FontCatalogCache({Directory? root}); Future<SavedFontLists?> load(); Future<void> save(SavedFontLists lists); }`
  - `bool isStale(SavedFontLists lists, DateTime now, {Duration maxAge = const Duration(minutes: 5)})`
  - `class FontPreviewCache { FontPreviewCache({http.Client? client, Directory? root}); File? fileFor(String url); Future<File?> fetch(String url); Future<void> fetchAll(Iterable<String> urls); }`
  — `fileFor` is synchronous and answers only for a preview already on disk (after `fetch` or a
  previous run); the file name is derived from the URL deterministically.

- [ ] **Step 1: Write the failing tests:**
  - `'saved lists round-trip with their time'`; `'a corrupt file reads as nothing saved'`.
  - `'stale after five minutes'`: 4:59 → false, 5:01 → true.
  - `'a preview is fetched once and then read from disk'` (one `preview:` hit for two `fetch` calls; a new instance's `fileFor` finds it).
  - `'a preview that fails to fetch answers null, never throws'`.
- [ ] **Step 2: Run them** — Expected: FAIL.
- [ ] **Step 3: Implement**: the lists under `<app support>/font_catalog.json` through a temp
  rename; previews under `<app support>/font_previews/`, `fetchAll` at most 4 at a time.
- [ ] **Step 4: Run them** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(fonts): saved font lists and preview images`

### Task 6: Registering fonts, a plain getFontStyle, and an export that does not wait

**Files:**
- Create: `lib/features/fonts/font_names.dart`, `lib/features/fonts/font_registry.dart`
- Modify: `lib/features/video_editor/utils/font_utils.dart`,
  `lib/features/video_editor/services/native_timeline_preview_service.dart`
- Delete: `lib/features/video_editor/services/export_fonts.dart`,
  `test/features/video_editor/services/export_fonts_test.dart`
- Test: `test/features/fonts/font_registry_test.dart`, `test/features/fonts/font_names_test.dart`,
  the export tests that passed `fontsReady:` (`caption_audio_channel_test.dart`,
  `caption_highlight_atlas_test.dart`)

**Interfaces:**
- Consumes: `FontLibrary.load/find` (Task 4).
- Produces:
  - `const String kSystemFontName = 'Roboto';`
  - `const List<String> kBundledFontNames = ['Montserrat Bold', 'Bebas Neue', 'Poppins'];`
  - `const List<String> kServerTemplateFontNames = ['Abril Fatface', 'Inter', 'Montserrat', 'Nunito', 'Oswald', 'Permanent Marker', 'Playfair Display', 'Press Start 2P', 'Righteous', 'Sacramento'];`
  - `bool isLocalFontName(String name)` (System or bundled, case-insensitive)
  - `class FontRegistry { FontRegistry({Future<void> Function(Uint8List bytes, String name)? loader}); static final FontRegistry instance; bool isAvailable(String name); Future<bool> registerFile(String name, String path); Listenable get changes; }`
    — `isAvailable` is true for local names and registered names; `registerFile` registers a name
    once per session, answers false (and does not register) when the file is missing or the
    loader throws, and notifies `changes` after a new registration.
  - `Future<void> registerFontsOnPhone(Iterable<String> names, {FontLibrary? library, FontRegistry? registry})`
    — registers each non-local name found in the library.
  - `NativeTimelinePreviewService({..., Future<void> Function(Iterable<String> fontNames)? registerFonts})`
    replacing `fontsReady` / `fontsTimeout`; default `registerFontsOnPhone` with a `FontLibrary()`.
  - `font_utils.dart`: `getFontStyle(...)` returns `TextStyle(fontFamily: name, ...)` with the
    same parameters, always. `allFonts` stays for now as
    `[kSystemFontName, ...kBundledFontNames, ...kServerTemplateFontNames]` (Task 11 deletes it).

- [ ] **Step 1: Write the failing tests:**
  - `'local names are always available'`; `'a registered name is available'`.
  - `'a name registers once'` (the fake loader runs once for two calls).
  - `'registering notifies changes'`.
  - `'a file the engine refuses is not registered and does not throw'` (loader throws →
    `false`, `isAvailable` false, a later call tries again) — Review Focus 1.
  - `'a missing file answers false'`.
  - `'every template and caption font is local or a server template font'` — over
    `kTextTemplates` and `kCaptionPresets`.
  - Export: `'export registers the project's text fonts before it rasterises'` — a
    `registerFonts` fake records the names; `exportVideo` on a state with texts in
    `'Playfair Display'` and `'Poppins'` calls it with both before the rasteriser runs.
- [ ] **Step 2: Run them** — Expected: FAIL.
- [ ] **Step 3: Implement.** The default loader is `ui.loadFontFromList(bytes, fontFamily: name)`.
  `exportVideo` calls `registerFonts(state.textOverlays.map((t) => t.fontFamily))` where it
  awaited `awaitExportFonts`, and the font warning goes with it.
- [ ] **Step 4: Run the new tests and `test/features/video_editor/services`** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(fonts): register downloaded fonts; export no longer waits`

### Task 7: Making a named font available

**Files:**
- Create: `lib/features/fonts/font_service.dart`, `lib/features/fonts/providers.dart`
- Test: `test/features/fonts/font_service_test.dart`

**Interfaces:**
- Consumes: `FontClient` (3), `FontLibrary` (4), `FontCatalogCache` (5), `FontRegistry` (6).
- Produces:
  - `class FontService { FontService({required FontClient client, required FontLibrary library, required FontCatalogCache cache, FontRegistry? registry});`
    - `Future<bool> ensureAvailable(String name, {void Function(double progress)? onProgress})`
    - `Future<void> prefetch(Iterable<String> names)`
    - `Future<void> updateOutdated(Iterable<ServerFont> listed)`
    - `Future<void> registerOnPhone(Iterable<String> names) }`
  - `providers.dart`: `fontClientProvider`, `fontLibraryProvider`, `fontCatalogCacheProvider`,
    `fontPreviewCacheProvider`, `fontServiceProvider` — app-wide `Provider`s, the client over
    `accountApiProvider` like `catalogClientProvider`.

- [ ] **Step 1: Write the failing tests:**
  - `'a local name needs nothing'` (true, zero requests).
  - `'a font on the phone is registered without a request'`.
  - `'a font in the saved lists is downloaded by its id'`.
  - `'otherwise the family lookup finds a Regular face'` (`family:Righteous` hit, then download).
  - `'a family lookup that answers another face is refused'` (name `'Lato Bold'` is never
    looked up by family; a `byFamily('Lato')` answer is not used for it) → false.
  - `'no connection answers false and throws nothing'`.
  - `'two calls for one name share one download'`.
  - `'a higher version is downloaded, an equal one is not'`; `'an updated font already
    registered this session is not registered again'`.
- [ ] **Step 2: Run them** — Expected: FAIL.
- [ ] **Step 3: Implement.** Resolution order: registry, library, saved lists (by `name`), then
  `byFamily(name)` accepted only if the answer's `name` equals `name` (case-insensitive). A
  download asks `client.download(id)` for a fresh ticket every time. In-flight calls are shared
  per name. Failures answer false.
- [ ] **Step 4: Run them** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(fonts): make a named font available on the phone`

### Task 8: The Font tab's grid: order, search, and choosing

**Files:**
- Create: `lib/features/fonts/font_grid.dart`
- Test: `test/features/fonts/font_grid_test.dart`

**Interfaces:**
- Consumes: Tasks 3–7.
- Produces:
  - `enum FontSource { system, bundled, server }`
  - `class FontEntry { String name; String label; FontSource source; ServerFont? font; }`
    — System's label is `'SYSTEM'`; a bundled font's label is its name; a server font's is its
    `displayName`.
  - `List<FontEntry> fontGridEntries({required List<ServerFont> trending, required List<ServerFont> more})`
  - `List<FontEntry> filterFontEntries(List<FontEntry> entries, String query)` — lowercase,
    spaces, `-` and `_` removed on both sides; matches label or name.
  - `sealed class FontTileState` with `FontReady`, `FontNotOnPhone`, `FontDownloading(double progress)`,
    `FontFailed`.
  - `class FontGridController extends ChangeNotifier { FontGridController({required FontService service, required FontClient client, required FontCatalogCache cache, required FontLibrary library, required FontPreviewCache previews, bool serverConfigured = SlimshotApi.isConfigured, DateTime Function()? now});`
    - `Future<void> open()`, `Future<void> refresh()`
    - `List<FontEntry> get entries` (filtered), `set query(String)`
    - `FontTileState stateOf(FontEntry entry)`
    - `Future<void> choose(FontEntry entry, ValueChanged<String> apply)`
    - `String? takeNotice() }`

- [ ] **Step 1: Write the failing tests:**
  - `'System, the bundled fonts, Trending, then More fonts'`.
  - `'a server font named like a local one is left out'` (including `'bebas neue'`, Review
    Focus 2); `'a font in both lists shows once, first place'`.
  - `'search ignores case, spaces, dashes and underscores'` (`'playfair-display'` finds
    Playfair Display).
  - `'the saved lists show at once, then the server's'`.
  - `'a list under five minutes old is not fetched again'`.
  - `'a missing More fonts category leaves Trending'` (404 for `more-fonts`).
  - `'a rate-limited list keeps the saved one and waits'` (429 with `retryAfterSeconds: 30`;
    `refresh()` 10 s later makes no request; 31 s later does) — Review Focus 5.
  - `'with no server address it lists local fonts and asks nothing'` (`serverConfigured: false`,
    zero hits, no notice) — Review Focus 4.
  - `'choosing a font on the phone applies it at once'`.
  - `'choosing one not on the phone shows progress, then applies it'`.
  - `'the last choice wins'` (choose A, then B while A downloads: only `B` is applied).
  - `'a font that lands after the controller is disposed applies nothing'` — Review Focus 3.
  - `'no connection: "No internet connection", and the tile keeps its arrow'` (`FontFailed`,
    notice text exact); any other failure: `"Couldn't download this font"`.
- [ ] **Step 2: Run them** — Expected: FAIL.
- [ ] **Step 3: Implement.** `open()` reads the saved lists, publishes entries, and fetches both
  categories when they are missing or stale (each 404 an empty list; a 429 records the wait),
  saves them, then `previews.fetchAll` and `service.updateOutdated`. `choose` keeps a counter;
  an apply runs only when its count is still the latest and the controller is not disposed.
- [ ] **Step 4: Run them** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(fonts): the Font tab's grid order, search and choosing`

### Task 9: The grid in the text editor

**Files:**
- Create: `lib/features/fonts/widgets/font_grid_view.dart`
- Modify: `lib/features/video_editor/widgets/text_overlay/text_editor_dialog.dart`
  (`_buildFontPanel`, the `_fonts` field)
- Test: `test/features/fonts/font_grid_view_test.dart`

**Interfaces:**
- Consumes: `FontGridController` (8), the providers (7).
- Produces: `class FontGridView extends ConsumerStatefulWidget { const FontGridView({required String selectedName, required ValueChanged<String> onSelected}); }`
  — it builds its own `FontGridController` from the providers in `initState` and disposes it.

- [ ] **Step 1: Write the failing widget tests** (providers overridden with the Task 3 fake):
  - `'tiles in grid order, three to a row'`.
  - `'a server tile shows its preview, with an arrow until downloaded'`.
  - `'the selected font's tile wears the selected border'` (`primaryStart`).
  - `'a tap on a bundled tile selects it at once'`.
  - `'a tap on a server tile shows a ring, then selects it'`.
  - `'typing in search narrows the tiles'`.
  - `'the text editor's Font tab is the grid'` (open the editor on the Font tab; find
    `FontGridView` with the overlay's font as `selectedName`).
- [ ] **Step 2: Run them** — Expected: FAIL.
- [ ] **Step 3: Implement.** A search field above a `GridView` (`crossAxisCount: 3`,
  `childAspectRatio: 2.6`) inside a `RefreshIndicator` that calls `refresh()`. Tiles:
  `AppColors.surface` fill; System draws `SYSTEM` letter-spaced; bundled tiles draw their name in
  their own font in `AppColors.textPrimary`; server tiles draw the preview file
  (`Image.file`, `cacheWidth` at tile width) or the display name until it is on disk; a
  `LucideIcons.download` glyph top-left for `FontNotOnPhone`/`FontFailed`, a determinate
  `CircularProgressIndicator` for `FontDownloading`. A notice from `takeNotice()` goes through
  `ToastUtils.show(context, ..., isError: true)`. `_buildFontPanel` returns
  `FontGridView(selectedName: _fontFamily, onSelected: (name) { setState(() => _fontFamily = name); _updateOverlay(); })`.
- [ ] **Step 4: Run them, then `test/features/video_editor/widgets`** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(fonts): the text editor's Font tab is the server grid`

### Task 10: A project's fonts, tiles that fetch theirs, and text that redraws

**Files:**
- Create: `lib/features/fonts/project_fonts.dart`
- Modify: `lib/screens/video_editor_screen.dart` (`_loadDraft` at ~670, the
  `ref.listen<VideoEditorState>` at ~3341, where the templates sheet and the caption style sheet
  are opened), `lib/features/video_editor/widgets/text_overlay/text_editor_dialog.dart` (the
  Templates tab), `lib/features/video_editor/widgets/text_overlay/text_overlay_layer.dart`,
  `lib/features/video_editor/widgets/text_overlay/text_preview_tile.dart`
- Test: `test/features/fonts/project_fonts_test.dart`, `test/features/video_editor/widgets/text_preview_tile_test.dart` (extend)

**Interfaces:**
- Consumes: `FontService` (7), `FontRegistry.changes` (6).
- Produces:
  - `Set<String> fontsToFetch(Iterable<String> projectFonts, Set<String> alreadyAsked, bool Function(String name) isAvailable)`
  - `Set<String> templateFontNames(Iterable<TextTemplate> templates)`,
    `Set<String> captionPresetFontNames(Iterable<CaptionPreset> presets)` — each minus local names.
  - `const String kFontUnavailableMessage = "A font in this project couldn't be downloaded";`

- [ ] **Step 1: Write the failing tests:**
  - `'only fonts neither available nor asked are fetched'`.
  - `'template and caption fonts leave out the local ones'`.
  - `'a preview tile redraws when a font registers'` (pump a `TextPreviewTile`, register through
    a `FontRegistry` with a fake loader, pump: the tile rebuilt — e.g. its painter instance changed).
- [ ] **Step 2: Run them** — Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `_loadDraft`: after `notifier.loadDraft(draft)`, `await fontService.registerOnPhone(...)` with
    the draft's text fonts.
  - The state listener: `fontsToFetch(...)` over `state.textOverlays`; each name is marked asked
    and `ensureAvailable`d; the first false of the session shows `kFontUnavailableMessage` once.
  - Opening the templates sheet, the Templates tab, or the caption style sheet calls
    `fontService.prefetch(templateFontNames(...))` / `prefetch(captionPresetFontNames(...))`.
  - `TextOverlayLayer` and `TextPreviewTile` rebuild on `FontRegistry.instance.changes`
    (a `ListenableBuilder` around what measures and paints the text).
- [ ] **Step 4: Run them, then `test/features/video_editor` and `test/screens`** — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(fonts): fetch a project's and a grid's fonts; redraw when one lands`

### Task 11: Google Fonts and the decorative fonts leave the app

**Files:**
- Delete: `assets/fonts/ArianaVioleta-dz2K.ttf`, `BelieveIt-DvLE.ttf`, `ChrustyRock-ORLA.ttf`,
  `Debrosee-ALPnL.ttf`, `Newretrostyle3d-ygjm.ttf`, `ShadeBlue-2OozX.ttf`, `ShortBaby-Mg2w.ttf`,
  `SuperKindly-drE8E.ttf`, `AlteixsansRegulardemo-E4j1n.otf`, `font.zip`, `PlusJakartaSans.zip`
- Modify: `pubspec.yaml` (drop `google_fonts` and the 8 families; `flutter pub get`),
  `lib/main.dart` (drop `GoogleFonts.config`), `lib/features/video_editor/utils/font_utils.dart`
  (drop `allFonts`, `googleFontsList`, `customBundledFonts`, `isCustomFont`),
  `test/flutter_test_config.dart` (delete if it only configured Google Fonts),
  `test/support/test_fonts.dart` (comment), the tests that read `allFonts`
  (`caption_placement_test`, `caption_preset_catalog_test`, `new_text_test`,
  `text_template_catalog_test`)
- Create: `test/no_google_fonts_test.dart`

**Interfaces:**
- Consumes: `isLocalFontName`, `kServerTemplateFontNames` (6).

- [ ] **Step 1: Write the failing guard test** `'nothing in the app imports google_fonts'`: no
  file under `lib/` contains `package:google_fonts`, and `pubspec.yaml` has no `google_fonts:`.
- [ ] **Step 2: Run it** — Expected: FAIL (listing the files still importing it).
- [ ] **Step 3: Remove** as listed; the catalog tests check each font with
  `isLocalFontName(name) || kServerTemplateFontNames.contains(name)`.
- [ ] **Step 4: Run the whole suite** — `flutter test` and `flutter analyze --no-pub`
  — Expected: all pass; analyzer at 44 or fewer.
- [ ] **Step 5: Commit** — `chore(fonts): Google Fonts and the unlicensed fonts leave the app`

### Task 12: The notes

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write a "Fonts from the server" section** (awaiting device verification): the
  grid, the name rule, files and caches, registration and redraw, templates and captions, the
  export no longer waiting, the owner's two server to-dos; and correct what changed: the
  auto-captions "Export did not wait for fonts" paragraph (gone), the
  "Tests that measure text must use `kTestFontFamily`" paragraph (Montserrat Bold, no network
  concern), the templates rule "every font is in `allFonts`", and the bundled-fonts mentions.
- [ ] **Step 2: Run** `flutter test`, `flutter analyze --no-pub` and the Kotlin suite
  (`cd android; ./gradlew :app:testDebugUnitTest`) — Expected: all green, analyzer at 44 or fewer.
- [ ] **Step 3: Commit** — `docs: fonts from the server in the working notes`
