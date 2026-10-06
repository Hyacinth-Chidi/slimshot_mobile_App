# Credits Stage 2 — the Price Step — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto captions asks the server for its price after the audio is rendered, shows "6 credits · You have 94" with Generate before anything is uploaded, says "Needs 6 credits · You have 2" when short, updates the home pill from the upload's charge, and says "Your credits were returned" when a paid job fails.

**Architecture:** The caption pipeline gains a `pricing` stage between render and upload: it quotes the rendered WAV's duration through a new `AccountService.quote`, then asks the progress sheet (a `confirmPrice` callback passed to `run`) whether to go ahead. A free quote skips the question; no confirmer, a decline, or the sheet closing all mean no upload. `CaptionService` reads the upload's `charged` block, the pipeline hands its balance to a new `AccountNotifier.applyBalance`, and a job the server reports `failed` after a charge surfaces as a refund line.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, Riverpod `StateNotifier`, `package:http` + `MockClient`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-05-app-accounts-credits-design.md` (§3 A, §4.4, §5 `CaptionPipeline`, §6, §7, §8 stage 2). Server contract: `slimshot_server/docs/app-credits-api.md` §11 (quote), §12 (captions, `charged`, refunds, keys), §14 (errors).

## Global Constraints

- Work on the branch `feat/credits-stage2` (cut from `main`, carrying this plan). Never push or merge; the user device-tests and pushes.
- Test-first for every behaviour; watch each test fail before writing the code.
- `flutter analyze --no-pub` must stay at exactly **48** issues. Run the full `flutter test` at the end of every task.
- **Never compute a price in the app.** Always `POST /credits/quote` with the rendered WAV's own duration (contract §11).
- Copy, exactly: `"6 credits · You have 94"`, `"Needs 6 credits · You have 2"`, singular `"1 credit"`, `"Captioning failed. Your credits were returned."`, stage label `"Checking price"`. No titles, no echo of the tool's name, one line per message.
- Colours only from `AppColors`; sheets keep the existing `CaptionProgressSheet` frame and `SheetActionButton`s.
- **No ads in this stage.** The not-enough state shows the line and Close only (stage 3 adds Watch an ad and Invite).
- A free quote (`credits: 0`) skips the price step entirely (spec §4.4).
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **The sheet dismissed at the price step** (tap outside, Back, Cancel) must upload nothing and charge nothing → Task 5, "closing at the price step uploads nothing".
2. **Credits spent between the quote and the upload**: the server answers `402 INSUFFICIENT_CREDITS` with `details.required`/`details.balance`; the user must see "Needs N credits · You have M", not the generic transcribe line → Task 4, "a refusal for credits says how many".
3. **A `/me` that was already on its way when the charge landed** must not put the old balance back on the pill → Task 2, "an older /me does not undo a charge".
4. **Declining after an upload whose response was lost** must not keep that upload's key (the next run is a new upload) → Task 4, "declining forgets a lost upload's key".
5. **Only a paid job's failure promises a refund**; a free job's failure keeps its own line → Task 4, "a failed paid job says the credits came back; a free one does not".

---

## File Structure

| File | Responsibility |
| :--- | :--- |
| `lib/features/account/models/account_models.dart` (modify) | `CreditQuote` (credits, balance, enough); `AccountUser.withBalance`. |
| `lib/features/account/services/account_service.dart` (modify) | `quote(feature, durationSeconds)`; `autoCaptionsFeature` constant. |
| `lib/features/account/logic/account_copy.dart` (modify) | `creditCount`, `priceLine`, `shortfallLine` — the one wording for prices. |
| `lib/features/account/providers/account_providers.dart` (modify) | `AccountNotifier.applyBalance(int)`, ticketed like every other profile answer. |
| `lib/features/video_editor/services/caption_service.dart` (modify) | `CreditCharge`; `CaptionJobStart.charged`; a `failed` job throws `CaptionJobFailed`. |
| `lib/features/video_editor/services/caption_errors.dart` (modify) | `CaptionJobFailed`; `CaptionFailure.refunded`; the refund and shortfall lines. |
| `lib/features/video_editor/services/caption_pipeline.dart` (modify) | `CaptionStage.pricing`; `quotePrice`, `onCharged`; `run(confirmPrice:)`; the key-reuse retry; refund mapping. |
| `lib/features/video_editor/widgets/panels/caption_progress_sheet.dart` (modify) | The price step: enough (Cancel / Generate) and short (Close). |
| `lib/screens/video_editor_screen.dart` (modify) | Wires `quotePrice` and `onCharged`. |
| `CLAUDE.md` (modify) | Stage 2 section; drop "until stage 2 there is no confirm". |

---

### Task 1: The quote — model, request and wording

**Files:**
- Modify: `lib/features/account/models/account_models.dart`
- Modify: `lib/features/account/services/account_service.dart`
- Modify: `lib/features/account/logic/account_copy.dart`
- Test: `test/features/account/services/account_service_test.dart`
- Test: `test/features/account/logic/account_copy_test.dart`

**Interfaces:**
- Consumes: `SlimshotApi.send`, `SlimshotApi.jsonRequest` (stage 1).
- Produces:
  - `class CreditQuote { const CreditQuote({required int credits, required int balance, required bool enough}); factory CreditQuote.fromJson(Map<String, dynamic>); final int credits; final int balance; final bool enough; bool get isFree; }`
  - `AccountUser AccountUser.withBalance(int balance)`
  - `static const String AccountService.autoCaptionsFeature = 'auto_captions'`
  - `Future<CreditQuote> AccountService.quote(String feature, double durationSeconds)`
  - `String creditCount(int n)`, `String priceLine(int credits, int balance)`, `String shortfallLine(int needed, int balance)`

- [ ] **Step 0: Be on the branch** — `feat/credits-stage2` was cut from `main` with this plan.

```bash
git checkout feat/credits-stage2
```

- [ ] **Step 1: Write the failing service tests** — append inside `main()` of `test/features/account/services/account_service_test.dart`:

```dart
  test('a quote sends the feature and the audio length, signed in', () async {
    server.on(
      'POST',
      '/credits/quote',
      (_) => envelope({
        'credits': 6,
        'balance': 94,
        'enough': true,
        'pricingVersion': 3,
      }),
    );
    final quote = await service(signedIn: true)
        .quote(AccountService.autoCaptionsFeature, 125.4);

    expect(server.lastBody('POST', '/credits/quote'), {
      'feature': 'auto_captions',
      'durationSeconds': 125.4,
    });
    expect(
      server.to('POST', '/credits/quote').last.headers['Authorization'],
      'Bearer a1',
    );
    expect((quote.credits, quote.balance, quote.enough), (6, 94, true));
    expect(quote.isFree, isFalse);
  });

  test('a free quote is free, and a short one is not enough', () {
    expect(
      CreditQuote.fromJson({'credits': 0, 'balance': 3, 'enough': true}).isFree,
      isTrue,
    );
    final short =
        CreditQuote.fromJson({'credits': 6, 'balance': 2, 'enough': false});
    expect((short.enough, short.isFree), (false, false));
  });

  test("a quote missing 'enough' works it out rather than guessing yes", () {
    expect(CreditQuote.fromJson({'credits': 6, 'balance': 2}).enough, isFalse);
    expect(CreditQuote.fromJson({'credits': 6, 'balance': 6}).enough, isTrue);
  });
