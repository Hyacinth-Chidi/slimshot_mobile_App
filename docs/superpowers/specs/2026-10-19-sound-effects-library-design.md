# Sound effects library — design

**Date:** 2026-10-19. **Status:** design approved in chat; this spec awaits review.
**Server contract:** `slimshot_server/docs/app-catalog-api.md` (2026-10-18). Build against it
alone; anything it does not promise, do not rely on.

## Intent

A user editing a short video wants a whoosh, a click or a meme sound on the timeline in one
tap, from a library that grows without an app update. Success: open **Effects** on the audio
menu, pick a category, tap a sound's download icon, and it is on the timeline at the playhead,
playing in the preview and in the export. A sound once downloaded works offline, forever.

What the user said, and what is assumed:

- **Said:** categories are made in the dashboard and fetched, never hardcoded; the only fixed
  name is the `sound-effects` root. Row = cover, title (duration under it), a download icon.
  Download adds to the timeline in one tap. Everyone, no sign-in. SFX now, music later on the
  same code. Browsed data is kept for offline; downloaded sounds stay and play offline.
  Empty categories are toggled off in the dashboard, so no server change.
- **Assumed (approved in the design):** the sheet closes after a sound is added; no delete in
  this version; covers of sounds not downloaded are not kept offline.

## 1. Entry

- The audio menu's `effects` tool becomes **`sound_effects`**, label **Effects**, same icon.
  A new id because `effects` is the clip menu's tool and the screen currently tells the two
  apart by `currentMenuId` — a second meaning on one id is how the root menu's dead entries
  happened. `editor_menu_test.dart` is updated to pin the new id on `_audioMenu` and its
  handler.
- Visible only when the build carries a server address (`SlimshotApi.isConfigured`), through
  `isToolbarToolVisible` — a new `hasCatalogServer` case beside `auto_captions`'s.
- Opens `SoundEffectsSheet` through `showEditorSheet`, height **0.7** of the screen (a list to
  read down, like the Sounds library). No title (the echo rule).

## 2. Data

### 2.1 Client — `CatalogClient` (`features/sound_library/data/catalog_client.dart`)

Wraps the three public endpoints over `SlimshotApi`. `SlimshotApi._decode` only accepts a
`data` *map*; the categories answer is a list and the asset list carries `meta`. So
`SlimshotApi` gains **`sendPublicEnvelope`**: a public request returning the whole success
envelope (`data` as `Object?`, `meta` as a map), throwing `SlimshotApiException` on an error
envelope exactly as `_decode` does. Existing callers are untouched.

- `categories(root)` → `List<CatalogCategory>` (`id`, `slug`, `name`, `children`).
- `sounds(category, {cursor, limit = 30})` → `CatalogPage` (`items`, `nextCursor`).
- `download(id)` → `DownloadTicket` (`url`, `filename`, `format`, `byteSize`, `durationMs`).

Parsing is defensive (`(x as num?)?.toInt() ?? 0`; a row without an `id` or `title` is
dropped, never thrown on). `durationMs` 0 is kept; the row shows no duration.

`kSoundEffectsRoot = 'sound-effects'` is the only hardcoded name. The client takes the root as
a parameter so music is `'music'` later with nothing else changed.

### 2.2 Library — `SoundLibrary` (`features/sound_library/data/sound_library.dart`)

Downloaded sounds live in `<app documents>/sound_library/`:

- `<assetId>.<format>` — the file, written to `<assetId>.part` first and renamed on
  completion, so a killed download never leaves a file that looks whole.
- `<assetId>.cover` — the cover bytes, when the sound had one (fetched after the sound; a
  failed cover fetch is not a failed download — the row shows the default).
- `library.json` — one entry per sound: `id`, `title`, `durationMs`, `categorySlug`,
  `categoryName`, `fileName`, `coverFileName?`, `downloadedAt`. Written atomically (temp file,
  rename). Read defensively: an entry whose file is missing is dropped from the index on load.

Not under temp (Clear Cache sweeps temp), not under `drafts/<id>/` (a sound is shared between
drafts, and `DraftFiles.deleteAll` must not take it). Drafts store the absolute path in
`AudioTrackModel.filePath`, as they do for imported music. There is no delete in this version,
so a draft can never point at a library file that was removed by the app.

`download(item, ticket, onProgress)` streams the GET of `ticket.url` (no headers), reporting
`received / byteSize`, then fetches the cover. It never stores `ticket.url`. Two taps on one
sound share one in-flight download.

### 2.3 Browse cache — `CatalogCache`

The last category list and the **first page** of each category, as JSON in
`<app support>/catalog_cache.json` (cover URLs included — they are shown when online and
replaced by the default when an image fails). Shown at once when the sheet opens, then
replaced by the server's answer. Refetched on every open and on pull-to-refresh, as the
contract asks. Later pages are kept in memory for the session only.

## 3. The sheet — `SoundEffectsSheet`

