# Text to speech — the app Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From a selected text, Text to speech: pick a voice (samples free), Generate, and each text's voice lands as a green audio clip at the text's start — paid by characters through the silent price check, one undo step.

**Architecture:** A `SpeechService` on the existing `SlimshotApi` (one new signed-in byte download), a pure request planner (characters, limits, Apply to all), a `SpeechPipeline` + `SpeechRun` shaped exactly like captions' (key rules, shortfall, refund line, HeldWork), a sheet over `showEditorSheet`, and one notifier method that places every voice in a single undo step. The voice is an ordinary `AudioTrackModel` with two new fields, so preview, export and Auto captions (Source: Audio tracks) need no change.

**Tech Stack:** Flutter 3.47 / Dart 3.13, Riverpod `StateNotifier`, `package:http`, `just_audio`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-10-text-to-speech-design.md` ("The app"). Server contract: `slimshot_server/docs/app-api/text-to-speech.md` (built from the server branch `feat/text-to-speech`, commits 5612d19..22bae65).

**Branch:** `feat/text-to-speech`, cut from `feat/editor-polish` (it holds the spec and the most-used-first menus this extends); it merges after that branch.

## Global Constraints

- Shown only in a build with a server address: `isToolbarToolVisible('text_to_speech')` is `hasCaptionServer`.
- A character is `text.trim().runes.length`; a request's characters are the sum. Limits, the server's as shipped: 2,000 a text, 20,000 a request, 100 texts a request.
- Texts are sent trimmed; an empty text is skipped by Apply to all and leaves Generate off on its own. Apply to all voices plain texts only (no captions); a caption is voiced from its own menu.
- Every user-facing failure line goes through `speechErrorMessage` / `userMessageFor`; no server or engine words in a toast.
- Key rule, captions': a key is held until the server is known to hold a *failed* job for it, or answers `IDEMPOTENCY_KEY_REUSED` (then one fresh key); a resend under a held key is not priced again.
- Polling: the server's `pollAfterMs`, 3 dropped polls in a row ridden out, given up after 10 minutes.
- Sample player: `AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false)`, under `lib/features/video_editor/` (the playback-guard test reads every `AudioPlayer(` there).
- Files: `drafts/<draftId ?? 'unsaved'>/audio/voice_<textId>_<ms>.mp3` via `DraftFiles.audioDir`.
- `AudioTrackModel.isVoice` and `voiceForTextId` are written to the draft only when set: a draft without voices is byte-identical.
- Colours from `AppColors` (`voiceTrack` = `0xFF10B981`, Emerald 500); sheets through `showEditorSheet`, capped at `kEditorSheetPreviewFraction`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Stage files by name; never `android/app/google-services.json`, `assets/store/`, `macos/Flutter/GeneratedPluginRegistrant.swift`, `windows/flutter/*`. No push. No APK build (disk space) — `flutter test` and `flutter analyze --no-pub` are the gates.

## Review Focus

1. Generate answered by a lost response, then tapped again: no second charge — the run resends under its held key and is not priced again → test in A4 ("a retry after a lost answer reuses the key and skips the price").
2. The job completes but a download fails: Try again re-polls and downloads under the same key, never a new job → test in A4 ("a failed download keeps the key; the retry downloads the same job").
3. A text moved or deleted while its voice is being made: the voice lands where the text was when Generate was tapped, and a deleted text's voice is still placed → test in A3 ("places at the start captured with the request, even when the text has gone").
4. Voicing a text again replaces its earlier clip in the same undo step, and Undo brings the old clip back with its file still on disk → tests in A3 ("re-voicing replaces the old clip, one undo step") and A5 ("a replaced voice's file is kept until the editor closes").
5. Emoji and accents counted as the server does: `"héllo 👍🏽"` is 8 → test in A2.

## Where this plan departs from the spec (for the owner to check)

- **A replaced voice's file is deleted when the editor closes, not in the same step.** The spec
  says re-voicing a text loses the old clip *and file* at once; but Undo brings the old clip back,
  and its file must still be there to play. The clip goes at once; its file goes at close if no
  track uses it (`DraftFiles.sweepVoices`, `voice_*` files only).
- **Which clip is selected afterwards**: the voice of the text the sheet was opened from (its
  menu then offers Volume at once); after Apply to all from a caption, nothing.
- **Positions are taken when Generate is tapped**: a text moved or deleted while its voice is
  made does not move or drop the voice.

---

### A1: The server's speech API, from the app

**Files:**
- Modify: `lib/core/services/slimshot_api.dart` (signed-in bytes), `lib/features/account/services/account_service.dart` (quote by characters)
- Create: `lib/features/video_editor/services/speech_service.dart`
- Test: `test/core/services/slimshot_api_bytes_test.dart`, `test/features/account/account_service_speech_quote_test.dart`, `test/features/video_editor/services/speech_service_test.dart`

**Interfaces:**
- Produces:

```dart
// slimshot_api.dart
Future<Uint8List> sendForBytes(http.BaseRequest Function() build, {Duration timeout = defaultTimeout});
// account_service.dart
static const String textToSpeechFeature = 'text_to_speech';
Future<CreditQuote> quoteCharacters(int characters);
// speech_service.dart
class SpeechVoice { final String id; final String label; final String sampleUrl; }
class SpeechItem { final String id; final String text; }          // text already trimmed
class SpeechJobStart { final String jobId; final Duration pollAfter; final CreditCharge? charged; }
class SpokenItem { final String id; final double durationSeconds; }
class SpeechJobFailed extends SlimshotApiException { const SpeechJobFailed(super.code, [super.message]); }
const String kSpeechPollTimeout = 'SPEECH_POLL_TIMEOUT';
class SpeechService {
  SpeechService(SlimshotApi api, {Future<void> Function(Duration)? delay, DateTime Function()? clock});
  static const Duration pollLimit = Duration(minutes: 10);
  static const int maxPollFailures = 3;
  Future<List<SpeechVoice>> voices();                                    // GET /voices, public
  Future<SpeechJobStart> start({required String voiceId, required List<SpeechItem> items, required String idempotencyKey});
  Future<List<SpokenItem>> result(SpeechJobStart job, {required bool Function() isCancelled});
  Future<void> download(String jobId, String itemId, File into);         // written whole: .part, then renamed
}
```

- [ ] **Step 1: Write the failing tests.**
  - `sendForBytes`: `"returns the body's bytes on 200"`; `"refreshes once on UNAUTHENTICATED and sends again"`; `"a refusal is decoded like send's"` (404 envelope → `SlimshotApiException('NOT_FOUND')`); `"no session is SIGN_IN_REQUIRED"`. Use `MockClient` as the existing `slimshot_api` tests do.
  - `quoteCharacters`: posts `{feature: 'text_to_speech', characters: 342}` to `/credits/quote`.
  - `SpeechService`: `"lists the voices the server offers, skipping malformed ones"`; `"starts a job with the key and the trimmed items"` (body `{voiceId, items: [{id, text}]}`, header `Idempotency-Key`, `charged` read); `"polls until completed, at the server's pace, and returns each voice's length"`; `"a failed job throws SpeechJobFailed with the server's code"`; `"three dropped polls in a row end it; fewer are ridden out"`; `"gives up after 10 minutes"` (`kSpeechPollTimeout`); `"downloads into the file whole, leaving no .part"`; `"a cancelled poll throws SpeechCancelled"` (the run's sentinel, defined here).
- [ ] **Step 2:** Run `flutter test test/core/services/slimshot_api_bytes_test.dart test/features/account/account_service_speech_quote_test.dart test/features/video_editor/services/speech_service_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement. `sendForBytes` shares `send`'s refresh path (extract the authorised round trip into one private method returning the `http.Response`; `send` decodes it, `sendForBytes` returns `bodyBytes` for a 2xx). The poll loop is `CaptionService.result`'s, reading `items` (each `id`, `durationSeconds`).
- [ ] **Step 4:** Run the same tests plus `flutter test test/core/services test/features/account`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(tts): the server's voices, jobs and downloads, from the app`.

### A2: What a Generate sends — counting, limits, Apply to all

**Files:**
- Create: `lib/features/video_editor/logic/speech/speech_request.dart`
- Test: `test/features/video_editor/logic/speech/speech_request_test.dart`

**Interfaces:**
- Consumes: `TextOverlayModel` (`id`, `text`, `startTime`, `isCaption`).
- Produces:

```dart
const int kSpeechMaxItemCharacters = 2000;
const int kSpeechMaxRequestCharacters = 20000;
const int kSpeechMaxItems = 100;
int speechCharacters(String text);                          // text.trim().runes.length
class SpeechTarget { final String textId; final String text; final double startSeconds; }
sealed class SpeechPlan {}
class SpeechReady extends SpeechPlan { final List<SpeechTarget> targets; final int characters; }
class SpeechNothing extends SpeechPlan {}                   // nothing to voice: Generate off
class SpeechTooLong extends SpeechPlan { final String textId; }
class SpeechTooMuch extends SpeechPlan { final int fitting; }   // texts that fit, in order
SpeechPlan planSpeech({required List<TextOverlayModel> texts, required String selectedId, required bool applyToAll});
String speechPlanMessage(SpeechPlan plan);                  // the refusals' plain lines
```

- [ ] **Step 1: Write the failing tests:** `"counts code points of the trimmed text, as the server does"` (`speechCharacters(' héllo 👍🏽 ')` is 8); `"one text: the selected one, trimmed, at its start"`; `"an empty selected text is nothing to voice"`; `"Apply to all voices plain texts in timeline order, skipping empty ones and captions"`; `"Apply to all from a caption still skips captions"`; `"a text over 2,000 characters is refused by its id"` (message `"That text is too long for one voice. Split it into shorter texts."`); `"past 100 texts or 20,000 characters, says how many fit"` (message `"Too much for one go. Apply to all can voice $fitting of these texts at once."`).
- [ ] **Step 2:** Run `flutter test test/features/video_editor/logic/speech/speech_request_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement as pure functions; the start is captured here (`startTime`), which is what A3 places at.
- [ ] **Step 4:** Run it. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(tts): what a Generate sends — characters, limits, Apply to all`.

### A3: The voice on the timeline

**Files:**
- Modify: `lib/features/video_editor/models/audio_track_model.dart` (`isVoice`, `voiceForTextId`), `lib/core/theme/app_colors.dart` (`voiceTrack`), `lib/features/video_editor/widgets/timeline/audio_track_color.dart`, `lib/features/video_editor/widgets/timeline/lane_gutter_icons.dart` (`LaneGutterKind.voice`, `LucideIcons.mic`), `lib/features/video_editor/providers/video_editor_notifier.dart` (`placeVoices`)
- Test: `test/features/video_editor/models/audio_track_voice_test.dart`, `test/features/video_editor/providers/place_voices_test.dart`, `test/features/video_editor/widgets/timeline/lane_gutter_icons_test.dart` (extend)

**Interfaces:**
- Consumes: `SpeechTarget` (A2).
- Produces:

```dart
class VoiceClip { final String textId; final String filePath; final double durationSeconds; final double startSeconds; }
void placeVoices(List<VoiceClip> voices, {String? selectTextId});   // one undo step
```

- [ ] **Step 1: Write the failing tests:** `"a voice track round-trips its two fields, and a plain one writes neither"`; `"draws in the voice colour, with the mic in the gutter"`; `"places every voice at its captured start on the first free lane, as one undo step"`; `"places at the start captured with the request, even when the text has gone"`; `"re-voicing replaces the old clip, one undo step"` (old track with the same `voiceForTextId` removed; one `undo` brings it back); `"selects the voice of the text the sheet was opened from, else nothing"`.
- [ ] **Step 2:** Run the three test files. Expected: FAIL.
- [ ] **Step 3:** Implement. `placeVoices`: one `saveStateForUndo()`, drop tracks whose `voiceForTextId` is among the new ones, add each with `firstFreeLane` (`lane_layout.dart`), `_compactLanes()`, then the selection. Files are not deleted here (Undo must find them; A5 sweeps).
- [ ] **Step 4:** Run them, plus `flutter test test/features/video_editor`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(tts): a voice is a green audio clip at its text's start`.

### A4: The run — price, generate, download, refund

**Files:**
- Create: `lib/features/video_editor/services/speech_pipeline.dart`, `lib/features/video_editor/services/speech_run.dart`, `lib/features/video_editor/services/speech_errors.dart`
- Test: `test/features/video_editor/services/speech_pipeline_test.dart`, `test/features/video_editor/services/speech_run_test.dart`, `test/features/video_editor/services/speech_errors_test.dart`

**Interfaces:**
- Consumes: A1's service calls (as functions), A2's `SpeechReady`, A3's `VoiceClip`.
- Produces:

```dart
enum SpeechStage { speaking, downloading }
class SpeechPipeline {
  SpeechPipeline({required Future<CreditQuote> Function(int characters) quotePrice,
                  required Future<SpeechJobStart> Function(String voiceId, List<SpeechItem> items, String key) startJob,
                  required Future<List<SpokenItem>> Function(SpeechJobStart job, bool Function() isCancelled) awaitJob,
                  required Future<String> Function(String jobId, String itemId) download,   // returns the saved path
                  required void Function() onCancel, void Function(int balance)? onCharged, String Function()? newKey});
  Future<List<VoiceClip>> run(String voiceId, SpeechReady plan,
      {required void Function(SpeechStage stage) onProgress, Future<bool> Function(CreditQuote quote)? onShortfall});
  void cancel();
}
class SpeechRun extends ChangeNotifier { /* CaptionRun's members: stage, error, shortfall, voices, start, retry, earned, cancel */ }
String speechErrorMessage(Object error);
```

- [ ] **Step 1: Write the failing tests** (CaptionPipeline's and CaptionRun's tests are the model):
  - Pipeline: `"prices silently and generates when the balance covers it"`; `"a shortfall asks, and goes on only when told"`; `"a retry after a lost answer reuses the key and skips the price"`; `"a failed job takes a fresh key next time, and says the credits were returned when it was paid"`; `"IDEMPOTENCY_KEY_REUSED takes one fresh key"`; `"a failed download keeps the key; the retry downloads the same job"`; `"cancel stops at the next step and nothing is placed"`; `"downloads every item and returns its clip at the captured start"`.
  - Run: `"holds the app while running"`; `"earned credits that cover the price carry it on"`; `"retry runs the same pipeline"`.
  - Errors: each code to its line — `TTS_UNAVAILABLE` → "Text to speech is unavailable right now."; `VOICE_NOT_FOUND` → "That voice is no longer offered. Choose another."; `TEXT_TOO_LONG` → "That text is too long for one voice. Split it into shorter texts."; `NETWORK` → "No internet connection."; `kSpeechPollTimeout` → "Making the voice took too long. Try again."; a refunded paid failure → "Making the voice failed. Your credits were returned."; anything else → "Couldn't make the voice. Try again.".
- [ ] **Step 2:** Run the three files. Expected: FAIL.
- [ ] **Step 3:** Implement, mirroring `CaptionPipeline`/`CaptionRun` line for line where the rule is the same; the download step is new: keyed files are fetched in order, and any download failure rethrows with the key kept (the job is the server's for an hour).
- [ ] **Step 4:** Run them. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(tts): the voice run — priced, generated, downloaded, refunded`.

