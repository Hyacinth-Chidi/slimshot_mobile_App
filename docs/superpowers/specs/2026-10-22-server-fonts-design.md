# Fonts from SlimShot's server — app design

Date: 2026-10-22. Branch: `server-fonts`. Server contract:
`slimshot_server/docs/app-catalog-api.md` §8 — build against it alone; anything it does not
promise, don't rely on. The server side is built and needs no change.

## Why

The owner wants a font library like CapCut's: beautiful fonts they curate on their own server,
downloaded on demand, with only a few bundled in the app. Today the editor fetches 20 fonts from
Google at runtime through the `google_fonts` package (whose `pendingFonts()` already caused one
export bug, see `export_fonts.dart`) and bundles 9 more, 8 of which carry personal-use or
all-rights-reserved notices. The owner uploads only free (OFL) fonts and fonts they hold a
licence for.

This is the first of the text work, in the owner's order: **fonts, then text Effects (layered
looks), then Bubbles.**

## Goals

1. **The text editor's Font tab is one grid**, CapCut's "Trending fonts": System first, then the
   bundled fonts (Montserrat Bold, Bebas Neue, Poppins), then the server's `trending` category in
   the owner's order, then the server's `more-fonts` category in the owner's order. No tabs, no
   headings: one scroll with the owner's picks on top.
2. **A server tile is the server's preview image** — the font's name drawn in the font, white on
   transparent, shown on a dark tile. A download arrow until the font is on the phone, a progress
   ring while it downloads; **one tap downloads it and applies it**.
3. **Search** above the grid filters everything shown, on the phone.
4. **Offline**, the grid shows the last list the app saved, previews included; downloaded fonts
   work.
5. **A downloaded font is kept for good**, shared by every project. No delete.
6. **A fixed file the owner uploads** (a higher `version`) is downloaded quietly.
7. **`google_fonts` leaves the app entirely**: the editor's fonts and the app's own interface font
   (Plus Jakarta Sans), so the app never fetches from Google.
8. **Templates and caption styles keep working**, their fonts coming from the server.

## Non-goals

- **Old projects.** The owner will delete their test projects; nothing is migrated and the
  server's by-family lookup is not used for drafts. A text whose font is not on the phone draws
  in the System font. Nothing may crash on one.