```
┌─────────────────────────────────────┐
│ Downloaded │ Funny & Memes │ Impacts │…   ← pills, scroll sideways
├─────────────────────────────────────┤
│ [cover]  Whoosh Fast                ⬇ │
│          0.8s                         │
│ [cover]  Camera Shutter             ◔ │  ← downloading: progress ring
│ [cover]  Glass Break                + │  ← in the library
└─────────────────────────────────────┘
```

- **Pills.** **Downloaded** first — the library, newest first, works offline — then the
  root's children in the order returned. A pill's list includes its sub-categories (the server
  does this). The sheet opens on the first server pill when there is one, else Downloaded.
  Pill styling follows the transitions sheet's pills (`primaryStart` over `border` when
  chosen), but these scroll: the count is the dashboard's, not ours.
- **Row.** 48px square cover (rounded 8, `previewStage` behind it), or the bundled default
  cover (`assets/images/sound_cover_default.png`, a waveform glyph on the stage colour). Title
  one line, ellipsised, `textPrimary`; duration under it, `textSecondary`:
  `formatSoundDuration` — under 10s one decimal (`0.8s`, `4.0s`), else `m:ss` (`0:12`,
  `1:05`). The icon: `download` (not in the library), a progress ring (downloading), `plus`
  (in the library).
- **Tap the icon:** ⬇ downloads then adds; ＋ adds at once (§4).
- **Tap a downloaded row:** plays it from the file through one `just_audio` player owned by
  the sheet; tapping it again, or another row, stops it; closing the sheet disposes it. A row
  not in the library does nothing on tap (the server has no previews).
- **Paging.** 30 per page; the next page loads when the list is within a screen of its end;
  stops at `nextCursor == null`. Pull to refresh reloads pills and the current pill.

### 3.1 States

- **Loading** (nothing cached): three skeleton rows.
- **Offline / failed:** cached rows stay; a single line above the list, "You're offline",
  with **Retry**. With nothing cached, the line and Retry alone. Rows not in the library show
  dimmed and their ⬇ is disabled while offline.
- **Empty pill:** "No sounds here yet."
- **No `sound-effects` root (404):** only the Downloaded pill; no error.
- **Category vanished (404 on list):** reload the pills, select Downloaded if it is gone.
- **Rate limited (429):** wait `retryAfterSeconds` before the next automatic request; a
  manual Retry inside that window waits too. No loop.

## 4. Adding to the timeline

`VideoEditorNotifier.addLibrarySound(LibrarySound sound)`:

- An `AudioTrackModel` with the sound's file, `sourceDuration = durationMs / 1000`, full range,
  `timelineStart = currentPlaybackPosition`, through `addAudioTrack` — so one undo step, the
  first free lane (`_laneForNew`), and the new track selected.
- If the library entry's `durationMs` is 0 (the server did not know), the length is read from
  the file with `just_audio` before adding, as the Import path does; a file that will not open
  is a failed add.
- The sheet closes; the toolbar shows the audio track's menu as selecting an audio track does.

## 5. Errors the user sees

- A download that fails: `ToastUtils.show(context, "Couldn't download <title>", isError: true)`;
  the icon returns to ⬇. The `.part` file is deleted.
- 404 on download (sound removed): the row is dropped from the current list, and the same toast.
- 403 on download (reserved for gated sounds): toast "<title> isn't available".
- Everything else is the offline line in §3.1. No toast for browse failures.

## 6. Testing

- `CatalogClient`: parses each documented answer (fixtures copied from the contract), drops
  malformed rows, maps 404 / 422 / 429 to `SlimshotApiException` with the code and
  `retryAfterSeconds`; `sendPublicEnvelope` keeps `meta`.
- `SoundLibrary` over a temp directory: download writes `.part` then the file; a failed stream
  leaves no file and no index entry; the index survives a reload; a missing file is dropped on
  load; two concurrent downloads of one id make one request; the cover failing still adds.
- `CatalogCache`: round-trips; a corrupt file reads as empty.
- `formatSoundDuration`: 0.4 → `0.4s`, 9.94 → `9.9s`, 9.96 → `0:10` (a value that rounds to
  10.0 takes the long form, never `10.0s`), 65 → `1:05`, 0 → no duration shown.
- Sheet (widget, fakes for client and library): pills = Downloaded + server order; cached rows
  shown before the answer; offline line and Retry; ⬇ → ring → closes and calls add; ＋ adds
  without a request; tapping a non-library row does nothing; 404 root → Downloaded only;
  no overflow at 320px with text at 1.3×; `panel_theme_test` covers it (it lives under
  `widgets/panels/`).
- Notifier: `addLibrarySound` places at the playhead on a free lane, one undo step.
- Menu: `_audioMenu` declares `sound_effects`, the handler opens the sheet, visibility follows
  the server address.

No Kotlin changes: an added sound is an ordinary audio track, already played by the preview and
mixed by `AudioExportMixer`.

## Out of scope

Deleting library sounds; search; favourites; previews before download; music (same code, a
later root); sign-in or credits on downloads (the server's `entitlement.canDownload` is the
hook, and the app already treats 403 as "not available").