### A5: The sheet, the menu and the wiring

**Files:**
- Create: `lib/features/video_editor/widgets/panels/text_to_speech_sheet.dart`, `lib/features/video_editor/services/voice_sample_player.dart`
- Modify: `lib/screens/video_editor_screen.dart` (`_textOverlayMenu` second entry, the handler, `_newSpeechPipeline`, the close-time sweep), `lib/features/video_editor/logic/toolbar_visibility.dart`, `lib/core/services/draft_files.dart` (`sweepVoices`), `CLAUDE.md` (a section, written like its neighbours)
- Test: `test/features/video_editor/widgets/panels/text_to_speech_sheet_test.dart`, `test/core/services/draft_files_voices_test.dart`, `test/features/video_editor/logic/toolbar_visibility_test.dart` (extend), `test/features/video_editor/editor_menu_test.dart` (extend)

**Interfaces:**
- Consumes: A1–A4.
- Produces:

```dart
abstract class VoiceSamplePlayer { Future<void> play(String url); Future<void> stop(); Future<void> dispose(); ValueListenable<String?> get playing; }
class TextToSpeechSheet extends StatefulWidget {
  const TextToSpeechSheet({required this.loadVoices, required this.plan, required this.newRun,
                           required this.samples, required this.earnCredits, required this.onVoices});
}
static Future<void> DraftFiles.sweepVoices(String draftId, {required Set<String> keep, Directory? root});  // voice_* files only
```