```

- [ ] **Step 2: Write the failing wording tests** — append inside `main()` of `test/features/account/logic/account_copy_test.dart`:

```dart
  test('prices read as the spec writes them, singular included', () {
    expect(priceLine(6, 94), '6 credits · You have 94');
    expect(priceLine(1, 94), '1 credit · You have 94');
    expect(shortfallLine(6, 2), 'Needs 6 credits · You have 2');
    expect(shortfallLine(1, 0), 'Needs 1 credit · You have 0');
  });
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/account/services/account_service_test.dart test/features/account/logic/account_copy_test.dart`
Expected: FAIL to compile — `CreditQuote`, `quote`, `autoCaptionsFeature`, `priceLine`, `shortfallLine` are not defined.

- [ ] **Step 4: Add the model** — in `account_models.dart`, after `AccountUser`'s `toJson()` add to the class:

```dart
  /// The same user with a balance a spend answered with.
  AccountUser withBalance(int balance) => AccountUser(
        id: id,
        email: email,
        username: username,
        referralCode: referralCode,
        creditBalance: balance,
        suspended: suspended,
        needsClaim: needsClaim,
      );
```

and at the end of the file:

```dart
/// What a run will cost, asked of the server before anything is uploaded.
/// The app never works a price out itself: the owner can change the pricing
/// at any time (contract §11).
class CreditQuote {
  const CreditQuote({
    required this.credits,
    required this.balance,
    required this.enough,
  });

  factory CreditQuote.fromJson(Map<String, dynamic> json) {
    final credits = (json['credits'] as num?)?.toInt() ?? 0;
    final balance = (json['balance'] as num?)?.toInt() ?? 0;
    return CreditQuote(
      credits: credits,
      balance: balance,
      // Worked out, never assumed: a missing flag must not read as yes.
      enough: json['enough'] as bool? ?? balance >= credits,
    );
  }

  final int credits;
  final int balance;
  final bool enough;

  /// Nothing to confirm: the price step is skipped.
  bool get isFree => credits <= 0;
}
```

- [ ] **Step 5: Add the request** — in `account_service.dart`, inside `AccountService` after `deleteAccount`:

```dart
  /// The feature name Auto captions is priced under.
  static const String autoCaptionsFeature = 'auto_captions';

  /// What [feature] will cost for [durationSeconds] of audio — the length of
  /// the exact file about to be uploaded, which the server measures again.
  Future<CreditQuote> quote(String feature, double durationSeconds) async =>
      CreditQuote.fromJson(
        await _api.send(
          () => _api.jsonRequest('POST', '/credits/quote', {
            'feature': feature,
            'durationSeconds': durationSeconds,
          }),
        ),
      );
```

- [ ] **Step 6: Add the wording** — at the end of `account_copy.dart`:

```dart
/// "1 credit", "6 credits".
String creditCount(int n) => n == 1 ? '1 credit' : '$n credits';

/// The price step when the balance covers it.
String priceLine(int credits, int balance) =>
    '${creditCount(credits)} · You have $balance';

/// The price step, or a refusal, when it does not.
String shortfallLine(int needed, int balance) =>
    'Needs ${creditCount(needed)} · You have $balance';
```

- [ ] **Step 7: Run them to see them pass**

Run: `flutter test test/features/account/services/account_service_test.dart test/features/account/logic/account_copy_test.dart`
Expected: PASS.

- [ ] **Step 8: Full suite and analyzer**

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all pass; `48 issues found`.

- [ ] **Step 9: Commit**

```bash
git add lib/features/account test/features/account
git commit -m "feat(credits): ask the server what Auto captions will cost

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The balance a charge answered with reaches the pill at once

