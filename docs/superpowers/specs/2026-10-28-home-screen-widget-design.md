# Home screen widget and icon menu — design

**Status:** agreed in chat with the owner, 2026-10-28, from mockups (the widget with an edit, the
widget before any edit, the long-press menu). Android only — the app is Android-first.

## Why

The owner wants SlimShot on the phone's home screen. An unfinished edit is the strongest reason to
come back to an editor, so the widget is that edit, one tap from continuing. The two jobs people
start most — a new video, a compression — go on the icon's long-press menu, where they cost
nothing to keep.

## What the user sees

### 1. The "Continue editing" widget

One widget, one size: **4 × 2** cells, in the app's dark look (near-black card, 24 dp corners, a
faint light edge, purple accents).

**With an edit** — the most recently saved draft:

- **Its cover** on the left, rounded: the draft's `thumbnailPath` (the cover the user chose, else
  the first frame the editor saved). A **length chip** ("0:42") sits on the cover when the length
  is known.
- **Kicker** "CONTINUE EDITING" (lilac, small capitals).
- **Main line** — when it was edited: "Edited today", "Edited yesterday", else "Edited 12 Oct"
  (the phone's locale for the date). *The mockup showed a name ("Dance reel"); drafts have no
  names (Workspace shows only the cover and "2 hours ago"), so the main line is the edit time —
  my call.*
- **Sub line** — the clip count: "4 clips" ("1 clip").
- A purple pill button **Continue** — **text only, no icon** (the owner's call).
- **A tap anywhere on the card**, the button included, opens that draft in the editor.

**Before any edit** (no drafts, or the last one deleted): a placeholder tile (dashed lilac frame
with a plus) where the cover goes, kicker "SLIMSHOT", main line "No edits yet", sub line "Your
last edit will wait here", and the button **Start editing** — text only. A tap does what Home's
New video card does.

**In the widget picker:** listed under SlimShot as "Continue editing", with a preview of the
card holding a sample edit.

### 2. The icon's long-press menu (app shortcuts)

- **New video** — does what Home's New video card does: the gallery, then the editor.
- **Compress video** — does what Home's Compress video card does: the videos, then the compress
  screen.

**Removed at the owner's call:** the widget's New video and Status-ready buttons, the small 2 × 2
widget, and the menu's Compress photo and Privacy strip.

## How it behaves

- **Which edit:** the draft with the latest `updatedAt` — the first of `DraftService.getDrafts()`
  — whatever screen saved it.
- **It follows every change.** `DraftService.saveDraft`, `deleteDraft` and `clearAll` already
  announce themselves through `DraftRefreshNotifier`; the app pushes the widget's data on each,
  and once at every launch (a widget added before the app's first run, drafts saved by an older
  build).
- **Taps land on Home and run Home's own handlers** — `_handleEditVideo`, `_handleCompressVideo`,
  and opening a draft the way Home's recent drafts do — so the picker, the gallery-permission
  dialog and the error toasts are exactly Home's. There is no second implementation of either
  job.
- **The app elsewhere** (a compress screen, Settings, the editor on another draft): a tap goes
  Home first, the way Back would — the editor saves its draft on the way out, as it always does.
  **Continue for the edit already open in the editor just brings the app forward.**
- **Work in progress is never thrown away by a tap.** While an export or a compression is
  running, a tap only brings the app forward; going Home would leave the screen running it.
  *My call.*
- **Before onboarding has been seen** (a widget added before the first launch): onboarding shows
  as usual, and the tap's job runs when Home appears. *My call.*
- **Continue on a draft that no longer exists** (only if a widget update was missed): Home, with
  the toast "That edit was deleted.", and the widget redraws with the draft that is now latest.
  *My call.*
- **Dates go stale, so they are worked out when the widget draws**, on the phone, from the saved
  time, and the widget redraws **every hour** — "today" turns to "yesterday" within an hour of
  midnight, at no measurable cost (the platform's floor is 30 minutes). *My call; "2 hours ago"
  is not offered because it cannot stay true without frequent wake-ups.*
- **The length is the edit's own**: `projectEndSeconds`, computed exactly as
  `totalEditedDurationProvider` computes the editor's duration — saved with the draft as a new
  optional field (`editedSeconds`, written only when known, so every existing draft loads
  unchanged). **`DraftProject.durationSeconds` is the first imported
  file's length, not the edit's, and must not be shown.** A draft saved before this has no
  length chip until it is next saved.
- **A cover file that is gone or unreadable** shows the placeholder tile without the plus.

## How it's built (decided)

**Native Android, no new packages.**

- **The widget** is an `AppWidgetProvider` with a RemoteViews XML layout — not Jetpack Glance,
  which would bring Compose into a Gradle build that already opts out of Flutter's newer Kotlin
  setup (`android.builtInKotlin=false`). The card's background is a rounded drawable; on Android
  12+ the root carries `@android:id/background` so launchers round it to their own radius.
- **The cover is prepared once, when the edit changes**: decoded off the main thread from the
  file, centre-cropped to 9:16, scaled to at most ~300 px tall, its corners rounded in code, and
  kept as a small picture beside the widget's data — RemoteViews cannot clip an image on older
  Android, and a large bitmap breaks the widget's memory limit. The hourly redraw only reads that
  copy, so it never decodes the full cover and works with the app closed.
- **Text is in the phone's own font** (`sans-serif`, `sans-serif-medium`): widgets render inside
  the launcher, and Plus Jakarta Sans lives in Flutter's assets, not Android resources. *My call.*
- **The menu** is static shortcuts (`res/xml/shortcuts.xml`, Android 7.1+). On Android 7.0 —
  `minSdk` is 24 — the menu does not exist and nothing breaks. Its icons are as in the mockup:
  a lilac glyph (a plus, inward arrows) on a deep-purple circle.

**One channel, `slimshot_ai/home_widget`:**

- **Dart → Kotlin `setLastEdit`** with `{draftId, coverPath, editedAtMillis, clips,
  lengthSeconds?}`, or `null` for none. Kotlin keeps it in the widget's own `SharedPreferences`
  file (the widget draws without the app running) and asks `AppWidgetManager` to redraw.
- **Kotlin → Dart, launch actions.** The widget's taps and the shortcuts start `MainActivity`
  (already `singleTop`) with an action: `com.techfamz.slimshotai.action.CONTINUE` (+ the draft
  id), `.NEW_VIDEO`, `.COMPRESS_VIDEO`. The activity keeps the action it was started with for
  Dart to take (`takeLaunchAction`) and sends later ones (`onNewIntent`) as calls. **An action is
  taken once** — cleared when read, so an activity recreated on rotation does not run it again.
  The share intents (`receive_sharing_intent`) are untouched.

**Dart:**

- **`HomeWidgetSync`** — the latest draft to the payload (draft id, cover path, edit time, clip
  count, length); runs at launch and on every `DraftRefreshNotifier` change. Pure enough to test
  without a device.
- **`LaunchActions`** — a small holder of the pending action. The app root takes actions from the
  channel and sends the router Home; Home runs the matching handler and clears it. An action
  waits while Home is not up (the splash, onboarding).
- **`saveDraft`** writes `editedSeconds` from `projectEndSeconds`.

## Tests

- **Dart:** the payload (latest draft chosen, clip count, length present only when saved, `null`
  when no drafts); `editedSeconds` round-trips and an old draft without it loads unchanged; launch
  routing — each action runs the right Home handler, waits until Home is up, Continue on the open
  edit does nothing, a missing draft toasts, an action during an export or a compression does
  nothing.
- **Kotlin (JVM):** the date label (today, yesterday, a date, across midnight and time zones),
  the length text ("0:42", "12:05", "1:02:03"), the crop-and-scale arithmetic.
- **On a device:** the widget's look (with and without an edit, large text, Android 12+ corners,
  the picker preview), Continue opening the right edit, the card following an edit and a delete,
  both shortcuts, a tap from a cold start and from the editor.

## Not in this

iOS widgets; other sizes or a resizable layout; several drafts in one widget; configuration;
draft names; dynamic shortcuts; the removed buttons and menu items above.

## Must not happen

- A widget that wakes the phone more than hourly, or redraws on anything but a draft change and
  the hourly date check.
- Continue opening a different edit from the one shown, or a stale cover after a new one was
  chosen.
- A New video or Compress video that behaves differently from Home's.
- A tap that abandons an export or a compression in progress.

## Left to the builder

The exact dp sizes and spacing inside the card (within the mockup's look), the draft-preview
picture for older phones' widget picker, and how `LaunchActions` reaches Home (a provider, a
notifier) — as long as an action is run once and only by Home.