- [ ] **Step 1: Write the failing tests:**
  - Sheet: `"lists the voices with a play button each, and plays one sample at a time"`; `"closing the sheet stops the sample"`; `"Generate is off for an empty text, and says why a too-long one cannot go"`; `"Apply to all texts voices every plain text"` (label exactly "Apply to all texts"); `"while running: a ring and Cancel; a failure's line and Try again"`; `"a shortfall shows 'Needs N credits · You have M' with the earn block"`; `"offline, the voices say No internet connection, with Retry"`; `"no voices offered says Text to speech is unavailable right now"`; `"a finished run hands its voices over and closes"`.
  - Menu and visibility: `"Text to speech is the text menu's second tool, with a handler"`; `"shown only with a server address"`.
  - Files: `"a replaced voice's file is kept until the editor closes"` — `sweepVoices` deletes `voice_*` files not in `keep`, and nothing else (`extract_*`, `voiceover_*` untouched).
- [ ] **Step 2:** Run the four test files. Expected: FAIL.
- [ ] **Step 3:** Implement. The handler: `requireAccount(context, ref, reason: 'Sign in to use Text to speech')`, then `showEditorSheet` with the sheet wired to a run on its own `SlimshotApi` (so Cancel aborts), `onCharged` → `accountProvider.notifier.applyBalance`, `onVoices` → `notifier.placeVoices(...)`. The voice list is fetched on every opening; the session's last list shows meanwhile (a `StateProvider` kept for the session), and the last voice chosen is pre-selected; the editor's `dispose` (after its final save) calls `DraftFiles.sweepVoices(draftId, keep: <every audio track's filePath>)`. The sample player is `AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false)` with `setUrl`; the sheet stops it in `dispose`.
- [ ] **Step 4:** Run `flutter test` (all) and `flutter analyze --no-pub`. Expected: PASS, no issues.
- [ ] **Step 5:** Commit: `feat(tts): Text to speech on a text's menu`.

**Device checks** (the spec's list): one text and Apply to all; each clip at its text's start, green, playing in the preview and in the exported file; samples playing with no charge; a shortfall carried on by an ad; a failure saying the credits were returned; offline; re-voicing replacing the old clip, and Undo bringing it back playable; the draft reopened with its voices; Auto captions (Source: Audio tracks) over a voice.