**Files:**
- Modify: `lib/features/account/providers/account_providers.dart`
- Test: `test/features/account/providers/account_notifier_test.dart`

**Interfaces:**
- Consumes: `AccountUser.withBalance` (Task 1); the notifier's private `_nextTicket` / `_adopt` (stage 1).
- Produces: `Future<void> AccountNotifier.applyBalance(int balance)`.

- [ ] **Step 1: Write the failing tests** — append inside `main()` of `account_notifier_test.dart`:

```dart
  test('a charged balance shows at once', () async {
    server.on('GET', '/me', (_) => envelope(userJson(balance: 94)));
    final c = containerWith(session: signedInSession(profile: userJson(balance: 94)));
    c.read(accountProvider);
    await pumpEventQueue();

    await c.read(accountProvider.notifier).applyBalance(88);
    expect(c.read(accountProvider).user!.creditBalance, 88);
  });

  test('an older /me does not undo a charge', () async {
    final answer = Completer<http.Response>();
    server.on('GET', '/me', (_) => answer.future);
    final c = containerWith(session: signedInSession(profile: userJson(balance: 94)));
    c.read(accountProvider); // restore: its /me is now on its way
    await pumpEventQueue();

    await c.read(accountProvider.notifier).applyBalance(88);
    answer.complete(envelope(userJson(balance: 94))); // read before the charge
    await pumpEventQueue();
    expect(c.read(accountProvider).user!.creditBalance, 88);
  });

  test('signed out, a balance changes nothing', () async {
    final c = containerWith();
    await c.read(accountProvider.notifier).applyBalance(88);
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/account/providers/account_notifier_test.dart`
Expected: FAIL to compile — `applyBalance` is not defined.

- [ ] **Step 3: Implement** — in `AccountNotifier`, after `refresh()`:

```dart
  /// The balance a spend answered with (a caption upload's `charged`), shown
  /// at once. It takes a ticket like any profile answer, so a `/me` that was
  /// already on its way — read before the charge — cannot put the old
  /// balance back.
  Future<void> applyBalance(int balance) async {
    final user = state.user;
    if (user == null) return;
    await _adopt(user.withBalance(balance), _nextTicket());
  }
```

- [ ] **Step 4: Run them to see them pass**

Run: `flutter test test/features/account/providers/account_notifier_test.dart`
Expected: PASS.

- [ ] **Step 5: Full suite and analyzer**

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all pass; `48 issues found`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/account/providers test/features/account/providers
git commit -m "feat(credits): a charge's balance reaches the pill at once

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The upload reports its charge; a failed job is told apart

**Files:**
- Modify: `lib/features/video_editor/services/caption_service.dart`
- Modify: `lib/features/video_editor/services/caption_errors.dart`
- Test: `test/features/video_editor/services/caption_service_test.dart`

**Interfaces:**
- Consumes: `SlimshotApiException` (stage 1).
- Produces:
  - `class CreditCharge { const CreditCharge({required int credits, required int balance}); final int credits; final int balance; }`
  - `CaptionJobStart({required String jobId, required Duration pollAfter, CreditCharge? charged})` with `final CreditCharge? charged`
  - `class CaptionJobFailed extends SlimshotApiException { const CaptionJobFailed(String code, [String message = '']); }`

- [ ] **Step 1: Write the failing tests** — append inside `main()` of `caption_service_test.dart`. Use the file's existing `serviceWith(MockClient …)` helper and its `audio` file; build each `MockClient` the way the file's existing upload tests do:

```dart
  test('the upload reports what it charged', () async {
    final service = serviceWith(MockClient((request) async => envelope({
          'jobId': 'cap_1',
          'status': 'queued',
          'pollAfterMs': 1500,
          'charged': {'credits': 6, 'balance': 88},
        }, 202)));
    final job = await service.start(
      audioPath: audio.path,
      idempotencyKey: 'k1',
    );
    expect((job.charged!.credits, job.charged!.balance), (6, 88));
  });

  test('a free job, or a resend, reports no charge', () async {
    final service = serviceWith(MockClient((request) async => envelope({
          'jobId': 'cap_1',
          'status': 'queued',
          'pollAfterMs': 1500,
        }, 202)));
    final job = await service.start(
      audioPath: audio.path,
      idempotencyKey: 'k1',
    );
    expect(job.charged, isNull);
  });

  test('a job the server failed is told apart from a request that failed',
      () async {
    final service = serviceWith(
      MockClient((request) async => envelope({
            'jobId': 'cap_1',
            'status': 'failed',
            'error': {'code': 'PROVIDER_FAILED', 'message': 'm'},
          })),
      delay: (_) async {},
    );
    await expectLater(
      service.result(job, isCancelled: () => false),
      throwsA(isA<CaptionJobFailed>()
          .having((e) => e.code, 'code', 'PROVIDER_FAILED')),
    );
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/video_editor/services/caption_service_test.dart`
Expected: FAIL to compile — `charged` and `CaptionJobFailed` are not defined.

- [ ] **Step 3: Add `CaptionJobFailed`** — in `caption_errors.dart`, after `CaptionFailure`:

```dart
/// The server finished the job as `failed`. Told apart from a request that
/// failed because a paid job's credits are already back by then (contract
/// §12), which the user is told.
class CaptionJobFailed extends SlimshotApiException {
  const CaptionJobFailed(super.code, [super.message]);
}
```

- [ ] **Step 4: Carry the charge** — in `caption_service.dart`, replace `CaptionJobStart` with:

```dart
/// What an upload took, and the balance after it.
class CreditCharge {
  const CreditCharge({required this.credits, required this.balance});

  final int credits;
  final int balance;
}

/// A caption job the server has accepted.
class CaptionJobStart {
  const CaptionJobStart({
    required this.jobId,
    required this.pollAfter,
    this.charged,
  });

  final String jobId;
  final Duration pollAfter;

  /// Absent for a free job and for a resend of an upload the server still
  /// has: nothing was taken.
  final CreditCharge? charged;
}
```

In `start`, replace the final `return CaptionJobStart(jobId: jobId, pollAfter: _pollAfter(data));` with:

```dart
    return CaptionJobStart(
      jobId: jobId,
      pollAfter: _pollAfter(data),
      charged: _charged(data['charged']),
    );
```

and add beside `_pollAfter`:

```dart
  static CreditCharge? _charged(Object? value) {
    if (value is! Map) return null;
    final credits = value['credits'];
    final balance = value['balance'];
    if (credits is! num || balance is! num) return null;
    return CreditCharge(credits: credits.toInt(), balance: balance.toInt());
  }
```

In `result`, in `case 'failed':`, replace `throw SlimshotApiException(` with `throw CaptionJobFailed(` (same two arguments).

- [ ] **Step 5: Run them to see them pass**

Run: `flutter test test/features/video_editor/services/caption_service_test.dart`
Expected: PASS, the existing tests included (`CaptionJobFailed` is a `SlimshotApiException`, so tests matching on its code still match).

- [ ] **Step 6: Full suite and analyzer**

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all pass; `48 issues found`.

- [ ] **Step 7: Commit**

```bash
git add lib/features/video_editor/services test/features/video_editor/services
git commit -m "feat(captions): the upload reports its charge; a failed job is told apart

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The pipeline prices, asks, and reports

**Files:**
- Modify: `lib/features/video_editor/services/caption_pipeline.dart`
- Modify: `lib/features/video_editor/services/caption_errors.dart`
- Test: `test/features/video_editor/services/caption_pipeline_test.dart`

**Interfaces:**
- Consumes: `CreditQuote` (Task 1), `shortfallLine` (Task 1), `CreditCharge` / `CaptionJobStart.charged` / `CaptionJobFailed` (Task 3).
- Produces:
  - `enum CaptionStage { preparing, pricing, uploading, listening, placing }`
  - `CaptionPipeline({…existing…, required Future<CreditQuote> Function(double durationSeconds) quotePrice, void Function(int balance)? onCharged})`
  - `Future<List<CaptionDraft>> run(CaptionRequest request, {required void Function(CaptionStage, double?) onProgress, Future<bool> Function(CreditQuote quote)? confirmPrice})` — no `confirmPrice` means a paid quote is **declined**.
  - `static const String CaptionFailure.refunded = 'REFUNDED'`

- [ ] **Step 1: Update the test helper** — in `caption_pipeline_test.dart`, add imports

```dart
import 'package:slimshotai/features/account/models/account_models.dart';
```

add `late List<double> quoted; late List<int> charges;` beside the other `late`s and initialise both to `[]` in `setUp`, then give `pipeline(...)` three more parameters and pass them through:

```dart
  CaptionPipeline pipeline({
    Future<CaptionAudioResult> Function(CaptionSource source)? render,
    Future<CaptionJobStart> Function(String? language)? start,
    Future<CaptionTranscript> Function(bool Function() isCancelled)? transcript,
    CreditQuote quote = const CreditQuote(credits: 0, balance: 94, enough: true),
    Future<CreditQuote> Function()? quoteWith,
    Future<CaptionJobStart> Function(String key)? startWithKey,
  }) {
    var n = 0;
    return CaptionPipeline(
      audioPath: () async => '/tmp/captions.m4a',
      deleteFile: (path) async => deleted.add(path),
      newKey: () => 'key-${++n}',
      renderAudio: (path, source, onProgress) async {
        onProgress(0.5);
        return render == null ? sound : render(source);
      },
      quotePrice: (seconds) async {
        quoted.add(seconds);
        return quoteWith == null ? quote : quoteWith();
      },
      startJob: (path, language, key) async {
        keys.add(key);
        if (startWithKey != null) return startWithKey(key);
        return start == null ? job : start(language);
      },
      awaitJob: (job, isCancelled) =>
          transcript == null ? Future.value(hello) : transcript(isCancelled),
      onCharged: charges.add,
      onCancel: () => cancels++,
    );
  }