- **Export waiting for fonts.** A font is applied only once it is on the phone, so in normal use
  export finds it ready (the owner's point). The export draws exactly what the canvas draws.
- More font categories, style filters, a Downloaded tab, a premium ("Pro") flag, deleting
  downloaded fonts, non-Latin or colour fonts (the server refuses those anyway).

## Anti-goals

- A tile, the canvas and the exported file disagreeing about which font a text wears.
- Any request to Google's servers.
- The catalogue bundled into the APK.
- A tap that downloads a font and then applies it over a font the user chose after tapping.

## Constraints

- **The server contract (§8):** `GET /fonts?category=<slug>` (one unpaged list per category),
  `GET /fonts/:id`, `GET /fonts/by-family/:familyName` (the published Regular face, exact
  spelling), `POST /assets/:id/download` → a `url` valid 10 minutes (never stored) with
  `version`, `format`, `byteSize`. A font item carries `id`, `displayName`, `familyName`,
  `styleName`, `version`, `format` (`ttf`/`otf`) and `preview {url, width, height}` (480×160).
  A missing category answers 404 — show what else there is. Rate limits: 120 reads and 30
  downloads a minute per IP; 429 carries `retryAfterSeconds`. The server keeps
  **(familyName, styleName) unique**, case-insensitively, and never deletes a published font.
- **The server address** comes from `SLIMSHOT_API_URL` through `SlimshotApi`, as for sounds.
  Without it the grid shows System and the bundled fonts only.
- **Drawing a text stays synchronous.** `getFontStyle` returns a `TextStyle` at once — the text
  geometry measures during layout (`text_overlay_geometry.dart`).
- **The draft format does not change.** `TextOverlayModel.fontFamily` stays one plain string.
- **Preview and export use the same fonts**: the canvas painter and `TextOverlayRasterizer` both
  draw through `getFontStyle`.
- The low-end target: tile previews decoded at tile size, nothing heavy at startup.

## Decided with the owner

- One grid, two categories `trending` then `more-fonts` (the owner creates `more-fonts`; until
  then the grid shows Trending only). A font sits in one category; one in neither is hidden but
  still downloadable by id.
- Bundled: **Montserrat Bold** (already bundled, the caption and new-text default), **Bebas
  Neue**, **Poppins**, plus the phone's **System** font.
- One tap downloads and applies. No Downloaded tab. No delete.
- Export does not wait. Old projects don't matter.
- Google Fonts goes completely.
- The 8 decorative bundled fonts (Ariana Violeta, Believe It, Chrusty Rock, Debrosee, New Retro
  Style 3d, Shade Blue, Short Baby, Super Kindly) **leave the app** — the owner was asked about
  their licences and did not object to removing them.

## The design — my calls

### A font's name in the app

**A server font is known by its family name, plus its style when that is not Regular**:
"Playfair Display" for Playfair Display Regular, "Lato Bold" for Lato Bold. That name is what a
text stores in `fontFamily` and what the font is registered under with the text engine.

- It is unique (the server enforces family + style) and stable (both are read from the file and
  never edited), so it is as good as the id for naming a face.
- Templates and caption styles already name their fonts this way ("Playfair Display",
  "Righteous"), so they keep working unchanged, and so does `TextLook.sameLookAs`.
- The draft format is untouched.

The phone's own records map a name to the server font's `id` and `version`; the id is what a
download asks for.

- **System** is the name `Roboto`, as today (the model's default and every emoji): on Android
  that resolves to the phone's own font.
- **Bundled** names: `Montserrat Bold`, `Bebas Neue`, `Poppins`.
- **A server font whose name is System's or a bundled font's is not shown** — each font appears
  once. (So the owner need not upload those three; if they do, nothing doubles.)

### On the phone

- Files in `<documents>/font_library/` as `<id>-v<version>.<format>`, written to a `.part` file
  and renamed when whole; a `library.json` (name, id, display name, family, style, version, file)
  written through a temp file. Not temp: Clear Cache and the OS sweep temp.
- The list (both categories, as last received) in `<app support>/font_catalog.json`, shown at
  once when the tab opens; refetched when the tab opens if the saved one is over 5 minutes old,
  and on pull-to-refresh. A 429 keeps the saved list and waits `retryAfterSeconds`.
- Preview images cached on disk in `<app support>/font_previews/`, keyed by URL (a changed
  preview gets a new URL), downloaded when the list arrives, so an offline grid still shows them.
  Decoded at tile width.

### Registering with the text engine

Flutter's `FontLoader(name)` reads a file's bytes and registers it. A registered font cannot be
replaced in the same session.

- A font is registered **right after it downloads**, **when a project opens** (the fonts its
  texts use, before the canvas draws text — reading a few local files is milliseconds), and
  **when a template or caption-style grid opens** (the fonts its tiles use that are on the phone).
- `getFontStyle(name)` returns `TextStyle(fontFamily: name)` at once. A name not registered yet
  draws in the System font; **anything drawing text redraws when a font it uses finishes
  registering** (one notifier the painters and tiles listen to).
- **A higher `version`** in the list for a font on the phone is downloaded in the background and
  replaces the old file, used from the next app start. Counted as a download by the server, which
  the contract accepts.

### The Font tab

- Three tiles a row, dark tiles shaped like the 3:1 preview; the selected font's tile wears the
  editor's selected style (`primaryStart` border). System is a "SYSTEM" tile; bundled tiles draw
  their own name live in their own font, white, to match the previews.
- A tap on a font on the phone applies it. A tap on one that isn't downloads it with a ring and
  applies it when it lands — **unless the user chose another font meanwhile: the last tap
  wins**, and a superseded download finishes quietly without applying.
- A failed download keeps the arrow and says "No internet connection" (no connection) or
  "Couldn't download this font" (anything else) — the sound library's lines.
- Search matches display names (and the bundled names), ignoring case, spaces, dashes and
  underscores, over everything in the grid.
- The grid is exactly System, the bundled fonts and the two lists. A font listed twice shows once
  (first place wins). A font the owner later takes out of both categories leaves the grid even
  if it is on the phone; texts already wearing it keep it. A listed font without a preview (the
  contract says this does not happen) shows its display name instead.

### Templates and caption styles

- A template or caption style that names a server font draws its tile in that font once it is on
  the phone. **Opening the grid quietly downloads the server fonts its tiles use** — a few hundred
  KB each, counted as downloads — so the tiles show their real look.
- A name is resolved to a server font from the saved list (family + style), else by
  `GET /fonts/by-family/:familyName` — every template font is a Regular face.
- Picking one applies at once; if its font is not on the phone yet it downloads and the text
  switches when it lands. Until then the canvas and an export both draw System, which agree.
- The server fonts the built-in templates and caption styles use, which the owner should upload
  as Regular faces: **Abril Fatface, Inter, Montserrat, Nunito, Oswald, Permanent Marker,
  Playfair Display, Press Start 2P, Righteous, Sacramento.**

### A project's fonts

When a project opens, each text font that is neither System, bundled nor on the phone is fetched
in the background (resolved like a template's). It draws in System until it lands; offline, one
toast says a font couldn't be downloaded, and the next opening tries again.

### Export

No waiting. The export registers the project's fonts that are on the phone (local, fast) before
it rasterises — so a text whose font is on the phone can never export in the fallback — and draws
what the canvas draws. `export_fonts.dart` (`awaitExportFonts`, `exportFontWarning`,
`kExportFontWait`) and `GoogleFonts.pendingFonts` go.

### The app's interface font

Plus Jakarta Sans is bundled as static OFL files in the weights the screens use — **400, 500,
600, 700, 800** (400 and 700 are bundled today). `app_theme.dart` and every
`GoogleFonts.plusJakartaSans(...)` call (gradient button, home, history, main shell, onboarding,
update, workspace) become plain `TextStyle(fontFamily: 'Plus Jakarta Sans', ...)`.
`GoogleFonts.config` goes from `main.dart`, and `google_fonts` from `pubspec.yaml`.

### Clean-up and licences

- Deleted from `assets/fonts`: the 8 decorative fonts, the unused `AlteixsansRegulardemo` file,
  and `font.zip` / `PlusJakartaSans.zip`, which are saved HTML pages, not archives.
- `googleFontsList`, `customBundledFonts`, `allFonts` and `isCustomFont` are replaced by the
  bundled list plus the server list. Tests that pin template and caption fonts check them
  against the bundled names plus the server font list above.
- The SIL Open Font License notices of the bundled fonts (Montserrat, Bebas Neue, Poppins, Plus
  Jakarta Sans) are registered beside the GL Transitions notice
  (`core/legal/third_party_licences.dart`), as the OFL asks of a redistributed font.
- A guard test fails on any `google_fonts` import under `lib/`, like the stray-sheet guard.

## Left to the builder

The widget structure, the class and file names, the providers, the exact tile dimensions, and
how the network layer is faked in tests (`FontLoader` works in `flutter_test` with a bundled
font; `kTestFontFamily` stays for text measured in tests).

## Verification

**Tests** pin: the name rule and its de-duplication; the grid's order; arrow, ring and selected
states; last tap wins; the library surviving a restart and refusing a half-written file; the
version rule; the list cache and the 429 wait; search; template font resolution; registration
redrawing a text; no `google_fonts` under `lib/`.

**On the device**: the grid shows the owner's order with real previews; a tap downloads and
applies; the export wears the font; offline the grid and downloaded fonts work; a template with a
server font shows its real look after the grid opens; a caption style using Righteous; the
interface still reads in Plus Jakarta Sans at every weight; the app sends nothing to Google.

## The owner's to-do on the server

- Create the `more-fonts` font category.
- Upload, as Regular faces, the template and caption fonts listed above.