```

The default quote is free, so every existing test runs as before; `expect(stages, CaptionStage.values)` now expects `pricing` too, which the pipeline reports even for a free quote.

- [ ] **Step 2: Write the failing tests** — append inside `main()`:

```dart
  const paid = CreditQuote(credits: 6, balance: 94, enough: true);
  void ignore(CaptionStage stage, double? value) {}

  test('a paid run is priced on the audio it rendered, then asked', () async {
    CreditQuote? asked;
    await pipeline(quote: paid).run(
      const CaptionRequest(),
      onProgress: ignore,
      confirmPrice: (q) async {
        asked = q;
        return true;
      },
    );
    expect(quoted, [3.0], reason: "the rendered sound's own length");
    expect(asked, same(paid));
    expect(keys, ['key-1']);
  });

  test('declining uploads nothing and cleans up', () async {
    await expectLater(
      pipeline(quote: paid).run(
        const CaptionRequest(),
        onProgress: ignore,
        confirmPrice: (_) async => false,
      ),
      throwsA(isA<CaptionCancelled>()),
    );
    expect(keys, isEmpty);
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('with nobody to ask, a paid run never uploads', () async {
    await expectLater(
      pipeline(quote: paid).run(const CaptionRequest(), onProgress: ignore),
      throwsA(isA<CaptionCancelled>()),
    );
    expect(keys, isEmpty);
  });

  test('a free run is not asked about', () async {
    var asked = false;
    await pipeline().run(
      const CaptionRequest(),
      onProgress: ignore,
      confirmPrice: (_) async => asked = true,
    );
    expect(asked, isFalse);
    expect(keys, ['key-1']);
  });

  test('a quote that fails uploads nothing', () async {
    await expectLater(
      pipeline(
        quoteWith: () async =>
            throw const SlimshotApiException('CAPTIONS_UNAVAILABLE'),
      ).run(const CaptionRequest(), onProgress: ignore),
      throwsA(isA<SlimshotApiException>()),
    );
    expect(keys, isEmpty);
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test("the upload's charged balance is reported", () async {
    await pipeline(
      quote: paid,
      start: (_) async => const CaptionJobStart(
        jobId: 'cap_1',
        pollAfter: Duration.zero,
        charged: CreditCharge(credits: 6, balance: 88),
      ),
    ).run(
      const CaptionRequest(),
      onProgress: ignore,
      confirmPrice: (_) async => true,
    );
    expect(charges, [88]);
  });

  test('a failed paid job says the credits came back; a free one does not',
      () async {
    Future<CaptionTranscript> fails(bool Function() _) async =>
        throw const CaptionJobFailed('PROVIDER_FAILED');

    await expectLater(
      pipeline(
        quote: paid,
        start: (_) async => const CaptionJobStart(
          jobId: 'cap_1',
          pollAfter: Duration.zero,
          charged: CreditCharge(credits: 6, balance: 88),
        ),
        transcript: fails,
      ).run(
        const CaptionRequest(),
        onProgress: ignore,
        confirmPrice: (_) async => true,
      ),
      throwsA(isA<CaptionFailure>()
          .having((e) => e.code, 'code', CaptionFailure.refunded)),
    );
    await expectLater(
      pipeline(transcript: fails)
          .run(const CaptionRequest(), onProgress: ignore),
      throwsA(isA<CaptionJobFailed>()),
    );
  });

  test('a key the server will not take again is replaced once', () async {
    var tries = 0;
    await pipeline(
      startWithKey: (key) async {
        if (tries++ == 0) {
          throw const SlimshotApiException('IDEMPOTENCY_KEY_REUSED');
        }
        return job;
      },
    ).run(const CaptionRequest(), onProgress: ignore);
    expect(keys, ['key-1', 'key-2']);
  });

  test('a second refusal of the key is not retried again', () async {
    await expectLater(
      pipeline(
        startWithKey: (_) async =>
            throw const SlimshotApiException('IDEMPOTENCY_KEY_REUSED'),
      ).run(const CaptionRequest(), onProgress: ignore),
      throwsA(isA<SlimshotApiException>()),
    );
    expect(keys, ['key-1', 'key-2']);
  });

  test("declining forgets a lost upload's key", () async {
    var lose = true;
    final p = pipeline(
      quote: paid,
      start: (_) async {
        if (lose) throw const SlimshotApiException(SlimshotApiException.network);
        return job;
      },
    );
    await expectLater(
      p.run(const CaptionRequest(),
          onProgress: ignore, confirmPrice: (_) async => true),
      throwsA(isA<SlimshotApiException>()),
    ); // key-1 kept: the upload may have landed
    await expectLater(
      p.run(const CaptionRequest(),
          onProgress: ignore, confirmPrice: (_) async => false),
      throwsA(isA<CaptionCancelled>()),
    );
    lose = false;
    await p.run(const CaptionRequest(),
        onProgress: ignore, confirmPrice: (_) async => true);
    expect(keys, ['key-1', 'key-2'], reason: 'a new upload, a new key');
  });

  test('a refusal for credits says how many', () {
    expect(
      captionErrorMessage(const SlimshotApiException(
        'INSUFFICIENT_CREDITS',
        'm',
        {'required': 6, 'balance': 2},
      )),
      'Needs 6 credits · You have 2',
    );
    expect(
      captionErrorMessage(const SlimshotApiException('INSUFFICIENT_CREDITS')),
      'Not enough credits for these captions.',
    );
    expect(
      captionErrorMessage(const CaptionFailure(CaptionFailure.refunded)),
      'Captioning failed. Your credits were returned.',
    );
  });
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/video_editor/services/caption_pipeline_test.dart`
Expected: FAIL to compile — `quotePrice`, `onCharged`, `confirmPrice`, `CaptionFailure.refunded` are not defined.

- [ ] **Step 4: The messages** — in `caption_errors.dart` add the import

```dart
import '../../account/logic/account_copy.dart';
```

add to `CaptionFailure`:

```dart
  /// A paid job the server failed; its credits are already back.
  static const String refunded = 'REFUNDED';
```

and at the top of `captionErrorMessage`, before `final code = …`:

```dart
  if (error is SlimshotApiException && error.code == 'INSUFFICIENT_CREDITS') {
    final needed = error.detailInt('required');
    final balance = error.detailInt('balance');
    // The balance moved between the price and the upload: say by how much.
    if (needed != null && balance != null) return shortfallLine(needed, balance);
  }
```

and in its `switch`, beside `CaptionFailure.noSpeech`:

```dart
    CaptionFailure.refunded => 'Captioning failed. Your credits were returned.',
```

- [ ] **Step 5: The pipeline** — in `caption_pipeline.dart`:

Add the import `import '../../account/models/account_models.dart';`.

Change the enum to:

```dart
enum CaptionStage { preparing, pricing, uploading, listening, placing }
```

Add to the constructor `required this.quotePrice,` and `this.onCharged,`, and the fields:

```dart
  /// What the rendered audio will cost — always asked, never worked out.
  final Future<CreditQuote> Function(double durationSeconds) quotePrice;

  /// The balance an upload's charge left, for the home pill.
  final void Function(int balance)? onCharged;
```

Replace `run` with:

```dart
  /// [confirmPrice] is asked before a paid upload; without one a paid run
  /// never uploads. A free run is not asked.
  Future<List<CaptionDraft>> run(
    CaptionRequest request, {
    required void Function(CaptionStage stage, double? progress) onProgress,
    Future<bool> Function(CreditQuote quote)? confirmPrice,
  }) async {
    _cancelled = false;
    var jobStarted = false;
    var paid = false;
    final path = await audioPath();
    try {
      onProgress(CaptionStage.preparing, 0);
      final audio = await renderAudio(
        path,
        request.source,
        (p) => onProgress(CaptionStage.preparing, p),
      );
      _throwIfCancelled();
      if (!audio.hasSound) throw const CaptionFailure(CaptionFailure.noSound);

      onProgress(CaptionStage.pricing, null);
      final quote = await quotePrice(audio.durationSeconds);
      _throwIfCancelled();
      if (!quote.isFree) {
        final approved = confirmPrice != null && await confirmPrice(quote);
        if (!approved || _cancelled) {
          // Nothing was uploaded for this audio, so no key belongs to it.
          _key = null;
          throw const CaptionCancelled();
        }
      }

      onProgress(CaptionStage.uploading, null);
      final job = await _upload(path, request.language);
      jobStarted = true;
      final charged = job.charged;
      if (charged != null) {
        paid = charged.credits > 0;
        onCharged?.call(charged.balance);
      }
      _throwIfCancelled();

      onProgress(CaptionStage.listening, null);
      final transcript = await awaitJob(job, () => _cancelled);
      _throwIfCancelled();

      onProgress(CaptionStage.placing, null);
      final drafts = groupCaptionWords(
        rebuildTranscriptSpacing(transcript.text, transcript.words),
        request.length,
        endLimitSeconds: audio.durationSeconds,
      );
      if (drafts.isEmpty) throw const CaptionFailure(CaptionFailure.noSpeech);
      _key = null;
      return drafts;
    } catch (error) {
      if (_cancelled ||
          error is CaptionAudioCancelled ||
          error is CaptionCancelled) {
        throw const CaptionCancelled();
      }
      // A key names one upload. Once the server holds a job for it, the same
      // key answers with that job — a failed one included — so a retry after
      // it needs a fresh key. A retry after an upload that never landed must
      // reuse its key, or a lost response becomes a second job.
      final uploadLost = !jobStarted &&
          error is SlimshotApiException &&
          error.code == SlimshotApiException.network;
      if (!uploadLost) _key = null;
      // The server refunds a failed paid job itself; say so.
      if (paid && error is CaptionJobFailed) {
        throw const CaptionFailure(CaptionFailure.refunded);
      }
      rethrow;
    } finally {
      await _deleteFile(path);
    }
  }

  /// Uploads under this run's key. A key that already paid for an earlier
  /// upload whose job is gone is refused with nothing charged; it is replaced
  /// once, and a second refusal is the server's to explain.
  Future<CaptionJobStart> _upload(String path, String? language) async {
    try {
      return await startJob(path, language, _key ??= _newKey());
    } on SlimshotApiException catch (e) {
      if (e.code != 'IDEMPOTENCY_KEY_REUSED') rethrow;
      _key = _newKey();
      return startJob(path, language, _key!);
    }
  }
```

- [ ] **Step 6: Run them to see them pass**

Run: `flutter test test/features/video_editor/services/caption_pipeline_test.dart`
Expected: PASS, the existing tests included.

- [ ] **Step 7: Full suite** — `test/features/video_editor/widgets/auto_caption_sheets_test.dart` builds a `CaptionPipeline` and will fail to compile without `quotePrice`. Add to its `pipelineWith` helper `quotePrice: (_) async => const CreditQuote(credits: 0, balance: 94, enough: true),` and the import `package:slimshotai/features/account/models/account_models.dart`. Also fix the one in `lib/screens/video_editor_screen.dart` minimally for now: `quotePrice: (_) async => const CreditQuote(credits: 0, balance: 0, enough: true),` with a `// wired in Task 6` comment, and the import `import '../features/account/models/account_models.dart';` — Task 6 replaces both.

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all pass; `48 issues found`.

- [ ] **Step 8: Commit**

```bash
git add lib/features/video_editor lib/screens/video_editor_screen.dart test/features/video_editor
git commit -m "feat(captions): price the audio before the upload, and report the charge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The price step in the progress sheet

**Files:**
- Modify: `lib/features/video_editor/widgets/panels/caption_progress_sheet.dart`
- Test: `test/features/video_editor/widgets/auto_caption_sheets_test.dart`

**Interfaces:**
- Consumes: `CaptionPipeline.run(confirmPrice:)`, `CaptionStage.pricing` (Task 4); `CreditQuote`, `priceLine`, `shortfallLine` (Task 1).
- Produces: keys `caption_price` (the line), `caption_confirm` (Generate), with the existing `caption_cancel` / `caption_close`.

- [ ] **Step 1: Let the helper price and count uploads** — in the `CaptionProgressSheet` group, change `pipelineWith` to:

```dart
    CaptionPipeline pipelineWith({
      required Future<CaptionAudioResult> Function() render,
      Future<CaptionTranscript> Function()? transcript,
      void Function()? onCancel,
      CreditQuote quote = const CreditQuote(credits: 0, balance: 94, enough: true),
      void Function()? onUpload,
    }) =>
        CaptionPipeline(
          audioPath: () async => '/tmp/none.m4a',
          deleteFile: (_) async {},
          renderAudio: (path, source, onProgress) => render(),
          quotePrice: (_) async => quote,
          startJob: (path, language, key) async {
            onUpload?.call();
            return const CaptionJobStart(jobId: 'cap_1', pollAfter: Duration.zero);
          },
          awaitJob: (job, isCancelled) =>
              transcript == null ? Future.value(hello) : transcript(),
          onCancel: onCancel ?? () {},
        );
```

- [ ] **Step 2: Write the failing tests** — append inside the group:

```dart
    testWidgets('a paid run shows its price and waits for Generate',
        (tester) async {
      var uploads = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () async => sound,
            quote: const CreditQuote(credits: 6, balance: 94, enough: true),
            onUpload: () => uploads++,
          ),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      expect(find.text('6 credits · You have 94'), findsOneWidget);
      expect(uploads, 0, reason: 'nothing leaves before Generate');

      await tapKey(tester, 'caption_confirm');
      expect(uploads, 1);
      expect((popped.single as List<CaptionDraft>).single.text, 'Hello');
    });

    testWidgets('closing at the price step uploads nothing', (tester) async {
      var uploads = 0;
      var cancels = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () async => sound,
            quote: const CreditQuote(credits: 6, balance: 94, enough: true),
            onUpload: () => uploads++,
            onCancel: () => cancels++,
          ),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      await tapKey(tester, 'caption_cancel');
      expect(popped.single, isNull);
      expect((uploads, cancels), (0, 1));

      // And by a tap outside the sheet.
      final again = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () async => sound,
            quote: const CreditQuote(credits: 6, balance: 94, enough: true),
            onUpload: () => uploads++,
          ),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(again.single, isNull);
      expect(uploads, 0);
    });

    testWidgets('short of credits: how many it needs, and only Close',
        (tester) async {
      var uploads = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () async => sound,
            quote: const CreditQuote(credits: 6, balance: 2, enough: false),
            onUpload: () => uploads++,
          ),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      expect(find.text('Needs 6 credits · You have 2'), findsOneWidget);
      expect(find.byKey(const Key('caption_confirm')), findsNothing);
      await tapKey(tester, 'caption_close');
      expect(popped.single, isNull);
      expect(uploads, 0);
    });

    testWidgets('a free run goes straight through', (tester) async {
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(render: () async => sound),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('caption_price')), findsNothing);
      expect((popped.single as List<CaptionDraft>).single.text, 'Hello');
    });
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/video_editor/widgets/auto_caption_sheets_test.dart`
Expected: FAIL — the paid run never shows a price (the sheet passes no `confirmPrice`, so it is declined) and `caption_confirm` is not found.

- [ ] **Step 4: Implement** — in `caption_progress_sheet.dart` add the imports

```dart
import '../../../account/logic/account_copy.dart';
import '../../../account/models/account_models.dart';
```

add to the state:

```dart
  /// The price waiting for an answer; null when none is asked.
  CreditQuote? _quote;
  Completer<bool>? _decision;

  Future<bool> _confirmPrice(CreditQuote quote) {
    final decision = Completer<bool>();
    setState(() {
      _quote = quote;
      _decision = decision;
    });
    return decision.future;
  }

  void _generate() {
    final decision = _decision;
    if (decision == null || decision.isCompleted) return;
    setState(() {
      _quote = null;
      _decision = null;
    });
    decision.complete(true);
  }
```

In `dispose`, before `super.dispose()` and after the cancel:

```dart
    // Closed while the price was showing — Cancel, Back, a tap outside: no.
    final decision = _decision;
    if (decision != null && !decision.isCompleted) decision.complete(false);
```

Pass it to the run: `widget.pipeline.run(widget.request, onProgress: …, confirmPrice: _confirmPrice)`.

In `_retry`, also clear `_quote = null; _decision = null;`.

Add `CaptionStage.pricing => 'Checking price',` to `_label`.

In `build`, read `final quote = _quote;` and make the children three-way: `if (error != null)` the existing error block, `else if (quote != null)` the price block, `else` the existing progress block. The price block:

```dart
                Text(
                  quote.enough
                      ? priceLine(quote.credits, quote.balance)
                      : shortfallLine(quote.credits, quote.balance),
                  key: const Key('caption_price'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                if (quote.enough)
                  Row(
                    children: [
                      Expanded(
                        child: SheetActionButton(
                          key: const Key('caption_cancel'),
                          label: 'Cancel',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SheetActionButton(
                          key: const Key('caption_confirm'),
                          label: 'Generate',
                          filled: true,
                          onTap: _generate,
                        ),
                      ),
                    ],
                  )
                else
                  SheetActionButton(
                    key: const Key('caption_close'),
                    label: 'Close',
                    onTap: () => Navigator.of(context).pop(),
                  ),
```

(The error block is now the first branch: change `if (error == null) ...[progress] else ...[error]` into `if (error != null) ...[error] else if (quote != null) ...[price] else ...[progress]`, keeping both existing blocks unchanged.)

- [ ] **Step 5: Run them to see them pass**

Run: `flutter test test/features/video_editor/widgets/auto_caption_sheets_test.dart`
Expected: PASS, the three existing progress-sheet tests included.

- [ ] **Step 6: Full suite and analyzer**

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all pass; `48 issues found`.

- [ ] **Step 7: Commit**

```bash
git add lib/features/video_editor/widgets/panels/caption_progress_sheet.dart test/features/video_editor/widgets/auto_caption_sheets_test.dart
git commit -m "feat(captions): the price step — Generate, or how many credits are needed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Wire the screen, and record the stage

**Files:**
- Modify: `lib/screens/video_editor_screen.dart` (`_startAutoCaptions`)
- Modify: `CLAUDE.md`
- Test: `test/features/video_editor/services/caption_access_test.dart` (its source-reading test)

**Interfaces:**
- Consumes: `AccountService.quote`, `AccountService.autoCaptionsFeature` (Task 1); `AccountNotifier.applyBalance` (Task 2); `CaptionPipeline(quotePrice:, onCharged:)` (Task 4).
- Produces: nothing new.

- [ ] **Step 1: Write the failing test** — in `caption_access_test.dart`'s source-reading test (`'Auto captions asks for an account before its options, and runs as the user'`), add after its last `expect`:

```dart
    expect(body, contains('quotePrice:'),
        reason: 'the run is priced by the server before it uploads');
    expect(body, contains('AccountService.autoCaptionsFeature'));
    expect(body, contains('.applyBalance('),
        reason: "the charge's balance reaches the pill at once");
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/features/video_editor/services/caption_access_test.dart`
Expected: FAIL — `AccountService.autoCaptionsFeature` and `.applyBalance(` are not in `_startAutoCaptions` yet.

- [ ] **Step 3: Wire it** — in `_startAutoCaptions`, after `final captions = CaptionService(api);` add

```dart
    // On the run's own client, so Cancel stops a quote in flight too.
    final account = AccountService(api);
```

and in the `CaptionPipeline(` call replace Task 4's placeholder `quotePrice` with:

```dart
      quotePrice: (seconds) =>
          account.quote(AccountService.autoCaptionsFeature, seconds),
      onCharged: (balance) =>
          unawaited(ref.read(accountProvider.notifier).applyBalance(balance)),
```

Add the import `import '../features/account/services/account_service.dart';` if the file does not have it, and **remove** Task 4's `import '../features/account/models/account_models.dart';` if nothing else in the file now uses it — an unused import would put the analyzer at 49. The existing `refresh()` after the sheet stays: it is what shows a refund.

- [ ] **Step 4: Run it to see it pass**

Run: `flutter test test/features/video_editor/services/caption_access_test.dart`
Expected: PASS.

- [ ] **Step 5: Record the stage in `CLAUDE.md`** — in "Accounts and credits — stage 1", replace the sentence

`After a run the profile is read again so the pill follows the charge — until stage 2 there is no confirm before the server charges.`

with

`After a run the profile is read again, which is what shows a refund.`

and add, directly after that section, a new section:

```markdown
### Accounts and credits — stage 2: the price step

**Awaiting device verification.** Plan: `docs/superpowers/plans/2026-10-06-credits-stage2-price-step.md`.
A run is **priced after the audio is rendered and before it is uploaded** (`CaptionStage.pricing`,
"Checking price"): `AccountService.quote` sends the rendered WAV's own length — the server measures
that file again and charges what it measures, so the app **never works a price out**. The progress
sheet shows `"6 credits · You have 94"` with Cancel / Generate, or `"Needs 6 credits · You have 2"`
with Close (stage 3 puts Watch an ad and Invite there). **A free quote skips the step.** The
pipeline asks through `run(confirmPrice:)`, and **with nobody to ask a paid run never uploads** — a
missing confirmer declines, it never approves. Closing the sheet at the step (Cancel, Back, a tap
outside) answers no. **Declining drops the run's key**: nothing was uploaded for that audio, so a
key kept from a lost upload would name a different one.

**The charge reaches the pill at once** (`onCharged` → `AccountNotifier.applyBalance`), ticketed
like every profile answer so a `/me` already on its way cannot put the old balance back.
**A paid job the server fails is refunded by the server**; `CaptionService` throws
`CaptionJobFailed` for a `failed` job (a `SlimshotApiException`, so its code still reads), and the
pipeline turns it into "Captioning failed. Your credits were returned." only when the upload
actually charged. `402 INSUFFICIENT_CREDITS` at the upload — the balance moved after the quote —
says how many from `details`. `409 IDEMPOTENCY_KEY_REUSED` takes one fresh key and uploads once
more; a second refusal is shown.
```

- [ ] **Step 6: Full suite and analyzer**

Run: `flutter test` then `flutter analyze --no-pub`
Expected: all pass; `48 issues found`.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/video_editor_screen.dart test/features/video_editor/services/caption_access_test.dart CLAUDE.md
git commit -m "feat(captions): wire the price step and the charge into the editor

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Device checks for the user (after Task 6)

1. Signed in with credits: Auto captions → "Checking price" → "N credits · You have M" → Generate → the home pill drops by N without a restart.
2. Cancel at the price step, and a tap outside it: no charge (pill unchanged; the admin history shows no `feature_charge`).
3. An account with fewer credits than the price: "Needs N credits · You have M", Close only.
4. If the admin sets Auto captions free (0): no price step at all.
