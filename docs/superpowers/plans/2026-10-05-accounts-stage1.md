# Accounts — Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optional sign-in (Google or an emailed code), the claim step, the credits pill on the home screen and an Account section in Settings — and Auto captions asks for sign-in before it starts, then runs as the signed-in user.

**Architecture:** Tokens live in the platform keystore (`flutter_secure_storage`) behind a small `TokenVault`. One shared `AccountSession` owns the tokens and the cached profile, and serialises refreshes so a refresh token is never used twice. `SlimshotApi` gains signed-in requests (access token, one refresh, then "sign in"), sign-in requests (install token in the body) and public requests. `AccountService` is one method per endpoint; `AccountNotifier` (Riverpod, app-wide) is the signed-in state the UI watches. `requireAccount` is the one door: sign-in sheet, then claim sheet.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, flutter_riverpod 2 (`StateNotifier`), `package:http` with `MockClient` in tests, `flutter_secure_storage` ^10.3.4, `google_sign_in` ^7.2.0.

**Spec:** `docs/superpowers/specs/2026-10-05-app-accounts-credits-design.md` (this plan is its §8 stage 1). Server contract: `slimshot_server/docs/app-credits-api.md` on the server's `feat/accounts-credits` branch.

**Stages:** this is stage 1 of 3. Stage 2 (the price step, charge and refund in the balance) and stage 3 (rewarded ads, invites, the Credits screen with history) get their own plans after stage 1 is tested on a device. Until stage 2, a caption run is charged by the server without a confirm step; the balance on the home screen follows it.

## Global Constraints

- Branch: `feat/accounts-credits`. Commit per task; **never push or merge** — the owner tests on a device first.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Test-first: every new behaviour has a test that was run and seen to fail before the code existed.
- `flutter analyze --no-pub` must still report exactly **48 issues** at the end (the pre-existing count); new code adds none.
- Colours come from `AppColors`, never hard-coded (white only for a glyph or label on the purple accent). Icons are `LucideIcons` from `lib/core/theme/lucide_icons.dart`.
- Sheets open through `showEditorSheet` (`lib/features/video_editor/widgets/panels/editor_sheet.dart`); a test fails on any direct `showModalBottomSheet` call in `lib/`.
- UI copy is minimal: one heading saying **why** a sheet opened, never which tool opened it; errors are one line, no titles; toasts via `ToastUtils.show(context, message, isError:)`.
- Account sheets are at most **480 px** wide, centred (`kAccountSheetMaxWidth`).
- Branch on `error.code`, never on the server's message.
- The Google Web client ID comes only from `--dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=…`; without it the Google button is not shown.
- Accounts are offered only in a build with a server (`SlimshotApi.isConfigured`, i.e. `--dart-define=SLIMSHOT_API_URL=…`), through `accountFeatureProvider`.
- No Android ID is read or sent anywhere.
- Tests that measure text use `kTestFontFamily`; widget tests never `pumpAndSettle` while a spinner may be on screen — they `pump` with durations (`settle`).

## Review Focus

1. **An availability answer for a name the user has already typed over** must not mark the new text available or enable Claim — the answer arrives late on a mobile connection (Task 7).
2. **A session ended by any request** — a caption upload refused with `SIGN_IN_REQUIRED`, say — must flip the whole app to signed out, home pill included (Task 5).
3. **A server error or proxy page during a token refresh** must not sign the user out; only a refusal (401) ends a session (Task 3).
4. **Signing out with no connection** must still sign out on the phone (Task 5).
5. **A profile request that lands after signing out** must not write the user's email and username back to the phone (Task 5).

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/core/services/token_vault.dart` (new) | `TokenVault` interface; `SecureTokenVault` over `flutter_secure_storage`, an unreadable value reads as absent. |
| `lib/core/services/account_session.dart` (new) | `SessionTokens`; `AccountSession`: tokens, cached profile, `end()`, `ended` stream, serialised `refreshAfter`. |
| `lib/core/services/slimshot_api.dart` (modify) | Exception `details`; `SecureDeviceTokenStore` (moves the install token out of prefs); signed-in `send`, `sendPublic`, `sendWithDevice`, `deviceToken`, `jsonRequest`. |
| `lib/features/account/models/account_models.dart` (new) | `AccountUser`, `SignInResult`, `EmailCodeSent`, `UsernameAvailability`, `ClaimResult`. |
| `lib/features/account/logic/account_copy.dart` (new) | Every account line the user reads: `accountErrorMessage`, `usernameReasonMessage`, `claimResultLines`, `kUsernameRule`, `kGoogleSignInFailed`. |
| `lib/features/account/logic/username_rules.dart` (new) | `isValidUsername`, `usernameInputFormatters`, `kUsernameCheckDelay`. |
| `lib/features/account/services/account_service.dart` (new) | One method per account endpoint. |
| `lib/features/account/services/google_id_tokens.dart` (new) | `GoogleIdTokens` interface; `PluginGoogleIdTokens` over `google_sign_in` 7. |
| `lib/features/account/providers/account_providers.dart` (new) | Providers; `AccountState`; `AccountNotifier`. |
| `lib/features/account/widgets/account_sheet_frame.dart` (new) | The sheet frame (480 cap, keyboard inset), heading, error line, primary button, input decoration. |
| `lib/features/account/widgets/sign_in_sheet.dart` (new) | Google + email + code. |
| `lib/features/account/widgets/username_field.dart` (new) | Debounced, stale-safe availability field. |
| `lib/features/account/widgets/claim_sheet.dart` (new) | Username, optional invite code, the claimed result. |
| `lib/features/account/account_gate.dart` (new) | `requireAccount`. |
| `lib/features/account/widgets/credits_pill.dart` (new) | Home pill: balance, or "Free credits". Refreshes on resume. |
| `lib/screens/home_header.dart` (new) | Brand + pill row; the brand scales down on a narrow phone. |
| `lib/core/widgets/settings_rows.dart` (new) | `SettingsSectionHeader`, `SettingsItem`, `SettingsDivider`, moved out of `settings_screen.dart`. |
| `lib/features/account/widgets/settings_account_section.dart` (new) | The Account section. |
| `lib/features/account/widgets/username_sheet.dart` (new) | Change username. |
| `lib/features/account/widgets/delete_account_sheet.dart` (new) | Confirm and delete. |
| `lib/features/video_editor/services/caption_access.dart` (modify) | `ensureAllowed(context, ref)` → `requireAccount`. |
| `lib/features/video_editor/services/caption_errors.dart` (modify) | Lines for `SIGN_IN_REQUIRED`, `INSUFFICIENT_CREDITS`, `ACCOUNT_SUSPENDED`. |
| `lib/screens/video_editor_screen.dart` (modify) | Gate before the options sheet; the caption client shares the session; balance refresh after a run. |
| `lib/screens/home_screen.dart`, `lib/screens/settings_screen.dart` (modify) | Place the pill and the section. |
| `test/support/account_fakes.dart`, `test/support/fake_server.dart`, `test/support/account_harness.dart` (new) | Memory vault and device tokens, a signed-in session, a path-routed fake server, provider overrides, a sheet host. |

---

### Task 1: Secrets in the keystore

**Files:**
- Modify: `pubspec.yaml` (dependencies)
- Create: `lib/core/services/token_vault.dart`
- Modify: `lib/core/services/slimshot_api.dart` (replace `PrefsDeviceTokenStore` with `SecureDeviceTokenStore`)
- Create: `test/support/account_fakes.dart`
- Create: `test/core/services/token_vault_test.dart`
- Create: `test/core/services/secure_device_token_store_test.dart`
- Modify: `test/core/services/slimshot_api_test.dart` (drop the prefs-store test)

**Interfaces:**
- Produces: `abstract class TokenVault { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); }`; `class SecureTokenVault implements TokenVault { const SecureTokenVault([FlutterSecureStorage storage]); }`; `class SecureDeviceTokenStore implements DeviceTokenStore { const SecureDeviceTokenStore([TokenVault vault]); static const String vaultKey = 'slimshot_device_token'; static const String legacyPrefsKey = 'slimshot_device_token'; }`; test `MemoryTokenVault` with a public `Map<String, String> values`.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under the `# Utils` block (after `uuid: ^4.4.0`), add:

```yaml
  # Sign-in tokens and the install token, in the platform keystore.
  flutter_secure_storage: ^10.3.4
```

Run: `flutter pub get`
Expected: `Got dependencies!` with `flutter_secure_storage 10.3.4` added.

- [ ] **Step 2: Write the test support vault**

Create `test/support/account_fakes.dart`:

```dart
import 'package:slimshotai/core/services/token_vault.dart';

/// A [TokenVault] in memory: what a test stores, it can read straight back.
class MemoryTokenVault implements TokenVault {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
```

- [ ] **Step 3: Write the failing tests**

Create `test/core/services/token_vault_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/token_vault.dart';

/// Storage whose every read fails, as it does on a phone that restored a
/// backup without the keystore key that encrypted it.
class _UnreadableStorage implements FlutterSecureStorage {
  const _UnreadableStorage();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #read) {
      return Future<String?>.error(
        PlatformException(code: 'Exception', message: 'BAD_DECRYPT'),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores, reads and deletes a value', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const vault = SecureTokenVault();
    expect(await vault.read('k'), isNull);
    await vault.write('k', 'v');
    expect(await vault.read('k'), 'v');
    await vault.delete('k');
    expect(await vault.read('k'), isNull);
  });

  test('a value that cannot be decrypted reads as absent', () async {
    const vault = SecureTokenVault(_UnreadableStorage());
    expect(await vault.read('k'), isNull);
  });
}
```

Create `test/core/services/secure_device_token_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';

import '../../support/account_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a token kept in preferences moves into the vault, once', () async {
    SharedPreferences.setMockInitialValues({
      SecureDeviceTokenStore.legacyPrefsKey: 'old-token',
    });
    final vault = MemoryTokenVault();
    final store = SecureDeviceTokenStore(vault);

    expect(await store.read(), 'old-token');
    expect(vault.values[SecureDeviceTokenStore.vaultKey], 'old-token');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SecureDeviceTokenStore.legacyPrefsKey), isNull);
    expect(await store.read(), 'old-token');
  });

  test('the vault wins over a leftover in preferences', () async {
    SharedPreferences.setMockInitialValues({
      SecureDeviceTokenStore.legacyPrefsKey: 'old-token',
    });
    final vault = MemoryTokenVault()
      ..values[SecureDeviceTokenStore.vaultKey] = 'new-token';
    expect(await SecureDeviceTokenStore(vault).read(), 'new-token');
  });

  test('nothing stored reads as nothing', () async {
    expect(await SecureDeviceTokenStore(MemoryTokenVault()).read(), isNull);
  });

  test('write and clear go to the vault, and clear leaves no copy behind',
      () async {
    SharedPreferences.setMockInitialValues({
      SecureDeviceTokenStore.legacyPrefsKey: 'old-token',
    });
    final vault = MemoryTokenVault();
    final store = SecureDeviceTokenStore(vault);
    await store.write('t');
    expect(vault.values[SecureDeviceTokenStore.vaultKey], 't');
    await store.clear();
    expect(vault.values, isEmpty);
    expect(await store.read(), isNull);
  });
}
```

In `test/core/services/slimshot_api_test.dart`, delete the test `'the token is kept in preferences'` (the class it tests is being replaced) and remove the now-unused `import 'package:shared_preferences/shared_preferences.dart';`.

- [ ] **Step 4: Run the tests to see them fail**

Run: `flutter test test/core/services/token_vault_test.dart test/core/services/secure_device_token_store_test.dart`
Expected: FAIL — compilation errors: `token_vault.dart` not found, `SecureDeviceTokenStore` isn't defined.

- [ ] **Step 5: Write the vault**

Create `lib/core/services/token_vault.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small secrets by name: the install token, the session tokens and the
/// signed-in profile.
abstract class TokenVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The vault in the platform's keystore-backed storage.
///
/// **A value that cannot be decrypted reads as absent.** A backup restored
/// onto a phone whose keystore never held the key that encrypted it cannot be
/// read back; throwing there would break every launch, where reading nothing
/// leaves the app signed out — which is the truth on that phone.
class SecureTokenVault implements TokenVault {
  const SecureTokenVault([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('SecureTokenVault: $key unreadable ($e)');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('SecureTokenVault: $key not deleted ($e)');
    }
  }
}
```

- [ ] **Step 6: Replace the prefs store**

In `lib/core/services/slimshot_api.dart`, add `import 'token_vault.dart';` after the `shared_preferences` import, then replace the whole `PrefsDeviceTokenStore` class (its doc comment included) with:

```dart
/// The install token, in the [TokenVault].
///
/// It used to live in `shared_preferences`; once sign-in made the install a
/// key to an account it was worth protecting. It moves the first time it is
/// read — the old copy is removed only after the new one is written, so a
/// move cut short loses nothing.
class SecureDeviceTokenStore implements DeviceTokenStore {
  const SecureDeviceTokenStore([this._vault = const SecureTokenVault()]);

  final TokenVault _vault;

  static const String vaultKey = 'slimshot_device_token';
  static const String legacyPrefsKey = 'slimshot_device_token';

  @override
  Future<String?> read() async {
    final stored = await _vault.read(vaultKey);
    if (stored != null) return stored;
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyPrefsKey);
    if (legacy == null) return null;
    await _vault.write(vaultKey, legacy);
    await prefs.remove(legacyPrefsKey);
    return legacy;
  }

  @override
  Future<void> write(String token) => _vault.write(vaultKey, token);

  @override
  Future<void> clear() async {
    await _vault.delete(vaultKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyPrefsKey);
  }
}
```

In the `SlimshotApi` constructor, change the default `DeviceTokenStore tokens = const PrefsDeviceTokenStore(),` to `DeviceTokenStore tokens = const SecureDeviceTokenStore(),`.

- [ ] **Step 7: Run the tests to see them pass**

Run: `flutter test test/core/services/token_vault_test.dart test/core/services/secure_device_token_store_test.dart test/core/services/slimshot_api_test.dart test/features/video_editor/services/caption_service_test.dart`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/services/token_vault.dart lib/core/services/slimshot_api.dart test/support/account_fakes.dart test/core/services/token_vault_test.dart test/core/services/secure_device_token_store_test.dart test/core/services/slimshot_api_test.dart
git commit -m "feat(account): keep the install token in the keystore

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The session, and one refresh at a time

**Files:**
- Create: `lib/core/services/account_session.dart`
- Create: `test/core/services/account_session_test.dart`

**Interfaces:**
- Consumes: `TokenVault`, `SecureTokenVault` (Task 1).
- Produces: `class SessionTokens { const SessionTokens({required String accessToken, required String refreshToken}); }`; `class AccountSession { AccountSession({TokenVault vault}); static const accessKey, refreshKey, profileKey; Stream<void> get ended; Future<SessionTokens?> read(); Future<void> save(SessionTokens); Future<String?> readProfile(); Future<void> saveProfile(String json); Future<void> end(); Future<SessionTokens?> refreshAfter(String failedAccess, Future<SessionTokens?> Function(String refreshToken) refresh); }`.

- [ ] **Step 1: Write the failing tests**

Create `test/core/services/account_session_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/account_session.dart';

import '../../support/account_fakes.dart';

void main() {
  late MemoryTokenVault vault;
  late AccountSession session;
  const first = SessionTokens(accessToken: 'a1', refreshToken: 'r1');
  const second = SessionTokens(accessToken: 'a2', refreshToken: 'r2');

  setUp(() {
    vault = MemoryTokenVault();
    session = AccountSession(vault: vault);
  });

  test('saves, reads and ends a session, the profile with it', () async {
    expect(await session.read(), isNull);
    await session.save(first);
    await session.saveProfile('{"id":"u1"}');
    final read = await session.read();
    expect((read!.accessToken, read.refreshToken), ('a1', 'r1'));
    expect(await session.readProfile(), '{"id":"u1"}');

    final ended = expectLater(session.ended, emits(null));
    await session.end();
    await ended;
    expect(await session.read(), isNull);
    expect(vault.values, isEmpty);
  });

  test('two refusals at once share one refresh', () async {
    await session.save(first);
    var refreshes = 0;
    final gate = Completer<void>();
    Future<SessionTokens?> refresh(String token) async {
      refreshes++;
      expect(token, 'r1');
      await gate.future;
      return second;
    }

    final a = session.refreshAfter('a1', refresh);
    final b = session.refreshAfter('a1', refresh);
    gate.complete();
    final results = await Future.wait([a, b]);

    expect(refreshes, 1);
    expect(results.map((t) => t!.accessToken), ['a2', 'a2']);
    expect((await session.read())!.refreshToken, 'r2');
  });

  test('a refusal with a token already replaced takes the new one', () async {
    await session.save(second);
    var refreshes = 0;
    final result = await session.refreshAfter('a1', (_) async {
      refreshes++;
      return null;
    });
    expect(result!.accessToken, 'a2');
    expect(refreshes, 0);
  });

  test('a refused refresh ends the session', () async {
    await session.save(first);
    final ended = expectLater(session.ended, emits(null));
    expect(await session.refreshAfter('a1', (_) async => null), isNull);
    await ended;
    expect(await session.read(), isNull);
  });

  test('a refresh that cannot reach the server keeps the session', () async {
    await session.save(first);
    await expectLater(
      session.refreshAfter(
        'a1',
        (_) async => throw const SocketException('offline'),
      ),
      throwsA(isA<SocketException>()),
    );
    expect((await session.read())!.accessToken, 'a1');

    // The next refusal may try again.
    final again = await session.refreshAfter('a1', (_) async => second);
    expect(again!.accessToken, 'a2');
  });

  test('with no session there is nothing to refresh', () async {
    var refreshes = 0;
    final result = await session.refreshAfter('a1', (_) async {
      refreshes++;
      return second;
    });
    expect(result, isNull);
    expect(refreshes, 0);
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/core/services/account_session_test.dart`
Expected: FAIL — `account_session.dart` not found.

- [ ] **Step 3: Write the session**

Create `lib/core/services/account_session.dart`:

```dart
import 'dart:async';

import 'token_vault.dart';

/// A signed-in session: the short-lived access token every signed-in request
/// carries, and the refresh token that replaces it.
class SessionTokens {
  const SessionTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// The signed-in session on this phone, shared by every server client.
///
/// **Refreshes run one at a time**, and they have to: the server lets a
/// refresh token work once, and a second use looks like a stolen token and
/// ends the whole session. Two requests refused together therefore take
/// turns — the first exchanges the refresh token, and the second, finding the
/// access token it was refused with already replaced, simply uses the new one.
///
/// Everything personal the app keeps — the tokens and the last profile — is
/// here, so [end] is the one place that forgets it.
class AccountSession {
  AccountSession({TokenVault vault = const SecureTokenVault()}) : _vault = vault;

  static const String accessKey = 'account_access_token';
  static const String refreshKey = 'account_refresh_token';
  static const String profileKey = 'account_profile';

  final TokenVault _vault;
  final StreamController<void> _ended = StreamController<void>.broadcast();
  Future<SessionTokens?> _turns = Future<SessionTokens?>.value();

  /// Fires whenever the session ends: signed out, deleted, or refused by the
  /// server.
  Stream<void> get ended => _ended.stream;

  Future<SessionTokens?> read() async {
    final access = await _vault.read(accessKey);
    final refresh = await _vault.read(refreshKey);
    if (access == null || refresh == null) return null;
    return SessionTokens(accessToken: access, refreshToken: refresh);
  }

  Future<void> save(SessionTokens tokens) async {
    await _vault.write(accessKey, tokens.accessToken);
    await _vault.write(refreshKey, tokens.refreshToken);
  }

  /// The last `/me` the app saw, as JSON — what the home screen shows before
  /// the server has answered.
  Future<String?> readProfile() => _vault.read(profileKey);

  Future<void> saveProfile(String json) => _vault.write(profileKey, json);

  Future<void> end() async {
    await _vault.delete(accessKey);
    await _vault.delete(refreshKey);
    await _vault.delete(profileKey);
    _ended.add(null);
  }

  /// The session to retry with after a request was refused with
  /// [failedAccess].
  ///
  /// [refresh] trades a refresh token for new tokens. It answers null when
  /// the server refused the refresh token — the session is then over — and
  /// throws when the server could not be reached or did not answer, which
  /// says nothing about the session, so it is not ended for that. Returns
  /// null once there is no session.
  Future<SessionTokens?> refreshAfter(
    String failedAccess,
    Future<SessionTokens?> Function(String refreshToken) refresh,
  ) {
    final turn = _turns
        .catchError((Object _) => null)
        .then((_) => _rotate(failedAccess, refresh));
    _turns = turn;
    return turn;
  }

  Future<SessionTokens?> _rotate(
    String failedAccess,
    Future<SessionTokens?> Function(String refreshToken) refresh,
  ) async {
    final current = await read();
    if (current == null) return null;
    if (current.accessToken != failedAccess) return current;
    final fresh = await refresh(current.refreshToken);
    if (fresh == null) {
      await end();
      return null;
    }
    await save(fresh);
    return fresh;
  }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `flutter test test/core/services/account_session_test.dart`
Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/account_session.dart test/core/services/account_session_test.dart
git commit -m "feat(account): a shared session whose refreshes take turns

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Signed-in requests in the server client

**Files:**
- Modify: `lib/core/services/slimshot_api.dart`
- Modify: `lib/screens/video_editor_screen.dart:1107` (pass a session — temporary, Task 10 shares the app's)
- Modify: `test/support/account_fakes.dart` (add `MemoryDeviceTokens`, `signedInSession`)
- Rewrite: `test/core/services/slimshot_api_test.dart`
- Modify: `test/features/video_editor/services/caption_service_test.dart` (build the client with a session)

**Interfaces:**
- Consumes: `AccountSession`, `SessionTokens` (Task 2); `SecureDeviceTokenStore` (Task 1).
- Produces on `SlimshotApiException`: `const SlimshotApiException(String code, [String message = '', Map<String, Object?> details = const {}])`, `static const String signInRequired = 'SIGN_IN_REQUIRED'`, `int? detailInt(String key)`.
- Produces on `SlimshotApi`: constructor `SlimshotApi({required String baseUrl, required AccountSession session, http.Client? client, DeviceTokenStore tokens})`; `Future<Map<String, dynamic>> send(http.BaseRequest Function() build, {Duration timeout})` — **now signed in**; `Future<Map<String, dynamic>> sendPublic(http.BaseRequest Function() build, {Duration timeout})`; `Future<Map<String, dynamic>> sendWithDevice(String path, Map<String, Object?> body, {Duration timeout})`; `Future<String> deviceToken({Duration timeout})`; `http.Request jsonRequest(String method, String path, Map<String, Object?> body)`.
- Produces in test support: `class MemoryDeviceTokens implements DeviceTokenStore { MemoryDeviceTokens([String? token]); String? token; }`; `AccountSession signedInSession({String access = 'tok', String refresh = 'ref', Map<String, Object?>? profile})`.

- [ ] **Step 1: Extend the test support**

Replace `test/support/account_fakes.dart` with:

```dart
import 'dart:convert';

import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/core/services/token_vault.dart';

/// A [TokenVault] in memory: what a test stores, it can read straight back.
class MemoryTokenVault implements TokenVault {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// An install token in memory; null until the install is registered.
class MemoryDeviceTokens implements DeviceTokenStore {
  MemoryDeviceTokens([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

/// A session already signed in, optionally with a profile kept from last
/// time.
AccountSession signedInSession({
  String access = 'tok',
  String refresh = 'ref',
  Map<String, Object?>? profile,
}) {
  final vault = MemoryTokenVault();
  vault.values[AccountSession.accessKey] = access;
  vault.values[AccountSession.refreshKey] = refresh;
  if (profile != null) {
    vault.values[AccountSession.profileKey] = jsonEncode(profile);
  }
  return AccountSession(vault: vault);
}
```

- [ ] **Step 2: Write the failing tests**

Replace `test/core/services/slimshot_api_test.dart` with:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';

import '../../support/account_fakes.dart';

http.Response envelope(Object data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status);

http.Response failure(
  String code,
  int status, {
  Map<String, Object?>? details,
}) =>
    http.Response(
      jsonEncode({
        'success': false,
        'error': {
          'code': code,
          'message': 'm',
          if (details != null) 'details': details,
          'traceId': 't',
        },
      }),
      status,
    );

Matcher throwsCode(String code) => throwsA(
      isA<SlimshotApiException>().having((e) => e.code, 'code', code),
    );

SlimshotApi apiWith(
  MockClient client, {
  AccountSession? session,
  DeviceTokenStore? devices,
}) =>
    SlimshotApi(
      baseUrl: 'https://api.test/',
      client: client,
      session: session ?? signedInSession(access: 'a1', refresh: 'r1'),
      tokens: devices ?? MemoryDeviceTokens(),
    );

const fresh = {'accessToken': 'a2', 'refreshToken': 'r2', 'expiresIn': 900};

void main() {
  group('signed-in requests', () {
    test('carry the access token, and never register the install', () async {
      final seen = <http.Request>[];
      final api = apiWith(MockClient((request) async {
        seen.add(request);
        return envelope({'ok': true});
      }));
      await api.send(() => http.Request('GET', api.uri('/me')));

      expect(seen, hasLength(1));
      expect(seen.single.headers['Authorization'], 'Bearer a1');
      expect(seen.single.url.toString(), 'https://api.test/api/app/v1/me');
    });

    test('with no session nothing is sent: the user has to sign in', () async {
      var sends = 0;
      final api = apiWith(
        MockClient((_) async {
          sends++;
          return envelope({});
        }),
        session: AccountSession(vault: MemoryTokenVault()),
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.signInRequired),
      );
      expect(sends, 0);
    });

    test('an expired token is refreshed once and the request rebuilt',
        () async {
      var built = 0;
      late http.Request exchange;
      final session = signedInSession(access: 'a1', refresh: 'r1');
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            exchange = request;
            return envelope(fresh);
          }
          return request.headers['Authorization'] == 'Bearer a2'
              ? envelope({'ok': true})
              : failure('UNAUTHENTICATED', 401);
        }),
        session: session,
      );
      final data = await api.send(() {
        built++;
        return http.Request('GET', api.uri('/me'));
      });

      expect(data, {'ok': true});
      expect(built, 2);
      expect(jsonDecode(exchange.body), {'refreshToken': 'r1'});
      expect(exchange.headers['Authorization'], isNull);
      final saved = await session.read();
      expect((saved!.accessToken, saved.refreshToken), ('a2', 'r2'));
    });

    test('two requests refused at once share one refresh', () async {
      var refreshes = 0;
      final api = apiWith(MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return envelope(fresh);
        }
        return request.headers['Authorization'] == 'Bearer a2'
            ? envelope({'ok': true})
            : failure('UNAUTHENTICATED', 401);
      }));
      final results = await Future.wait([
        api.send(() => http.Request('GET', api.uri('/me'))),
        api.send(() => http.Request('GET', api.uri('/credits/history'))),
      ]);
      expect(results, [
        {'ok': true},
        {'ok': true},
      ]);
      expect(refreshes, 1);
    });

    test('a refused refresh ends the session', () async {
      final session = signedInSession(access: 'a1', refresh: 'r1');
      final api = apiWith(
        MockClient((request) async => failure('UNAUTHENTICATED', 401)),
        session: session,
      );
      final ended = expectLater(session.ended, emits(null));
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.signInRequired),
      );
      await ended;
      expect(await session.read(), isNull);
    });

    test('a refresh the server could not answer keeps the session', () async {
      final session = signedInSession(access: 'a1', refresh: 'r1');
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return http.Response('<html>Bad gateway</html>', 502);
          }
          return failure('UNAUTHENTICATED', 401);
        }),
        session: session,
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.badResponse),
      );
      expect((await session.read())!.accessToken, 'a1');
    });

    test('a refresh with no connection keeps the session', () async {
      final session = signedInSession(access: 'a1', refresh: 'r1');
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            throw http.ClientException('offline');
          }
          return failure('UNAUTHENTICATED', 401);
        }),
        session: session,
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.network),
      );
      expect((await session.read())!.accessToken, 'a1');
    });

    test('a second refusal is an answer, not a loop', () async {
      var sends = 0;
      var refreshes = 0;
      final session = signedInSession(access: 'a1', refresh: 'r1');
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshes++;
            return envelope(fresh);
          }
          sends++;
          return failure('UNAUTHENTICATED', 401);
        }),
        session: session,
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.signInRequired),
      );
      expect((sends, refreshes), (2, 1));
      expect(await session.read(), isNull);
    });

    test('SIGN_IN_REQUIRED from the server ends the session', () async {
      final session = signedInSession();
      final api = apiWith(
        MockClient((_) async => failure('SIGN_IN_REQUIRED', 401)),
        session: session,
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/me'))),
        throwsCode(SlimshotApiException.signInRequired),
      );
      expect(await session.read(), isNull);
    });
  });

  group('sign-in requests', () {
    test('carry the install token in the body, registering once', () async {
      final seen = <http.Request>[];
      final devices = MemoryDeviceTokens();
      final api = apiWith(
        MockClient((request) async {
          seen.add(request);
          if (request.url.path.endsWith('/devices')) {
            return envelope({'token': 'dev-1'}, 201);
          }
          return envelope({'sentTo': 'ann@example.com'});
        }),
        devices: devices,
      );
      await api.sendWithDevice('/auth/email/start', {'email': 'ann@example.com'});
      await api.sendWithDevice('/auth/email/start', {'email': 'ann@example.com'});

      final registrations = seen.where((r) => r.url.path.endsWith('/devices'));
      expect(registrations, hasLength(1));
      expect(jsonDecode(registrations.single.body), {'platform': 'android'});
      final start = seen.last;
      expect(jsonDecode(start.body), {
        'email': 'ann@example.com',
        'deviceToken': 'dev-1',
      });
      expect(start.headers['Authorization'], isNull);
      expect(start.headers['Content-Type'], startsWith('application/json'));
      expect(devices.token, 'dev-1');
    });

    test('an install the server no longer knows is registered again, once',
        () async {
      final devices = MemoryDeviceTokens('stale');
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return envelope({'token': 'fresh'}, 201);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return body['deviceToken'] == 'fresh'
              ? envelope({'ok': true})
              : failure('DEVICE_NOT_REGISTERED', 422);
        }),
        devices: devices,
      );
      final data = await api.sendWithDevice('/auth/google', {'idToken': 'g'});
      expect(data, {'ok': true});
      expect(devices.token, 'fresh');
    });

    test('a public request carries no bearer', () async {
      late http.Request seen;
      final api = apiWith(MockClient((request) async {
        seen = request;
        return envelope({'loggedOut': true});
      }));
      await api.sendPublic(
        () => api.jsonRequest('POST', '/auth/logout', {'refreshToken': 'r1'}),
      );
      expect(seen.headers['Authorization'], isNull);
      expect(jsonDecode(seen.body), {'refreshToken': 'r1'});
    });
  });

  group('answers', () {
    test('a refusal carries its code, message and details', () async {
      final api = apiWith(
        MockClient(
          (_) async => failure('OTP_INVALID', 422, details: {'attemptsLeft': 3}),
        ),
        devices: MemoryDeviceTokens('dev-1'),
      );
      await expectLater(
        api.sendWithDevice('/auth/email/verify', {'code': '1'}),
        throwsA(
          isA<SlimshotApiException>()
              .having((e) => e.code, 'code', 'OTP_INVALID')
              .having((e) => e.message, 'message', 'm')
              .having((e) => e.detailInt('attemptsLeft'), 'attemptsLeft', 3),
        ),
      );
    });

    test('no connection is NETWORK', () async {
      final api = apiWith(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/x'))),
        throwsCode(SlimshotApiException.network),
      );
    });

    test('a request that never answers times out as NETWORK', () async {
      final api = apiWith(
        MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        api.send(
          () => http.Request('GET', api.uri('/x')),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsCode(SlimshotApiException.network),
      );
    });

    test('a body that is not the envelope is BAD_RESPONSE', () async {
      final api = apiWith(MockClient((_) async => http.Response('<html>', 502)));
      await expectLater(
        api.send(() => http.Request('GET', api.uri('/x'))),
        throwsCode(SlimshotApiException.badResponse),
      );
    });

    test('a build without a server address has no server', () {
      expect(SlimshotApi.isConfigured, isFalse);
    });
  });
}
```

In `test/features/video_editor/services/caption_service_test.dart`:
- delete the `MemoryTokens` class;
- add `import '../../../support/account_fakes.dart';`;
- in both `SlimshotApi(...)` constructions, replace `tokens: MemoryTokens(),` with `session: signedInSession(), tokens: MemoryDeviceTokens(),`.

(`signedInSession()` signs in with access token `tok`, so the existing assertion `upload.headers['Authorization'] == 'Bearer tok'` still holds — now as a signed-in upload.)

- [ ] **Step 3: Run the tests to see them fail**

Run: `flutter test test/core/services/slimshot_api_test.dart`
Expected: FAIL — compilation errors: no named parameter `session`, `sendWithDevice`/`sendPublic`/`jsonRequest`/`detailInt`/`signInRequired` not defined.

- [ ] **Step 4: Implement**

In `lib/core/services/slimshot_api.dart`:

Add `import 'account_session.dart';` beside `import 'token_vault.dart';`.

Replace the `SlimshotApiException` class with:

```dart
/// A request the server refused, or one that never reached it.
class SlimshotApiException implements Exception {
  const SlimshotApiException(
    this.code, [
    this.message = '',
    this.details = const {},
  ]);

  /// The server's error code (`CAPTIONS_UNAVAILABLE`, `OTP_INVALID`, …) or
  /// one of the local codes below.
  final String code;
  final String message;

  /// The error's `details`, where the server sends them
  /// (`attemptsLeft`, `retryAfterSeconds`, …).
  final Map<String, Object?> details;

  /// No connection, a timeout, or a request cut off.
  static const String network = 'NETWORK';

  /// A body that was not the server's envelope.
  static const String badResponse = 'BAD_RESPONSE';

  /// No session, or one the server ended: the user has to sign in.
  static const String signInRequired = 'SIGN_IN_REQUIRED';

  /// A whole number from [details], or null.
  int? detailInt(String key) {
    final value = details[key];
    return value is num ? value.toInt() : null;
  }

  @override
  String toString() =>
      'SlimshotApiException($code${message.isEmpty ? '' : ': $message'})';
}
```

Replace the whole `SlimshotApi` class with:

```dart
/// The app's one client for SlimShot's own server.
///
/// Three kinds of request. **Signed in** ([send]): the access token as a
/// bearer, refreshed once when it has expired. **Sign-in** ([sendWithDevice]):
/// no bearer — the install token travels in the body, so the server can tie
/// the install to the account. **Public** ([sendPublic]): neither, for the
/// refresh and logout calls that carry their own token.
class SlimshotApi {
  SlimshotApi({
    required String baseUrl,
    required AccountSession session,
    http.Client? client,
    DeviceTokenStore tokens = const SecureDeviceTokenStore(),
  })  : _base = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client(),
        _session = session,
        _tokens = tokens;

  /// The server this build talks to: `--dart-define=SLIMSHOT_API_URL=…`.
  /// Empty when the build carries none.
  static const String configuredBaseUrl =
      String.fromEnvironment('SLIMSHOT_API_URL');

  /// Whether this build has a server at all. Server features are offered
  /// only then — they are not offered before they work.
  static bool get isConfigured => configuredBaseUrl.isNotEmpty;

  static const Duration defaultTimeout = Duration(seconds: 20);

  final String _base;
  final http.Client _client;
  final AccountSession _session;
  final DeviceTokenStore _tokens;

  Uri uri(String path) => Uri.parse('$_base/api/app/v1$path');

  /// A JSON request to [path].
  http.Request jsonRequest(
    String method,
    String path,
    Map<String, Object?> body,
  ) =>
      http.Request(method, uri(path))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);

  /// Sends the request [build] makes as the signed-in user and returns the
  /// envelope's `data`.
  ///
  /// An access token lasts minutes. Expired, it is exchanged once — through
  /// the session, so requests refused together share one exchange — and the
  /// request is built again: a request can be sent only once, and a
  /// multipart body is a stream. No session, any other refusal, or a second
  /// refusal ends in [SlimshotApiException.signInRequired]: a request that
  /// cannot be made as anyone is the sign-in sheet's cue, never a loop.
  Future<Map<String, dynamic>> send(
    http.BaseRequest Function() build, {
    Duration timeout = defaultTimeout,
  }) async {
    final tokens = await _session.read();
    if (tokens == null) {
      throw const SlimshotApiException(SlimshotApiException.signInRequired);
    }
    var response =
        await _perform(_authorised(build(), tokens.accessToken), timeout);
    if (response.statusCode != HttpStatus.unauthorized) {
      return _decode(response);
    }
    final fresh = _errorCode(response) == 'UNAUTHENTICATED'
        ? await _session.refreshAfter(
            tokens.accessToken,
            (refreshToken) => _exchange(refreshToken, timeout),
          )
        : null;
    if (fresh != null) {
      response =
          await _perform(_authorised(build(), fresh.accessToken), timeout);
      if (response.statusCode != HttpStatus.unauthorized) {
        return _decode(response);
      }
    }
    await _session.end();
    throw const SlimshotApiException(SlimshotApiException.signInRequired);
  }

  /// Sends a request that needs no sign-in and carries no install token.
  Future<Map<String, dynamic>> sendPublic(
    http.BaseRequest Function() build, {
    Duration timeout = defaultTimeout,
  }) async =>
      _decode(await _perform(build(), timeout));

  /// POSTs [body] as JSON with this install's token added as `deviceToken` —
  /// how a sign-in names the phone. A token the server no longer knows (a
  /// reset database) is replaced once and the request sent again.
  Future<Map<String, dynamic>> sendWithDevice(
    String path,
    Map<String, Object?> body, {
    Duration timeout = defaultTimeout,
  }) async {
    Future<http.Response> post(String deviceToken) => _perform(
          jsonRequest('POST', path, {...body, 'deviceToken': deviceToken}),
          timeout,
        );
    var response = await post(await deviceToken(timeout: timeout));
    if (_errorCode(response) == 'DEVICE_NOT_REGISTERED') {
      await _tokens.clear();
      response = await post(await _register(timeout));
    }
    return _decode(response);
  }

  /// This install's token, registering the install the first time.
  Future<String> deviceToken({Duration timeout = defaultTimeout}) async =>
      await _tokens.read() ?? await _register(timeout);

  /// Aborts anything in flight — how Cancel stops an upload.
  void close() => _client.close();

  http.BaseRequest _authorised(http.BaseRequest request, String token) {
    request.headers['Authorization'] = 'Bearer $token';
    return request;
  }

  /// A refresh token traded for new tokens.
  ///
  /// Refused (401): the token is spent, revoked or unknown — null, and the
  /// session ends. Anything else that is not an answer — a server error, a
  /// proxy's page — says nothing about the session, so it is thrown and the
  /// session kept.
  Future<SessionTokens?> _exchange(String refreshToken, Duration timeout) async {
    final response = await _perform(
      jsonRequest('POST', '/auth/refresh', {'refreshToken': refreshToken}),
      timeout,
    );
    if (response.statusCode == HttpStatus.unauthorized) return null;
    final data = _decode(response);
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    if (access is! String || refresh is! String) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No session.',
      );
    }
    return SessionTokens(accessToken: access, refreshToken: refresh);
  }

  Future<String> _register(Duration timeout) async {
    final data = _decode(await _perform(
      jsonRequest('POST', '/devices', {'platform': 'android'}),
      timeout,
    ));
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No device token.',
      );
    }
    await _tokens.write(token);
    return token;
  }

  Future<http.Response> _perform(
    http.BaseRequest request,
    Duration timeout,
  ) async {
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const SlimshotApiException(
        SlimshotApiException.network,
        'Timed out.',
      );
    } on SocketException catch (e) {
      throw SlimshotApiException(SlimshotApiException.network, e.message);
    } on http.ClientException catch (e) {
      throw SlimshotApiException(SlimshotApiException.network, e.message);
    }
  }

  static Object? _body(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  static String? _errorCode(http.Response response) {
    final body = _body(response);
    if (body is Map && body['error'] is Map) {
      final code = (body['error'] as Map)['code'];
      return code is String ? code : null;
    }
    return null;
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = _body(response);
    if (body is Map && body['success'] == true && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map && body['error'] is Map) {
      final error = body['error'] as Map;
      final code = error['code'];
      final message = error['message'];
      final details = error['details'];
      throw SlimshotApiException(
        code is String ? code : 'HTTP_${response.statusCode}',
        message is String ? message : '',
        details is Map ? Map<String, Object?>.from(details) : const {},
      );
    }
    throw SlimshotApiException(
      SlimshotApiException.badResponse,
      'HTTP ${response.statusCode}',
    );
  }
}
```

In `lib/screens/video_editor_screen.dart`, change line 1107
`final api = SlimshotApi(baseUrl: SlimshotApi.configuredBaseUrl);`
to
`final api = SlimshotApi(baseUrl: SlimshotApi.configuredBaseUrl, session: AccountSession());`
and add `import '../core/services/account_session.dart';` with the other `../core/services/` imports. (Temporary: Task 10 replaces it with the app's shared session.)

- [ ] **Step 5: Run the tests to see them pass**

Run: `flutter test test/core/services/ test/features/video_editor/services/`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/slimshot_api.dart lib/screens/video_editor_screen.dart test/support/account_fakes.dart test/core/services/slimshot_api_test.dart test/features/video_editor/services/caption_service_test.dart
git commit -m "feat(account): signed-in, sign-in and public requests in the server client

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The account endpoints, and every line the user reads

**Files:**
- Create: `lib/features/account/models/account_models.dart`
- Create: `lib/features/account/logic/account_copy.dart`
- Create: `lib/features/account/logic/username_rules.dart`
- Create: `lib/features/account/services/account_service.dart`
- Create: `test/support/fake_server.dart`
- Create: `test/features/account/services/account_service_test.dart`
- Create: `test/features/account/logic/account_copy_test.dart`
- Create: `test/features/account/logic/username_rules_test.dart`

**Interfaces:**
- Consumes: `SlimshotApi.send/sendPublic/sendWithDevice/jsonRequest/uri`, `SlimshotApiException` (Task 3); `SessionTokens` (Task 2).
- Produces: `AccountUser {id, email, String? username, referralCode, int creditBalance, bool suspended, bool needsClaim; fromJson; toJson}`; `SignInResult {SessionTokens tokens, AccountUser user; fromJson}`; `EmailCodeSent {String sentTo, Duration resendAfter}`; `UsernameAvailability {bool available, String? reason}`; `ClaimResult {AccountUser user, int bonusCredits, String? bonusReason, String? referralOutcome, int referralCredits, int get creditsGranted}`.
- Produces: `AccountService(SlimshotApi api)` with `signInWithGoogle(String idToken) → Future<SignInResult>`, `startEmail(String email) → Future<EmailCodeSent>`, `verifyEmail(String email, String code) → Future<SignInResult>`, `me() → Future<AccountUser>`, `usernameAvailability(String name) → Future<UsernameAvailability>`, `changeUsername(String name) → Future<AccountUser>`, `claim({required String username, String? referralCode}) → Future<ClaimResult>`, `logout(String refreshToken) → Future<void>`, `deleteAccount() → Future<void>`.
- Produces: `accountErrorMessage(Object error) → String`, `usernameReasonMessage(String? reason) → String`, `claimResultLines(ClaimResult) → List<String>`, `const kUsernameRule`, `const kGoogleSignInFailed = 'GOOGLE_SIGN_IN_FAILED'`.
- Produces: `bool isValidUsername(String)`, `List<TextInputFormatter> get usernameInputFormatters`, `const Duration kUsernameCheckDelay = Duration(milliseconds: 300)`.
- Produces in test support: `FakeServer` (`client`, `requests`, `on(method, path, answer)`, `to(method, path)`, `lastBody(method, path)`), `envelope`, `failure`, `userJson`, `signInJson`, `fakeApi(FakeServer, {AccountSession? session, DeviceTokenStore? devices})`.

- [ ] **Step 1: Write the fake server**

Create `test/support/fake_server.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';

import 'account_fakes.dart';

http.Response envelope(Object data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status);

http.Response failure(
  String code,
  int status, {
  Map<String, Object?>? details,
}) =>
    http.Response(
      jsonEncode({
        'success': false,
        'error': {
          'code': code,
          'message': 'm',
          if (details != null) 'details': details,
          'traceId': 't',
        },
      }),
      status,
    );

/// The server, answering by method and path, and remembering every request.
/// A route nobody set answers 404 NOT_FOUND.
class FakeServer {
  final List<http.Request> requests = [];
  final Map<String, FutureOr<http.Response> Function(http.Request)> _routes =
      {};

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    final answer = _routes['${request.method} ${request.url.path}'];
    if (answer == null) return failure('NOT_FOUND', 404);
    return await answer(request);
  });

  /// Answers `METHOD /api/app/v1[path]`.
  void on(
    String method,
    String path,
    FutureOr<http.Response> Function(http.Request request) answer,
  ) {
    _routes['$method /api/app/v1$path'] = answer;
  }

  Iterable<http.Request> to(String method, String path) => requests.where(
        (r) => r.method == method && r.url.path == '/api/app/v1$path',
      );

  Map<String, dynamic> lastBody(String method, String path) =>
      jsonDecode(to(method, path).last.body) as Map<String, dynamic>;
}

Map<String, Object?> userJson({
  String username = 'ann_1',
  int balance = 100,
  bool needsClaim = false,
  String status = 'active',
}) =>
    {
      'id': 'u1',
      'email': 'ann@example.com',
      'username': needsClaim ? null : username,
      'referralCode': 'AB3DEF7K',
      'creditBalance': balance,
      'accountStatus': status,
      'needsClaim': needsClaim,
      'signInMethods': {'google': false, 'email': true},
      'ads': {'rewardCredits': 5, 'dailyCap': 10, 'remainingToday': 10},
    };

Map<String, Object?> signInJson({
  bool needsClaim = false,
  String access = 'a1',
  String refresh = 'r1',
}) =>
    {
      'accessToken': access,
      'refreshToken': refresh,
      'expiresIn': 900,
      'isNewAccount': needsClaim,
      'needsClaim': needsClaim,
      'user': userJson(needsClaim: needsClaim, balance: needsClaim ? 0 : 100),
    };

/// A client on [server], with an install already registered as `dev-1`.
SlimshotApi fakeApi(
  FakeServer server, {
  AccountSession? session,
  DeviceTokenStore? devices,
}) =>
    SlimshotApi(
      baseUrl: 'https://api.test',
      client: server.client,
      session: session ?? AccountSession(vault: MemoryTokenVault()),
      tokens: devices ?? MemoryDeviceTokens('dev-1'),
    );
```

- [ ] **Step 2: Write the failing tests**

Create `test/features/account/services/account_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/account/services/account_service.dart';

import '../../../support/account_fakes.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  AccountService service({bool signedIn = false}) => AccountService(
        fakeApi(
          server,
          session: signedIn ? signedInSession(access: 'a1', refresh: 'r1') : null,
        ),
      );

  test('Google sign-in sends the ID token and the install', () async {
    server.on('POST', '/auth/google', (_) => envelope(signInJson()));
    final result = await service().signInWithGoogle('id-1');

    expect(server.lastBody('POST', '/auth/google'), {
      'idToken': 'id-1',
      'deviceToken': 'dev-1',
    });
    expect(result.tokens.accessToken, 'a1');
    expect(result.tokens.refreshToken, 'r1');
    expect(result.user.username, 'ann_1');
  });

  test('an email code is asked for, then checked', () async {
    server
      ..on(
        'POST',
        '/auth/email/start',
        (_) => envelope({
          'sentTo': 'ann@example.com',
          'resendAfterSeconds': 60,
          'expiresInSeconds': 600,
        }),
      )
      ..on('POST', '/auth/email/verify', (_) => envelope(signInJson()));
    final accounts = service();

    final sent = await accounts.startEmail('ann@example.com');
    expect(sent.sentTo, 'ann@example.com');
    expect(sent.resendAfter, const Duration(seconds: 60));

    final result = await accounts.verifyEmail('ann@example.com', '123456');
    expect(server.lastBody('POST', '/auth/email/verify'), {
      'email': 'ann@example.com',
      'code': '123456',
      'deviceToken': 'dev-1',
    });
    expect(result.user.email, 'ann@example.com');
  });

  test('a sign-in answer without a session is BAD_RESPONSE', () async {
    server.on('POST', '/auth/google', (_) => envelope({'user': userJson()}));
    await expectLater(
      service().signInWithGoogle('id-1'),
      throwsA(isA<SlimshotApiException>()
          .having((e) => e.code, 'code', SlimshotApiException.badResponse)),
    );
  });

  test('the profile is read signed in', () async {
    server.on('GET', '/me', (_) => envelope(userJson(balance: 94)));
    final user = await service(signedIn: true).me();

    expect(server.to('GET', '/me').single.headers['Authorization'], 'Bearer a1');
    expect(user.creditBalance, 94);
    expect(user.referralCode, 'AB3DEF7K');
    expect(user.suspended, isFalse);
    expect(user.needsClaim, isFalse);
  });

  test('a suspended account reads as suspended', () async {
    server.on('GET', '/me', (_) => envelope(userJson(status: 'suspended')));
    expect((await service(signedIn: true).me()).suspended, isTrue);
  });

  test('availability asks about exactly the name typed', () async {
    server.on(
      'GET',
      '/usernames/ann_1/availability',
      (_) => envelope({'username': 'ann_1', 'available': false, 'reason': 'TAKEN'}),
    );
    final answer = await service(signedIn: true).usernameAvailability('ann_1');
    expect(answer.available, isFalse);
    expect(answer.reason, 'TAKEN');
  });

  test('a username change says what was asked', () async {
    server.on('PATCH', '/me/username', (_) => envelope(userJson(username: 'new_name')));
    final user = await service(signedIn: true).changeUsername('new_name');
    expect(server.lastBody('PATCH', '/me/username'), {'username': 'new_name'});
    expect(user.username, 'new_name');
  });

  test('a claim without a code sends no code, and reports the bonus', () async {
    server.on(
      'POST',
      '/me/claim',
      (_) => envelope({
        'user': userJson(),
        'bonus': {'granted': true, 'credits': 100},
        'referral': null,
      }),
    );
    final result = await service(signedIn: true).claim(username: 'ann_1');

    expect(server.lastBody('POST', '/me/claim'), {'username': 'ann_1'});
    expect(result.bonusCredits, 100);
    expect(result.referralOutcome, isNull);
    expect(result.creditsGranted, 100);
  });

  test('a claim with a code sends it, and reports the referral', () async {
    server.on(
      'POST',
      '/me/claim',
      (_) => envelope({
        'user': userJson(balance: 120),
        'bonus': {'granted': true, 'credits': 100},
        'referral': {'outcome': 'rewarded', 'credits': 20},
      }),
    );
    final result = await service(signedIn: true)
        .claim(username: 'ann_1', referralCode: 'AB3DEF7K');

    expect(server.lastBody('POST', '/me/claim'), {
      'username': 'ann_1',
      'referralCode': 'AB3DEF7K',
    });
    expect(result.referralOutcome, 'rewarded');
    expect(result.creditsGranted, 120);
  });

  test('a claim without a bonus says why', () async {
    server.on(
      'POST',
      '/me/claim',
      (_) => envelope({
        'user': userJson(balance: 0),
        'bonus': {'granted': false, 'reason': 'BONUS_ALREADY_CLAIMED'},
        'referral': null,
      }),
    );
    final result = await service(signedIn: true).claim(username: 'ann_1');
    expect(result.bonusCredits, 0);
    expect(result.bonusReason, 'BONUS_ALREADY_CLAIMED');
  });

  test('logout sends the refresh token, without a bearer', () async {
    server.on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    await service(signedIn: true).logout('r1');
    final request = server.to('POST', '/auth/logout').single;
    expect(server.lastBody('POST', '/auth/logout'), {'refreshToken': 'r1'});
    expect(request.headers['Authorization'], isNull);
  });

  test('deleting the account confirms in the body', () async {
    server.on('DELETE', '/me', (_) => envelope({'deleted': true}));
    await service(signedIn: true).deleteAccount();
    final request = server.to('DELETE', '/me').single;
    expect(server.lastBody('DELETE', '/me'), {'confirm': 'DELETE'});
    expect(request.headers['Content-Type'], startsWith('application/json'));
    expect(request.headers['Authorization'], 'Bearer a1');
  });

  test('a profile survives a round trip through JSON', () {
    final user = AccountUser.fromJson(userJson(status: 'suspended'));
    final again = AccountUser.fromJson(user.toJson());
    expect(again.id, user.id);
    expect(again.email, user.email);
    expect(again.username, user.username);
    expect(again.referralCode, user.referralCode);
    expect(again.creditBalance, user.creditBalance);
    expect(again.suspended, isTrue);
    expect(again.needsClaim, user.needsClaim);
  });
}
```

Create `test/features/account/logic/account_copy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/account/logic/account_copy.dart';
import 'package:slimshotai/features/account/models/account_models.dart';

import '../../../support/fake_server.dart';

void main() {
  test('every account error has its one line', () {
    const expected = {
      SlimshotApiException.network:
          'No connection. Check your internet and try again.',
      'GOOGLE_TOKEN_INVALID': "Google sign-in didn't work. Try again.",
      kGoogleSignInFailed: "Google sign-in didn't work. Try again.",
      'GOOGLE_EMAIL_UNVERIFIED': 'Use your email instead.',
      'SIGN_IN_METHOD_UNAVAILABLE': 'Use your email instead.',
      'ACCOUNT_LINK_CONFLICT': 'This email uses a different Google account.',
      'EMAIL_DOMAIN_NOT_ALLOWED': 'Use a regular email address.',
      'OTP_EXPIRED': 'Code expired. Send a new one.',
      'OTP_ATTEMPTS_EXCEEDED': 'Code expired. Send a new one.',
      'USERNAME_INVALID': kUsernameRule,
      'USERNAME_TAKEN': 'Taken',
      'REFERRAL_CODE_INVALID': "That invite code doesn't work.",
      'ACCOUNT_SUSPENDED': 'This account is suspended.',
      SlimshotApiException.signInRequired: 'Sign in again.',
      'SOMETHING_NEW': 'Something went wrong. Try again.',
    };
    expected.forEach((code, line) {
      expect(accountErrorMessage(SlimshotApiException(code)), line, reason: code);
    });
    expect(accountErrorMessage(StateError('?')), 'Something went wrong. Try again.');
  });

  test('a wrong code says how many tries are left', () {
    String line(int? left) => accountErrorMessage(SlimshotApiException(
          'OTP_INVALID',
          '',
          left == null ? const {} : {'attemptsLeft': left},
        ));
    expect(line(3), 'Wrong code · 3 tries left');
    expect(line(1), 'Wrong code · 1 try left');
    expect(line(null), 'Wrong code.');
  });

  test('waiting says for how long', () {
    String line(String code, int? wait) => accountErrorMessage(
          SlimshotApiException(
            code,
            '',
            wait == null ? const {} : {'retryAfterSeconds': wait},
          ),
        );
    expect(line('OTP_RESEND_TOO_SOON', 42), 'Try again in 42s.');
    expect(line('RATE_LIMITED', 30), 'Try again in 30s.');
    expect(line('RATE_LIMITED', null), 'Too many tries. Wait a moment.');
  });

  test('why a name cannot be had', () {
    expect(usernameReasonMessage('TAKEN'), 'Taken');
    expect(usernameReasonMessage('RESERVED'), 'Not available');
    expect(usernameReasonMessage('INVALID'), kUsernameRule);
    expect(usernameReasonMessage(null), kUsernameRule);
  });

  ClaimResult claimed({
    int bonus = 0,
    String? reason,
    String? outcome,
    int referral = 0,
  }) =>
      ClaimResult(
        user: AccountUser.fromJson(userJson()),
        bonusCredits: bonus,
        bonusReason: reason,
        referralOutcome: outcome,
        referralCredits: referral,
      );

  test('a claim explains itself in at most one line', () {
    expect(claimResultLines(claimed(bonus: 100)), isEmpty);
    expect(
      claimResultLines(claimed(bonus: 100, outcome: 'rewarded', referral: 20)),
      ['Includes 20 from your invite'],
    );
    expect(
      claimResultLines(claimed(reason: 'BONUS_ALREADY_CLAIMED')),
      ['This email or phone has already had its free credits.'],
    );
    expect(
      claimResultLines(claimed(reason: 'IP_LIMIT_REACHED')),
      ["Free credits aren't available on this network today."],
    );
    expect(claimResultLines(claimed()), ['No free credits this time.']);
  });
}
```

Create `test/features/account/logic/username_rules_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/logic/username_rules.dart';

String typed(String text) {
  var value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  for (final formatter in usernameInputFormatters) {
    value = formatter.formatEditUpdate(TextEditingValue.empty, value);
  }
  return value.text;
}

void main() {
  test('3–20 of a–z, 0–9 and _', () {
    for (final ok in ['ann', 'ann_1', 'a1_', '___', 'a' * 20]) {
      expect(isValidUsername(ok), isTrue, reason: ok);
    }
    for (final bad in ['', 'an', 'a' * 21, 'Ann', 'ann-1', 'ann 1', 'añn']) {
      expect(isValidUsername(bad), isFalse, reason: bad);
    }
  });

  test('typing keeps only what a username may hold, in lower case', () {
    expect(typed('Ann_1'), 'ann_1');
    expect(typed('ann-1!'), 'ann1');
    expect(typed('a' * 25), 'a' * 20);
  });
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `flutter test test/features/account/`
Expected: FAIL — `account_models.dart`, `account_copy.dart`, `username_rules.dart`, `account_service.dart` not found.

- [ ] **Step 4: Write the models**

Create `lib/features/account/models/account_models.dart`:

```dart
import '../../../core/services/account_session.dart';
import '../../../core/services/slimshot_api.dart';

/// The signed-in user, as `/me` describes them.
class AccountUser {
  const AccountUser({
    required this.id,
    required this.email,
    required this.username,
    required this.referralCode,
    required this.creditBalance,
    required this.suspended,
    required this.needsClaim,
  });

  factory AccountUser.fromJson(Map<String, dynamic> json) => AccountUser(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        username: json['username'] as String?,
        referralCode: json['referralCode'] as String? ?? '',
        creditBalance: (json['creditBalance'] as num?)?.toInt() ?? 0,
        suspended: json['accountStatus'] == 'suspended',
        needsClaim: json['needsClaim'] as bool? ?? false,
      );

  final String id;
  final String email;

  /// Null until the claim step has chosen one.
  final String? username;

  /// The user's own code to share — not the username.
  final String referralCode;

  /// Whole credits; never below zero.
  final int creditBalance;

  /// A suspended account can sign in and look, but not spend or claim.
  final bool suspended;

  /// A new account that has not chosen a username and claimed yet.
  final bool needsClaim;

  Map<String, Object?> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'referralCode': referralCode,
        'creditBalance': creditBalance,
        'accountStatus': suspended ? 'suspended' : 'active',
        'needsClaim': needsClaim,
      };
}

Map<String, dynamic> _object(Object? value, String what) {
  if (value is Map) return Map<String, dynamic>.from(value);
  throw SlimshotApiException(SlimshotApiException.badResponse, 'No $what.');
}

/// What a successful sign-in answers: the session and the user.
class SignInResult {
  const SignInResult({required this.tokens, required this.user});

  factory SignInResult.fromJson(Map<String, dynamic> json) {
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No session.',
      );
    }
    return SignInResult(
      tokens: SessionTokens(accessToken: access, refreshToken: refresh),
      user: AccountUser.fromJson(_object(json['user'], 'user')),
    );
  }

  final SessionTokens tokens;
  final AccountUser user;
}

/// An emailed code is on its way.
class EmailCodeSent {
  const EmailCodeSent({required this.sentTo, required this.resendAfter});

  factory EmailCodeSent.fromJson(Map<String, dynamic> json) => EmailCodeSent(
        sentTo: json['sentTo'] as String? ?? '',
        resendAfter: Duration(
          seconds: (json['resendAfterSeconds'] as num?)?.toInt() ?? 60,
        ),
      );

  final String sentTo;

  /// How long before another code may be asked for.
  final Duration resendAfter;
}

/// Whether a username can be had, and if not, why.
class UsernameAvailability {
  const UsernameAvailability({required this.available, this.reason});

  factory UsernameAvailability.fromJson(Map<String, dynamic> json) =>
      UsernameAvailability(
        available: json['available'] == true,
        reason: json['reason'] as String?,
      );

  final bool available;

  /// `INVALID`, `RESERVED` or `TAKEN` when not available.
  final String? reason;
}

/// What the claim step granted, and why when it granted nothing.
class ClaimResult {
  const ClaimResult({
    required this.user,
    required this.bonusCredits,
    this.bonusReason,
    this.referralOutcome,
    this.referralCredits = 0,
  });

  factory ClaimResult.fromJson(Map<String, dynamic> json) {
    final bonus = json['bonus'] is Map
        ? Map<String, dynamic>.from(json['bonus'] as Map)
        : const <String, dynamic>{};
    final referral = json['referral'] is Map
        ? Map<String, dynamic>.from(json['referral'] as Map)
        : null;
    return ClaimResult(
      user: AccountUser.fromJson(_object(json['user'], 'user')),
      bonusCredits: bonus['granted'] == true
          ? (bonus['credits'] as num?)?.toInt() ?? 0
          : 0,
      bonusReason: bonus['reason'] as String?,
      referralOutcome: referral?['outcome'] as String?,
      referralCredits: (referral?['credits'] as num?)?.toInt() ?? 0,
    );
  }

  final AccountUser user;

  /// The signup bonus granted; 0 when it was not.
  final int bonusCredits;

  /// Why the bonus was not granted: `BONUS_ALREADY_CLAIMED` or
  /// `IP_LIMIT_REACHED`.
  final String? bonusReason;

  /// `rewarded`, `inviter_capped` or `invitee_ineligible`; null without a
  /// code.
  final String? referralOutcome;

  /// The invite credits this user got.
  final int referralCredits;

  int get creditsGranted => bonusCredits + referralCredits;
}
```

- [ ] **Step 5: Write the copy and the username rules**

Create `lib/features/account/logic/account_copy.dart`:

```dart
import '../../../core/services/slimshot_api.dart';
import '../models/account_models.dart';

/// Google's picker failed for a reason other than the user closing it. A
/// local code, never the server's.
const String kGoogleSignInFailed = 'GOOGLE_SIGN_IN_FAILED';

/// The username rule, in the words the field shows.
const String kUsernameRule = '3–20 letters, numbers or _';

/// The one line the user sees for an account [error] — no title, no code.
String accountErrorMessage(Object error) {
  if (error is! SlimshotApiException) return 'Something went wrong. Try again.';
  return switch (error.code) {
    SlimshotApiException.network =>
      'No connection. Check your internet and try again.',
    'GOOGLE_TOKEN_INVALID' || kGoogleSignInFailed =>
      "Google sign-in didn't work. Try again.",
    'GOOGLE_EMAIL_UNVERIFIED' || 'SIGN_IN_METHOD_UNAVAILABLE' =>
      'Use your email instead.',
    'ACCOUNT_LINK_CONFLICT' => 'This email uses a different Google account.',
    'EMAIL_DOMAIN_NOT_ALLOWED' => 'Use a regular email address.',
    'OTP_INVALID' => _wrongCode(error.detailInt('attemptsLeft')),
    'OTP_EXPIRED' || 'OTP_ATTEMPTS_EXCEEDED' => 'Code expired. Send a new one.',
    'OTP_RESEND_TOO_SOON' || 'RATE_LIMITED' =>
      _wait(error.detailInt('retryAfterSeconds')),
    'USERNAME_INVALID' => kUsernameRule,
    'USERNAME_TAKEN' => 'Taken',
    'REFERRAL_CODE_INVALID' => "That invite code doesn't work.",
    'ACCOUNT_SUSPENDED' => 'This account is suspended.',
    SlimshotApiException.signInRequired => 'Sign in again.',
    _ => 'Something went wrong. Try again.',
  };
}

String _wrongCode(int? left) => left == null
    ? 'Wrong code.'
    : 'Wrong code · $left ${left == 1 ? 'try' : 'tries'} left';

String _wait(int? seconds) => seconds == null
    ? 'Too many tries. Wait a moment.'
    : 'Try again in ${seconds}s.';

/// Why a name cannot be had, from the availability answer's reason.
String usernameReasonMessage(String? reason) => switch (reason) {
      'TAKEN' => 'Taken',
      'RESERVED' => 'Not available',
      _ => kUsernameRule,
    };

/// The lines under a claim's headline: where invite credits came from, or
/// honestly why there were no free credits.
List<String> claimResultLines(ClaimResult result) => [
      if (result.bonusCredits > 0 && result.referralCredits > 0)
        'Includes ${result.referralCredits} from your invite',
      if (result.bonusCredits == 0)
        switch (result.bonusReason) {
          'BONUS_ALREADY_CLAIMED' =>
            'This email or phone has already had its free credits.',
          'IP_LIMIT_REACHED' =>
            "Free credits aren't available on this network today.",
          _ => 'No free credits this time.',
        },
    ];
```

Create `lib/features/account/logic/username_rules.dart`:

```dart
import 'package:flutter/services.dart';

/// How long typing must pause before the server is asked whether a name is
/// free. The server allows 60 checks a minute.
const Duration kUsernameCheckDelay = Duration(milliseconds: 300);

final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

/// 3–20 characters of `a–z`, `0–9` and `_` — the server's rule. The server
/// also reserves some names; only it can say which.
bool isValidUsername(String name) => _usernamePattern.hasMatch(name);

/// Keeps a username field to what a username may hold, in lower case — the
/// server stores names lowercased, so the field shows what will be kept.
List<TextInputFormatter> get usernameInputFormatters => [
      FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]')),
      LengthLimitingTextInputFormatter(20),
      const _LowerCase(),
    ];

class _LowerCase extends TextInputFormatter {
  const _LowerCase();

  // ASCII only reaches here, so lowercasing keeps the length — and with it
  // the cursor.
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.copyWith(text: newValue.text.toLowerCase());
}
```

- [ ] **Step 6: Write the service**

Create `lib/features/account/services/account_service.dart`:

```dart
import 'package:http/http.dart' as http;

import '../../../core/services/slimshot_api.dart';
import '../models/account_models.dart';

/// The account endpoints, one method each — requests and answers, no UI and
/// no state. `slimshot_server/docs/app-credits-api.md` is the contract.
class AccountService {
  AccountService(this._api);

  final SlimshotApi _api;

  Future<SignInResult> signInWithGoogle(String idToken) async =>
      SignInResult.fromJson(
        await _api.sendWithDevice('/auth/google', {'idToken': idToken}),
      );

  Future<EmailCodeSent> startEmail(String email) async =>
      EmailCodeSent.fromJson(
        await _api.sendWithDevice('/auth/email/start', {'email': email}),
      );

  Future<SignInResult> verifyEmail(String email, String code) async =>
      SignInResult.fromJson(
        await _api.sendWithDevice(
          '/auth/email/verify',
          {'email': email, 'code': code},
        ),
      );

  Future<AccountUser> me() async => AccountUser.fromJson(
        await _api.send(() => http.Request('GET', _api.uri('/me'))),
      );

  Future<UsernameAvailability> usernameAvailability(String name) async =>
      UsernameAvailability.fromJson(
        await _api.send(
          () => http.Request(
            'GET',
            _api.uri('/usernames/${Uri.encodeComponent(name)}/availability'),
          ),
        ),
      );

  Future<AccountUser> changeUsername(String name) async =>
      AccountUser.fromJson(
        await _api.send(
          () => _api.jsonRequest('PATCH', '/me/username', {'username': name}),
        ),
      );

  Future<ClaimResult> claim({
    required String username,
    String? referralCode,
  }) async =>
      ClaimResult.fromJson(
        await _api.send(
          () => _api.jsonRequest('POST', '/me/claim', {
            'username': username,
            if (referralCode != null) 'referralCode': referralCode,
          }),
        ),
      );

  Future<void> logout(String refreshToken) async {
    await _api.sendPublic(
      () => _api.jsonRequest(
        'POST',
        '/auth/logout',
        {'refreshToken': refreshToken},
      ),
    );
  }

  /// The server wants the confirmation in the body; the app's own confirm
  /// sheet comes first.
  Future<void> deleteAccount() async {
    await _api.send(
      () => _api.jsonRequest('DELETE', '/me', {'confirm': 'DELETE'}),
    );
  }
}
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `flutter test test/features/account/`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/account test/support/fake_server.dart test/features/account
git commit -m "feat(account): account endpoints, models and the words the user reads

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The signed-in state, and Google's account picker

**Files:**
- Modify: `pubspec.yaml` (`google_sign_in`)
- Create: `lib/features/account/services/google_id_tokens.dart`
- Create: `lib/features/account/providers/account_providers.dart`
- Create: `test/support/account_harness.dart`
- Create: `test/features/account/providers/account_notifier_test.dart`

**Interfaces:**
- Consumes: `AccountSession` (Task 2); `SlimshotApi` (Task 3); `AccountService`, models, `kGoogleSignInFailed` (Task 4).
- Produces: `abstract class GoogleIdTokens { bool get isAvailable; Future<String?> requestIdToken(); Future<void> signOut(); }`; `class PluginGoogleIdTokens implements GoogleIdTokens`.
- Produces: providers `accountFeatureProvider` (`Provider<bool>`), `accountSessionProvider` (`Provider<AccountSession>`), `accountApiProvider` (`Provider<SlimshotApi>`), `accountServiceProvider` (`Provider<AccountService>`), `googleIdTokensProvider` (`Provider<GoogleIdTokens>`), `accountProvider` (`StateNotifierProvider<AccountNotifier, AccountState>`).
- Produces: `class AccountState { const AccountState({AccountUser? user}); final AccountUser? user; bool get isSignedIn; bool get needsClaim; }`; `AccountNotifier` with `restore()`, `refresh()`, `completeSignIn(SignInResult)`, `claim({required String username, String? referralCode}) → Future<ClaimResult>`, `changeUsername(String)`, `signOut()`, `deleteAccount()`.
- Produces in test support: `FakeGoogleIdTokens`, `List<Override> accountOverrides(FakeServer server, {AccountSession? session, GoogleIdTokens? google})`, `Future<List<Object?>> pumpHost(WidgetTester, List<Override>, Future<Object?> Function(BuildContext, WidgetRef))`, `Future<void> settle(WidgetTester)`, `ProviderContainer containerOf(WidgetTester)`.

- [ ] **Step 1: Add the dependency and check its API**

In `pubspec.yaml`, after the `flutter_secure_storage` lines from Task 1, add:

```yaml
  # Sign in with Google: the account picker (Credential Manager), no browser.
  google_sign_in: ^7.2.0
```

Run: `flutter pub get`
Expected: `google_sign_in 7.2.0` added.

Check the one API detail this task relies on:

Run: `grep -n "authentication" "$LOCALAPPDATA/Pub/Cache/hosted/pub.dev/google_sign_in-7.2.0/lib/google_sign_in.dart"` (PowerShell: `Select-String -Path "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\google_sign_in-7.2.0\lib\google_sign_in.dart" -Pattern authentication`)
Expected: `GoogleSignInAuthentication get authentication` — synchronous. If it is declared as returning `Future<GoogleSignInAuthentication>`, write `(await account.authentication).idToken` in Step 5 instead of `account.authentication.idToken`, and ledger the ruling.

- [ ] **Step 2: Write the test harness**

Create `test/support/account_harness.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/account/services/google_id_tokens.dart';

import 'account_fakes.dart';
import 'fake_server.dart';

/// Google's picker, scripted: [idToken] null is the user closing it.
class FakeGoogleIdTokens implements GoogleIdTokens {
  FakeGoogleIdTokens({this.isAvailable = true, this.idToken = 'google-id-token'});

  @override
  final bool isAvailable;
  String? idToken;
  Object? error;
  int requests = 0;
  int signOuts = 0;

  @override
  Future<String?> requestIdToken() async {
    requests++;
    final failure = error;
    if (failure != null) throw failure;
    return idToken;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
  }
}

/// Accounts switched on, against [server], with [session] (signed out when
/// omitted) and a scripted Google.
List<Override> accountOverrides(
  FakeServer server, {
  AccountSession? session,
  GoogleIdTokens? google,
}) {
  final shared = session ?? AccountSession(vault: MemoryTokenVault());
  return [
    accountFeatureProvider.overrideWithValue(true),
    accountSessionProvider.overrideWithValue(shared),
    accountApiProvider.overrideWithValue(fakeApi(server, session: shared)),
    googleIdTokensProvider.overrideWithValue(google ?? FakeGoogleIdTokens()),
  ];
}

/// A screen with one button, "open", that runs [open] and records what it
/// returned.
Future<List<Object?>> pumpHost(
  WidgetTester tester,
  List<Override> overrides,
  Future<Object?> Function(BuildContext context, WidgetRef ref) open,
) async {
  final results = <Object?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: ElevatedButton(
                onPressed: () async => results.add(await open(context, ref)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return results;
}

/// Past a sheet's motion and any answer already queued. Never
/// `pumpAndSettle`: a busy button holds a spinner that never settles.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
```

- [ ] **Step 3: Write the failing tests**

Create `test/features/account/providers/account_notifier_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';

import '../../../support/account_fakes.dart';
import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  ProviderContainer containerWith({
    AccountSession? session,
    FakeGoogleIdTokens? google,
  }) {
    final container = ProviderContainer(
      overrides: accountOverrides(server, session: session, google: google),
    );
    addTearDown(container.dispose);
    return container;
  }

  test('with no session the app is signed out and asks nothing', () async {
    final c = containerWith();
    expect(c.read(accountProvider).isSignedIn, isFalse);
    await pumpEventQueue();
    expect(server.requests, isEmpty);
  });

  test("a kept session shows the last profile at once, then the server's",
      () async {
    final answer = Completer<http.Response>();
    server.on('GET', '/me', (_) => answer.future);
    final c = containerWith(session: signedInSession(profile: userJson(balance: 100)));

    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).user!.creditBalance, 100);

    answer.complete(envelope(userJson(balance: 80)));
    await pumpEventQueue();
    expect(c.read(accountProvider).user!.creditBalance, 80);
  });

  test('offline, the last profile stays', () async {
    server.on('GET', '/me', (_) => throw http.ClientException('offline'));
    final c = containerWith(session: signedInSession(profile: userJson(balance: 100)));
    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).user!.creditBalance, 100);
  });

  test('a profile another build wrote waits for the server, never fails',
      () async {
    final session = signedInSession();
    await session.saveProfile('{not json');
    server.on('GET', '/me', (_) => envelope(userJson(balance: 7)));
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).user!.creditBalance, 7);
  });

  test('a session ended anywhere signs the whole app out', () async {
    server.on('GET', '/me', (_) => envelope(userJson()));
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).isSignedIn, isTrue);

    await session.end(); // say, a caption upload refused with SIGN_IN_REQUIRED
    await pumpEventQueue();
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });

  test('a server that no longer knows the session signs the app out',
      () async {
    server.on('GET', '/me', (_) => failure('SIGN_IN_REQUIRED', 401));
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).isSignedIn, isFalse);
    expect(await session.readProfile(), isNull);
  });

  test('signing in keeps the session and the profile', () async {
    final session = AccountSession(vault: MemoryTokenVault());
    final c = containerWith(session: session);
    await c
        .read(accountProvider.notifier)
        .completeSignIn(SignInResult.fromJson(signInJson()));

    expect((await session.read())!.accessToken, 'a1');
    expect(await session.readProfile(), contains('ann@example.com'));
    expect(c.read(accountProvider).user!.username, 'ann_1');
  });

  test('signing out tells the server, forgets everything and leaves Google',
      () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson()))
      ..on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    final google = FakeGoogleIdTokens();
    final session = signedInSession(refresh: 'r9', profile: userJson());
    final c = containerWith(session: session, google: google);
    c.read(accountProvider);
    await pumpEventQueue();

    await c.read(accountProvider.notifier).signOut();
    expect(server.lastBody('POST', '/auth/logout'), {'refreshToken': 'r9'});
    expect(await session.read(), isNull);
    expect(await session.readProfile(), isNull);
    expect(google.signOuts, 1);
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });

  test('signing out works with no connection', () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson()))
      ..on('POST', '/auth/logout', (_) => throw http.ClientException('offline'));
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();

    await c.read(accountProvider.notifier).signOut();
    expect(c.read(accountProvider).isSignedIn, isFalse);
    expect(await session.read(), isNull);
  });

  test('a profile that lands after signing out is not kept', () async {
    final late = Completer<http.Response>();
    server
      ..on('GET', '/me', (_) => late.future)
      ..on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider); // restore asks /me, which hangs
    await pumpEventQueue();

    await c.read(accountProvider.notifier).signOut();
    late.complete(envelope(userJson()));
    await pumpEventQueue();

    expect(await session.readProfile(), isNull);
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });

  test('deleting the account confirms it and forgets everything', () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson()))
      ..on('DELETE', '/me', (_) => envelope({'deleted': true}));
    final google = FakeGoogleIdTokens();
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session, google: google);
    c.read(accountProvider);
    await pumpEventQueue();

    await c.read(accountProvider.notifier).deleteAccount();
    expect(server.lastBody('DELETE', '/me'), {'confirm': 'DELETE'});
    expect(await session.read(), isNull);
    expect(google.signOuts, 1);
    expect(c.read(accountProvider).isSignedIn, isFalse);
  });

  test('a deletion the server refused keeps the account', () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson()))
      ..on('DELETE', '/me', (_) => failure('RATE_LIMITED', 429));
    final session = signedInSession(profile: userJson());
    final c = containerWith(session: session);
    c.read(accountProvider);
    await pumpEventQueue();

    await expectLater(
      c.read(accountProvider.notifier).deleteAccount(),
      throwsA(isA<SlimshotApiException>()),
    );
    expect(c.read(accountProvider).isSignedIn, isTrue);
    expect(await session.read(), isNotNull);
  });

  test('claiming adopts the claimed profile', () async {
    server
      ..on('GET', '/me', (_) => envelope(userJson(needsClaim: true, balance: 0)))
      ..on(
        'POST',
        '/me/claim',
        (_) => envelope({
          'user': userJson(balance: 100),
          'bonus': {'granted': true, 'credits': 100},
          'referral': null,
        }),
      );
    final c = containerWith(
      session: signedInSession(profile: userJson(needsClaim: true, balance: 0)),
    );
    c.read(accountProvider);
    await pumpEventQueue();
    expect(c.read(accountProvider).needsClaim, isTrue);

    final result = await c.read(accountProvider.notifier).claim(username: 'ann_1');
    expect(result.creditsGranted, 100);
    expect(c.read(accountProvider).needsClaim, isFalse);
    expect(c.read(accountProvider).user!.creditBalance, 100);
  });
}
```

- [ ] **Step 4: Run the tests to see them fail**

Run: `flutter test test/features/account/providers/account_notifier_test.dart`
Expected: FAIL — `account_providers.dart` and `google_id_tokens.dart` not found.

- [ ] **Step 5: Write Google's token source**

Create `lib/features/account/services/google_id_tokens.dart`:

```dart
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/services/slimshot_api.dart';
import '../logic/account_copy.dart';

/// Where a Google ID token for our server comes from. An interface so the
/// sign-in flow is tested without a phone.
abstract class GoogleIdTokens {
  /// Whether this build can offer Google at all.
  bool get isAvailable;

  /// An ID token for our server, or null when the user closed the picker.
  Future<String?> requestIdToken();

  /// Forgets the chosen Google account, so the next sign-in shows the picker
  /// again rather than signing straight back in.
  Future<void> signOut();
}

/// Google's account picker — on Android, Credential Manager: the accounts
/// already on the phone, no browser.
class PluginGoogleIdTokens implements GoogleIdTokens {
  /// The **Web** OAuth client ID the server checks the token's audience
  /// against: `--dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=…`. Not the Android
  /// client's — that one only vouches for the app's signature.
  static const String serverClientId =
      String.fromEnvironment('SLIMSHOT_GOOGLE_CLIENT_ID');

  /// `initialize` may be called once per app run.
  static Future<void>? _initialised;

  @override
  bool get isAvailable => serverClientId.isNotEmpty;

  Future<void> _initialise() => _initialised ??=
      GoogleSignIn.instance.initialize(serverClientId: serverClientId);

  @override
  Future<String?> requestIdToken() async {
    await _initialise();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const SlimshotApiException(kGoogleSignInFailed, 'No ID token.');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw SlimshotApiException(
        kGoogleSignInFailed,
        e.description ?? e.code.name,
      );
    }
  }

  @override
  Future<void> signOut() async {
    if (!isAvailable) return;
    try {
      await _initialise();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Leaving Google is a courtesy; our own session has already ended.
    }
  }
}
```

- [ ] **Step 6: Write the providers and the notifier**

Create `lib/features/account/providers/account_providers.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/account_session.dart';
import '../../../core/services/slimshot_api.dart';
import '../models/account_models.dart';
import '../services/account_service.dart';
import '../services/google_id_tokens.dart';

/// Accounts exist only in a build that has a server — the rule Auto captions
/// already follows: not offered before it works.
final accountFeatureProvider = Provider<bool>((ref) => SlimshotApi.isConfigured);

/// The one session on this phone. Every server client is built on it, so a
/// session ended by any request ends it everywhere.
final accountSessionProvider =
    Provider<AccountSession>((ref) => AccountSession());

final accountApiProvider = Provider<SlimshotApi>((ref) {
  final api = SlimshotApi(
    baseUrl: SlimshotApi.configuredBaseUrl,
    session: ref.watch(accountSessionProvider),
  );
  ref.onDispose(api.close);
  return api;
});

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(ref.watch(accountApiProvider)),
);

final googleIdTokensProvider =
    Provider<GoogleIdTokens>((ref) => PluginGoogleIdTokens());

/// Who is signed in. App-wide on purpose — not autoDispose — because the
/// home screen, Settings and the editor all show or check it.
final accountProvider =
    StateNotifierProvider<AccountNotifier, AccountState>((ref) {
  final notifier = AccountNotifier(
    service: ref.watch(accountServiceProvider),
    session: ref.watch(accountSessionProvider),
    google: ref.watch(googleIdTokensProvider),
  );
  unawaited(notifier.restore());
  return notifier;
});

class AccountState {
  const AccountState({this.user});

  /// Null when signed out — or signed in with a profile not loaded yet.
  final AccountUser? user;

  bool get isSignedIn => user != null;
  bool get needsClaim => user?.needsClaim ?? false;
}

class AccountNotifier extends StateNotifier<AccountState> {
  AccountNotifier({
    required AccountService service,
    required AccountSession session,
    required GoogleIdTokens google,
  })  : _service = service,
        _session = session,
        _google = google,
        super(const AccountState()) {
    _ended = session.ended.listen((_) {
      if (mounted) state = const AccountState();
    });
  }

  final AccountService _service;
  final AccountSession _session;
  final GoogleIdTokens _google;
  late final StreamSubscription<void> _ended;

  /// Shows the profile kept from last time at once, then asks the server.
  Future<void> restore() async {
    if (await _session.read() == null) return;
    final kept = await _session.readProfile();
    if (kept != null && mounted) {
      try {
        state = AccountState(
          user: AccountUser.fromJson(jsonDecode(kept) as Map<String, dynamic>),
        );
      } catch (_) {
        // A profile written by another build: wait for the server's.
      }
    }
    await refresh();
  }

  /// Reads `/me` again. With no connection the last known profile stays; a
  /// session the server refused has already ended, which the listener on
  /// [AccountSession.ended] turns into signed out.
  Future<void> refresh() async {
    if (await _session.read() == null) return;
    try {
      await _adopt(await _service.me());
    } on SlimshotApiException catch (e) {
      debugPrint('AccountNotifier.refresh: ${e.code}');
    }
  }

  Future<void> completeSignIn(SignInResult result) async {
    await _session.save(result.tokens);
    await _adopt(result.user);
  }

  Future<ClaimResult> claim({
    required String username,
    String? referralCode,
  }) async {
    final result = await _service.claim(
      username: username,
      referralCode: referralCode,
    );
    await _adopt(result.user);
    return result;
  }

  Future<void> changeUsername(String name) async =>
      _adopt(await _service.changeUsername(name));

  /// Ends the session here whether or not the server hears about it: a
  /// sign-out that waited for a connection would leave the account open on a
  /// phone the user meant to leave.
  Future<void> signOut() async {
    final tokens = await _session.read();
    if (tokens != null) {
      try {
        await _service.logout(tokens.refreshToken);
      } on SlimshotApiException catch (e) {
        debugPrint('AccountNotifier.signOut: server not told (${e.code})');
      }
    }
    unawaited(_google.signOut());
    await _session.end();
  }

  /// Deletes the account on the server, then forgets it here. A refusal
  /// keeps everything and throws, so the confirm sheet can say why.
  Future<void> deleteAccount() async {
    await _service.deleteAccount();
    unawaited(_google.signOut());
    await _session.end();
  }

  /// Keeps [user] — unless the session ended while the answer was on its
  /// way, in which case nothing personal is written back.
  Future<void> _adopt(AccountUser user) async {
    if (await _session.read() == null) return;
    await _session.saveProfile(jsonEncode(user.toJson()));
    if (mounted) state = AccountState(user: user);
  }

  @override
  void dispose() {
    unawaited(_ended.cancel());
    super.dispose();
  }
}
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `flutter test test/features/account/`
Expected: all PASS.

- [ ] **Step 8: Check the Android build takes the two plugins**

Run: `flutter build apk --debug`
Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`. If Gradle names a minimum `minSdk` or `compileSdk` for `google_sign_in_android` or `flutter_secure_storage`, raise that value in `android/app/build.gradle.kts` to the number it names, rebuild, and ledger the ruling.

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/account test/support/account_harness.dart test/features/account/providers
git commit -m "feat(account): the signed-in state, and Google's account picker

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(Add `android/app/build.gradle.kts` to the commit if Step 8 changed it.)

---

### Task 6: The sign-in sheet

**Files:**
- Create: `lib/features/account/widgets/account_sheet_frame.dart`
- Create: `lib/features/account/widgets/sign_in_sheet.dart`
- Create: `test/features/account/widgets/sign_in_sheet_test.dart`

**Interfaces:**
- Consumes: `accountServiceProvider`, `googleIdTokensProvider`, `accountProvider` (Task 5); `accountErrorMessage` (Task 4); `SheetGrabHandle` (`lib/features/video_editor/widgets/panels/caption_sheet_parts.dart`); `showEditorSheet`.
- Produces: `const double kAccountSheetMaxWidth = 480`; widgets `AccountSheetFrame({required List<Widget> children})`, `AccountSheetHeading(String text)`, `AccountErrorLine(String text)`, `AccountPrimaryButton({required String label, required VoidCallback? onPressed, bool busy = false, bool danger = false})`; `InputDecoration accountInputDecoration(String hint)`; `const TextStyle kAccountInputStyle`.
- Produces: `SignInSheet({required String reason})` — pops `true` once signed in. Widget keys `sign_in_email`, `sign_in_code`, `sign_in_resend`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/account/widgets/sign_in_sheet_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/account/widgets/sign_in_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';

import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  late FakeGoogleIdTokens google;

  setUp(() {
    server = FakeServer()
      ..on(
        'POST',
        '/auth/email/start',
        (_) => envelope({
          'sentTo': 'ann@example.com',
          'resendAfterSeconds': 60,
          'expiresInSeconds': 600,
        }),
      )
      ..on('POST', '/auth/email/verify', (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return body['code'] == '123456'
            ? envelope(signInJson())
            : failure('OTP_INVALID', 422, details: {'attemptsLeft': 3});
      })
      ..on('POST', '/auth/google', (_) => envelope(signInJson()));
    google = FakeGoogleIdTokens();
  });

  Future<List<Object?>> open(WidgetTester tester) async {
    final results = await pumpHost(
      tester,
      accountOverrides(server, google: google),
      (context, ref) => showEditorSheet<bool>(
        context,
        builder: (_) => const SignInSheet(reason: 'Sign in to use Auto captions'),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return results;
  }

  Future<void> sendCode(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('sign_in_email')), 'ann@example.com');
    await tester.tap(find.text('Continue'));
    await settle(tester);
  }

  testWidgets('says why it opened, and offers Google and email', (tester) async {
    await open(tester);
    expect(find.text('Sign in to use Auto captions'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byKey(const Key('sign_in_email')), findsOneWidget);
  });

  testWidgets('without Google set up, email is the only way in', (tester) async {
    google = FakeGoogleIdTokens(isAvailable: false);
    await open(tester);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.byKey(const Key('sign_in_email')), findsOneWidget);
  });

  testWidgets('something that is not an email is not sent', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('sign_in_email')), 'ann');
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(server.requests, isEmpty);
  });

  testWidgets('an email gets a code, and asking again waits', (tester) async {
    await open(tester);
    await sendCode(tester);

    expect(server.lastBody('POST', '/auth/email/start'), {
      'email': 'ann@example.com',
      'deviceToken': 'dev-1',
    });
    expect(find.text('Code sent to ann@example.com'), findsOneWidget);
    expect(find.text('Send again in 60s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 60));
    expect(find.text('Send a new code'), findsOneWidget);
  });

  testWidgets('the right code signs in and closes the sheet', (tester) async {
    final results = await open(tester);
    await sendCode(tester);
    await tester.enterText(find.byKey(const Key('sign_in_code')), '123456');
    await settle(tester);

    expect(results, [true]);
    final container = containerOf(tester);
    expect(container.read(accountProvider).isSignedIn, isTrue);
    expect((await container.read(accountSessionProvider).read())!.accessToken, 'a1');
  });

  testWidgets('a wrong code says how many tries are left', (tester) async {
    final results = await open(tester);
    await sendCode(tester);
    await tester.enterText(find.byKey(const Key('sign_in_code')), '111111');
    await settle(tester);

    expect(find.text('Wrong code · 3 tries left'), findsOneWidget);
    expect(results, isEmpty);
    final code = tester.widget<TextField>(find.byKey(const Key('sign_in_code')));
    expect(code.controller!.text, isEmpty);
  });

  testWidgets('a disposable address is refused in one line', (tester) async {
    server.on(
      'POST',
      '/auth/email/start',
      (_) => failure('EMAIL_DOMAIN_NOT_ALLOWED', 422),
    );
    await open(tester);
    await sendCode(tester);
    expect(find.text('Use a regular email address.'), findsOneWidget);
    expect(find.byKey(const Key('sign_in_email')), findsOneWidget);
  });

  testWidgets('Google signs in with the token the picker gave', (tester) async {
    final results = await open(tester);
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);

    expect(server.lastBody('POST', '/auth/google'), {
      'idToken': 'google-id-token',
      'deviceToken': 'dev-1',
    });
    expect(results, [true]);
  });

  testWidgets('closing the Google picker changes nothing', (tester) async {
    google.idToken = null;
    final results = await open(tester);
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);

    expect(google.requests, 1);
    expect(server.to('POST', '/auth/google'), isEmpty);
    expect(results, isEmpty);
    expect(find.text('Sign in to use Auto captions'), findsOneWidget);
  });

  testWidgets('a Google account without a verified email is pointed at email',
      (tester) async {
    server.on('POST', '/auth/google', (_) => failure('GOOGLE_EMAIL_UNVERIFIED', 422));
    await open(tester);
    await tester.tap(find.text('Continue with Google'));
    await settle(tester);
    expect(find.text('Use your email instead.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/features/account/widgets/sign_in_sheet_test.dart`
Expected: FAIL — `sign_in_sheet.dart` not found.

- [ ] **Step 3: Write the frame**

Create `lib/features/account/widgets/account_sheet_frame.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../video_editor/widgets/panels/caption_sheet_parts.dart'
    show SheetGrabHandle;

/// The widest an account sheet grows: on a tablet it is a card, not a band
/// across the screen.
const double kAccountSheetMaxWidth = 480;

const TextStyle kAccountInputStyle =
    TextStyle(color: AppColors.textPrimary, fontSize: 16);

/// The frame every account sheet shares: the surface, corners and grab
/// handle the editor's sheets have, capped at [kAccountSheetMaxWidth] and
/// lifted above the keyboard.
class AccountSheetFrame extends StatelessWidget {
  const AccountSheetFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kAccountSheetMaxWidth),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + keyboard),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: SheetGrabHandle()),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sheet's one heading: why it opened.
class AccountSheetHeading extends StatelessWidget {
  const AccountSheetHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

/// One line under the field it is about. Never a dialog.
class AccountErrorLine extends StatelessWidget {
  const AccountErrorLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.error, fontSize: 13),
        ),
      );
}

/// The sheet's main action. A busy button shows a spinner and takes no tap.
class AccountPrimaryButton extends StatelessWidget {
  const AccountPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool danger;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: danger ? AppColors.error : AppColors.primaryStart,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.surfaceLight,
            disabledForegroundColor: AppColors.textTertiary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textPrimary,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      );
}

InputDecoration accountInputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.surface,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primaryStart),
      ),
    );
```

- [ ] **Step 4: Write the sheet**

Create `lib/features/account/widgets/sign_in_sheet.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/slimshot_api.dart';
import '../../../core/theme/app_colors.dart';
import '../logic/account_copy.dart';
import '../models/account_models.dart';
import '../providers/account_providers.dart';
import 'account_sheet_frame.dart';

final RegExp _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Signing in: Google, or an email and the code sent to it. The first
/// sign-in makes the account; there are no passwords.
///
/// One sheet, two steps — the email, then the code. Pops `true` once the
/// session is saved; closed any other way it pops nothing.
class SignInSheet extends ConsumerStatefulWidget {
  const SignInSheet({super.key, required this.reason});

  /// Why the sheet opened — "Sign in to use Auto captions" — its one heading.
  final String reason;

  @override
  ConsumerState<SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<SignInSheet> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  /// Where the code went; null on the email step.
  String? _sentTo;
  String? _error;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    return AccountSheetFrame(
      children: [
        AccountSheetHeading(widget.reason),
        ...(sentTo == null ? _emailStep() : _codeStep(sentTo)),
      ],
    );
  }

  List<Widget> _emailStep() {
    final google = ref.watch(googleIdTokensProvider);
    return [
      if (google.isAvailable) ...[
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: _busy ? null : _google,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Continue with Google',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(child: Divider(color: Colors.white10)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
              Expanded(child: Divider(color: Colors.white10)),
            ],
          ),
        ),
      ],
      TextField(
        key: const Key('sign_in_email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        autocorrect: false,
        textInputAction: TextInputAction.done,
        style: kAccountInputStyle,
        decoration: accountInputDecoration('Email'),
        onSubmitted: (_) => _sendCode(),
      ),
      if (_error != null) AccountErrorLine(_error!),
      const SizedBox(height: 16),
      AccountPrimaryButton(label: 'Continue', busy: _busy, onPressed: _sendCode),
    ];
  }

  List<Widget> _codeStep(String sentTo) => [
        Text(
          'Code sent to $sentTo',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('sign_in_code'),
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: kAccountInputStyle.copyWith(fontSize: 22, letterSpacing: 8),
          decoration: accountInputDecoration('6-digit code'),
          onChanged: (value) {
            setState(() {});
            if (value.length == 6) _verify();
          },
        ),
        if (_error != null) AccountErrorLine(_error!),
        const SizedBox(height: 16),
        AccountPrimaryButton(
          label: 'Continue',
          busy: _busy,
          onPressed: _code.text.length == 6 ? _verify : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _busy ? null : _useAnotherEmail,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Use another email'),
            ),
            TextButton(
              key: const Key('sign_in_resend'),
              onPressed: _resendIn > 0 || _busy ? null : _sendCode,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: Text(
                _resendIn > 0 ? 'Send again in ${_resendIn}s' : 'Send a new code',
              ),
            ),
          ],
        ),
      ];

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await ref.read(googleIdTokensProvider).requestIdToken();
      if (idToken == null) return; // closed the picker
      final result =
          await ref.read(accountServiceProvider).signInWithGoogle(idToken);
      await _finish(result);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final email = (_sentTo ?? _email.text).trim();
    if (!_emailShape.hasMatch(email)) {
      setState(() => _error = 'Enter your email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent = await ref.read(accountServiceProvider).startEmail(email);
      if (!mounted) return;
      setState(() {
        _sentTo = sent.sentTo.isEmpty ? email : sent.sentTo;
        _code.clear();
      });
      _countDown(sent.resendAfter.inSeconds);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final sentTo = _sentTo;
    if (_busy || sentTo == null || _code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(accountServiceProvider).verifyEmail(sentTo, _code.text);
      await _finish(result);
    } catch (e) {
      _code.clear();
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(SignInResult result) async {
    await ref.read(accountProvider.notifier).completeSignIn(result);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _useAnotherEmail() {
    _ticker?.cancel();
    setState(() {
      _sentTo = null;
      _error = null;
      _resendIn = 0;
    });
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() => _error = accountErrorMessage(error));
    if (error is SlimshotApiException && error.code == 'OTP_RESEND_TOO_SOON') {
      final wait = error.detailInt('retryAfterSeconds');
      if (wait != null) _countDown(wait);
    }
  }

  void _countDown(int seconds) {
    _ticker?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `flutter test test/features/account/widgets/sign_in_sheet_test.dart test/features/video_editor/widgets/panels/editor_sheet_test.dart`
Expected: all PASS (the editor-sheet scan still finds no stray `showModalBottomSheet`).

- [ ] **Step 6: Commit**

```bash
git add lib/features/account/widgets test/features/account/widgets
git commit -m "feat(account): sign in with Google or an emailed code

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The claim step, and the one door

**Files:**
- Create: `lib/features/account/widgets/username_field.dart`
- Create: `lib/features/account/widgets/claim_sheet.dart`
- Create: `lib/features/account/account_gate.dart`
- Create: `test/features/account/widgets/claim_sheet_test.dart`
- Create: `test/features/account/account_gate_test.dart`

**Interfaces:**
- Consumes: Task 4 copy and rules (`isValidUsername`, `usernameInputFormatters`, `kUsernameCheckDelay`, `usernameReasonMessage`, `accountErrorMessage`, `claimResultLines`); Task 5 providers; Task 6 frame widgets and `SignInSheet`.
- Produces: `UsernameField({required TextEditingController controller, required ValueChanged<bool> onAvailability, String? current})` (keys `username_field`, `username_ok`); `ClaimSheet()` — pops `true` when claimed; `Future<bool> requireAccount(BuildContext context, WidgetRef ref, {required String reason})`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/account/widgets/claim_sheet_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimshotai/features/account/logic/account_copy.dart';
import 'package:slimshotai/features/account/logic/username_rules.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/account/widgets/claim_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';

import '../../../support/account_fakes.dart';
import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;

  setUp(() {
    server = FakeServer()
      ..on('GET', '/me', (_) => envelope(userJson(needsClaim: true, balance: 0)))
      ..on(
        'GET',
        '/usernames/ann_1/availability',
        (_) => envelope({'username': 'ann_1', 'available': true}),
      )
      ..on(
        'GET',
        '/usernames/bob/availability',
        (_) => envelope({'username': 'bob', 'available': false, 'reason': 'TAKEN'}),
      )
      ..on(
        'POST',
        '/me/claim',
        (_) => envelope({
          'user': userJson(balance: 100),
          'bonus': {'granted': true, 'credits': 100},
          'referral': null,
        }),
      );
  });

  Future<List<Object?>> open(WidgetTester tester) async {
    final results = await pumpHost(
      tester,
      accountOverrides(
        server,
        session: signedInSession(profile: userJson(needsClaim: true, balance: 0)),
      ),
      (context, ref) =>
          showEditorSheet<bool>(context, builder: (_) => const ClaimSheet()),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return results;
  }

  Future<void> typeName(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const Key('username_field')), name);
    await tester.pump(kUsernameCheckDelay);
    await settle(tester);
  }

  VoidCallback? claimButton(WidgetTester tester) => tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, 'Claim'))
      .onPressed;

  int availabilityChecks() =>
      server.requests.where((r) => r.url.path.endsWith('/availability')).length;

  testWidgets('Claim waits for a free name, asked once typing stops',
      (tester) async {
    await open(tester);
    expect(find.text('Choose a username to claim your free credits'), findsOneWidget);
    expect(claimButton(tester), isNull);

    for (final partial in ['ann', 'ann_', 'ann_1']) {
      await tester.enterText(find.byKey(const Key('username_field')), partial);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(kUsernameCheckDelay);
    await settle(tester);

    expect(availabilityChecks(), 1);
    expect(find.byKey(const Key('username_ok')), findsOneWidget);
    expect(claimButton(tester), isNotNull);
  });

  testWidgets('a name against the rules is explained without asking',
      (tester) async {
    await open(tester);
    await typeName(tester, 'ab');
    expect(find.text(kUsernameRule), findsOneWidget);
    expect(availabilityChecks(), 0);
    expect(claimButton(tester), isNull);
  });

  testWidgets('a taken name says so and cannot be claimed', (tester) async {
    await open(tester);
    await typeName(tester, 'bob');
    expect(find.text('Taken'), findsOneWidget);
    expect(claimButton(tester), isNull);
  });

  testWidgets('an answer for a name already typed over is ignored',
      (tester) async {
    final slow = Completer<http.Response>();
    server.on('GET', '/usernames/ann_1/availability', (_) => slow.future);
    await open(tester);
    await tester.enterText(find.byKey(const Key('username_field')), 'ann_1');
    await tester.pump(kUsernameCheckDelay); // the question is asked
    await tester.enterText(find.byKey(const Key('username_field')), 'ann_12');
    slow.complete(envelope({'username': 'ann_1', 'available': true}));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('username_ok')), findsNothing);
    expect(claimButton(tester), isNull);
  });

  testWidgets('claiming shows what was granted, and Done closes the sheet',
      (tester) async {
    final results = await open(tester);
    await typeName(tester, 'ann_1');
    await tester.tap(find.text('Claim'));
    await settle(tester);

    expect(server.lastBody('POST', '/me/claim'), {'username': 'ann_1'});
    expect(find.text('+100 credits'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(results, [true]);
    expect(containerOf(tester).read(accountProvider).needsClaim, isFalse);
  });

  testWidgets('an invite code travels with the claim, and its credits are said',
      (tester) async {
    server.on(
      'POST',
      '/me/claim',
      (_) => envelope({
        'user': userJson(balance: 120),
        'bonus': {'granted': true, 'credits': 100},
        'referral': {'outcome': 'rewarded', 'credits': 20},
      }),
    );
    await open(tester);
    await typeName(tester, 'ann_1');
    await tester.tap(find.text('Have an invite code?'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('claim_invite')), ' ab3 def7k ');
    await tester.tap(find.text('Claim'));
    await settle(tester);

    expect(server.lastBody('POST', '/me/claim'), {
      'username': 'ann_1',
      'referralCode': 'ab3def7k',
    });
    expect(find.text('+120 credits'), findsOneWidget);
    expect(find.text('Includes 20 from your invite'), findsOneWidget);
  });

  testWidgets('a bad invite code is marked on its field, and nothing claimed',
      (tester) async {
    server.on('POST', '/me/claim', (_) => failure('REFERRAL_CODE_INVALID', 422));
    await open(tester);
    await typeName(tester, 'ann_1');
    await tester.tap(find.text('Have an invite code?'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('claim_invite')), 'NOPE');
    await tester.tap(find.text('Claim'));
    await settle(tester);

    expect(find.text("That invite code doesn't work."), findsOneWidget);
    expect(find.text('Claim'), findsOneWidget);
    expect(containerOf(tester).read(accountProvider).needsClaim, isTrue);
  });

  testWidgets('no bonus is explained honestly', (tester) async {
    server.on(
      'POST',
      '/me/claim',
      (_) => envelope({
        'user': userJson(balance: 0),
        'bonus': {'granted': false, 'reason': 'BONUS_ALREADY_CLAIMED'},
        'referral': null,
      }),
    );
    await open(tester);
    await typeName(tester, 'ann_1');
    await tester.tap(find.text('Claim'));
    await settle(tester);

    expect(find.text("You're all set"), findsOneWidget);
    expect(
      find.text('This email or phone has already had its free credits.'),
      findsOneWidget,
    );
  });
}
```

Create `test/features/account/account_gate_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/account_gate.dart';
import 'package:slimshotai/features/account/logic/username_rules.dart';

import '../../support/account_fakes.dart';
import '../../support/account_harness.dart';
import '../../support/fake_server.dart';

const reason = 'Sign in to use Auto captions';
const claimHeading = 'Choose a username to claim your free credits';

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  Future<List<Object?>> openGate(WidgetTester tester, {bool signedIn = false, bool needsClaim = false, bool keptProfile = true}) async {
    final session = signedIn
        ? signedInSession(
            profile: keptProfile ? userJson(needsClaim: needsClaim) : null,
          )
        : null;
    final results = await pumpHost(
      tester,
      accountOverrides(server, session: session),
      (context, ref) => requireAccount(context, ref, reason: reason),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return results;
  }

  testWidgets('signed in and claimed: straight through', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson()));
    final results = await openGate(tester, signedIn: true);
    expect(results, [true]);
    expect(find.text(reason), findsNothing);
  });

  testWidgets('signed out: the sign-in sheet, and closing it is a no',
      (tester) async {
    final results = await openGate(tester);
    expect(find.text(reason), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(results, [false]);
  });

  testWidgets('a new account goes from sign-in straight to the claim',
      (tester) async {
    server
      ..on(
        'POST',
        '/auth/email/start',
        (_) => envelope({'sentTo': 'ann@example.com', 'resendAfterSeconds': 60}),
      )
      ..on('POST', '/auth/email/verify', (request) {
        expect((jsonDecode(request.body) as Map)['code'], '123456');
        return envelope(signInJson(needsClaim: true));
      })
      ..on(
        'GET',
        '/usernames/ann_1/availability',
        (_) => envelope({'username': 'ann_1', 'available': true}),
      )
      ..on(
        'POST',
        '/me/claim',
        (_) => envelope({
          'user': userJson(balance: 100),
          'bonus': {'granted': true, 'credits': 100},
          'referral': null,
        }),
      );
    final results = await openGate(tester);

    await tester.enterText(find.byKey(const Key('sign_in_email')), 'ann@example.com');
    await tester.tap(find.text('Continue'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('sign_in_code')), '123456');
    await settle(tester);

    expect(find.text(claimHeading), findsOneWidget);
    await tester.enterText(find.byKey(const Key('username_field')), 'ann_1');
    await tester.pump(kUsernameCheckDelay);
    await settle(tester);
    await tester.tap(find.text('Claim'));
    await settle(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);

    expect(results, [true]);
  });

  testWidgets('signed in but not claimed: the claim sheet only', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson(needsClaim: true)));
    final results = await openGate(tester, signedIn: true, needsClaim: true);
    expect(find.text(claimHeading), findsOneWidget);
    expect(find.text(reason), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(results, [false]);
  });

  testWidgets('a kept session whose profile has not loaded is not asked to '
      'sign in again', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson()));
    final results = await openGate(tester, signedIn: true, keptProfile: false);
    expect(results, [true]);
    expect(find.text(reason), findsNothing);
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/features/account/widgets/claim_sheet_test.dart test/features/account/account_gate_test.dart`
Expected: FAIL — `claim_sheet.dart`, `account_gate.dart` not found.

- [ ] **Step 3: Write the username field**

Create `lib/features/account/widgets/username_field.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../logic/account_copy.dart';
import '../logic/username_rules.dart';
import '../providers/account_providers.dart';
import 'account_sheet_frame.dart';

/// A username field that asks the server whether a name is free once typing
/// pauses: one question per pause, and an answer for text the user has since
/// typed over is dropped — a late "available" must never bless a different
/// name.
class UsernameField extends ConsumerStatefulWidget {
  const UsernameField({
    super.key,
    required this.controller,
    required this.onAvailability,
    this.current,
  });

  final TextEditingController controller;

  /// Whether the text now in the field can be taken.
  final ValueChanged<bool> onAvailability;

  /// The user's own name (Settings): nothing to check, nothing to save.
  final String? current;

  @override
  ConsumerState<UsernameField> createState() => _UsernameFieldState();
}

class _UsernameFieldState extends ConsumerState<UsernameField> {
  Timer? _debounce;
  bool _checking = false;
  bool _ok = false;
  String? _message;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    widget.onAvailability(false);
    setState(() {
      _ok = false;
      _checking = false;
      _message = null;
    });
    if (text.isEmpty || text == widget.current) return;
    if (!isValidUsername(text)) {
      setState(() => _message = kUsernameRule);
      return;
    }
    setState(() => _checking = true);
    _debounce = Timer(kUsernameCheckDelay, () => _check(text));
  }

  Future<void> _check(String name) async {
    try {
      final answer =
          await ref.read(accountServiceProvider).usernameAvailability(name);
      if (!mounted || widget.controller.text != name) return;
      setState(() {
        _checking = false;
        _ok = answer.available;
        _message = answer.available ? null : usernameReasonMessage(answer.reason);
      });
      widget.onAvailability(answer.available);
    } catch (e) {
      if (!mounted || widget.controller.text != name) return;
      setState(() {
        _checking = false;
        _message = accountErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('username_field'),
          controller: widget.controller,
          autofocus: true,
          autocorrect: false,
          inputFormatters: usernameInputFormatters,
          style: kAccountInputStyle,
          onChanged: _changed,
          decoration: accountInputDecoration('Username').copyWith(
            prefixText: '@',
            prefixStyle: const TextStyle(color: AppColors.textTertiary),
            suffixIcon: _checking
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                : _ok
                    ? const Icon(
                        LucideIcons.check,
                        key: Key('username_ok'),
                        color: AppColors.success,
                      )
                    : null,
          ),
        ),
        if (_message != null) AccountErrorLine(_message!),
      ],
    );
  }
}
```

- [ ] **Step 4: Write the claim sheet**

Create `lib/features/account/widgets/claim_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/slimshot_api.dart';
import '../../../core/theme/app_colors.dart';
import '../logic/account_copy.dart';
import '../models/account_models.dart';
import '../providers/account_providers.dart';
import 'account_sheet_frame.dart';
import 'username_field.dart';

/// A new account's first step: choose a username, optionally enter a
/// friend's invite code, and claim the free credits. The amount is the
/// server's, so the sheet names it only once it has been granted.
///
/// Pops `true` when claimed. Closed before that, the account stays signed in
/// and unclaimed, and the next paid action asks again.
class ClaimSheet extends ConsumerStatefulWidget {
  const ClaimSheet({super.key});

  @override
  ConsumerState<ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends ConsumerState<ClaimSheet> {
  final _username = TextEditingController();
  final _invite = TextEditingController();
  bool _available = false;
  bool _showInvite = false;
  bool _busy = false;
  String? _error;
  String? _inviteError;
  ClaimResult? _result;

  @override
  void dispose() {
    _username.dispose();
    _invite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AccountSheetFrame(
      children: result == null ? _form() : _claimed(result),
    );
  }

  List<Widget> _form() => [
        const AccountSheetHeading('Choose a username to claim your free credits'),
        UsernameField(
          controller: _username,
          onAvailability: (ok) => setState(() => _available = ok),
        ),
        const SizedBox(height: 12),
        if (_showInvite) ...[
          TextField(
            key: const Key('claim_invite'),
            controller: _invite,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            style: kAccountInputStyle,
            decoration: accountInputDecoration('Invite code'),
            onChanged: (_) {
              if (_inviteError != null) setState(() => _inviteError = null);
            },
          ),
          if (_inviteError != null) AccountErrorLine(_inviteError!),
        ] else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showInvite = true),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Have an invite code?'),
            ),
          ),
        if (_error != null) AccountErrorLine(_error!),
        const SizedBox(height: 16),
        AccountPrimaryButton(
          label: 'Claim',
          busy: _busy,
          onPressed: _available ? _claim : null,
        ),
      ];

  List<Widget> _claimed(ClaimResult result) => [
        const SizedBox(height: 8),
        Text(
          result.creditsGranted > 0
              ? '+${result.creditsGranted} credits'
              : "You're all set",
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        for (final line in claimResultLines(result))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        const SizedBox(height: 24),
        AccountPrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ];

  Future<void> _claim() async {
    setState(() {
      _busy = true;
      _error = null;
      _inviteError = null;
    });
    final invite = _invite.text.replaceAll(' ', '');
    try {
      final result = await ref.read(accountProvider.notifier).claim(
            username: _username.text,
            referralCode: invite.isEmpty ? null : invite,
          );
      if (mounted) setState(() => _result = result);
    } on SlimshotApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ALREADY_CLAIMED') {
        await ref.read(accountProvider.notifier).refresh();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        if (e.code == 'REFERRAL_CODE_INVALID') {
          _inviteError = accountErrorMessage(e);
        } else {
          _error = accountErrorMessage(e);
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
```

- [ ] **Step 5: Write the door**

Create `lib/features/account/account_gate.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../video_editor/widgets/panels/editor_sheet.dart';
import 'providers/account_providers.dart';
import 'widgets/claim_sheet.dart';
import 'widgets/sign_in_sheet.dart';

/// The one door to anything that needs an account: the sign-in sheet when
/// signed out, then the claim sheet for an account that has not claimed.
/// Answers whether the user came through signed in and claimed.
///
/// [reason] is the sign-in sheet's heading — why it opened.
Future<bool> requireAccount(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
}) async {
  final notifier = ref.read(accountProvider.notifier);
  if (!ref.read(accountProvider).isSignedIn) {
    // A kept session whose profile has not loaded yet is still a session.
    await notifier.refresh();
  }
  if (!context.mounted) return false;
  if (!ref.read(accountProvider).isSignedIn) {
    final signedIn = await showEditorSheet<bool>(
      context,
      builder: (_) => SignInSheet(reason: reason),
    );
    if (signedIn != true || !context.mounted) return false;
  }
  if (ref.read(accountProvider).needsClaim) {
    final claimed = await showEditorSheet<bool>(
      context,
      builder: (_) => const ClaimSheet(),
    );
    if (claimed != true) return false;
  }
  return ref.read(accountProvider).isSignedIn;
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `flutter test test/features/account/`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/account test/features/account
git commit -m "feat(account): the claim step, and one door to anything needing an account

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The credits pill on the home screen

**Files:**
- Create: `lib/features/account/widgets/credits_pill.dart`
- Create: `lib/screens/home_header.dart`
- Modify: `lib/screens/home_screen.dart:212-246` (the logo row)
- Create: `test/features/account/widgets/credits_pill_test.dart`
- Create: `test/screens/home_header_test.dart`

**Interfaces:**
- Consumes: `accountFeatureProvider`, `accountProvider` (Task 5); `requireAccount` (Task 7).
- Produces: `CreditsPill()` (keys `credits_pill_balance`, `credits_pill_free`); `HomeHeader({required Widget brand})`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/account/widgets/credits_pill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/account/widgets/credits_pill.dart';

import '../../../support/account_fakes.dart';
import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  Future<void> pumpPill(WidgetTester tester, List<Override> overrides) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: CreditsPill())),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('a build without a server shows nothing', (tester) async {
    await pumpPill(tester, [accountFeatureProvider.overrideWithValue(false)]);
    expect(find.byKey(const Key('credits_pill_free')), findsNothing);
    expect(find.byKey(const Key('credits_pill_balance')), findsNothing);
  });

  testWidgets('signed out it offers free credits, and a tap asks to sign in',
      (tester) async {
    await pumpPill(tester, accountOverrides(server));
    expect(find.text('Free credits'), findsOneWidget);
    await tester.tap(find.byKey(const Key('credits_pill_free')));
    await settle(tester);
    expect(find.text('Sign in to get free credits'), findsOneWidget);
  });

  testWidgets('signed in it shows the balance', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson(balance: 94)));
    await pumpPill(
      tester,
      accountOverrides(server, session: signedInSession(profile: userJson(balance: 94))),
    );
    expect(find.text('94'), findsOneWidget);
    expect(find.text('Free credits'), findsNothing);
  });

  testWidgets('an account not yet claimed is offered its credits through the '
      'claim', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson(needsClaim: true, balance: 0)));
    await pumpPill(
      tester,
      accountOverrides(
        server,
        session: signedInSession(profile: userJson(needsClaim: true, balance: 0)),
      ),
    );
    await tester.tap(find.byKey(const Key('credits_pill_free')));
    await settle(tester);
    expect(find.text('Choose a username to claim your free credits'), findsOneWidget);
  });

  testWidgets('coming back to the app reads the balance again', (tester) async {
    server.on('GET', '/me', (_) => envelope(userJson()));
    await pumpPill(
      tester,
      accountOverrides(server, session: signedInSession(profile: userJson())),
    );
    final before = server.to('GET', '/me').length;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);
    expect(server.to('GET', '/me').length, before + 1);
  });
}
```

Create `test/screens/home_header_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/screens/home_header.dart';

import '../support/account_harness.dart';
import '../support/fake_server.dart';

void main() {
  testWidgets('the brand gives way to the pill on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: accountOverrides(FakeServer()),
        child: const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: HomeHeader(brand: SizedBox(width: 230, height: 44)),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Free credits'), findsOneWidget);
    final pill = tester.getRect(find.text('Free credits'));
    expect(pill.right, lessThanOrEqualTo(360 - 24 + 0.01));
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/features/account/widgets/credits_pill_test.dart test/screens/home_header_test.dart`
Expected: FAIL — `credits_pill.dart`, `home_header.dart` not found.

- [ ] **Step 3: Write the pill**

Create `lib/features/account/widgets/credits_pill.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../account_gate.dart';
import '../providers/account_providers.dart';

/// Top right of the home screen: the balance when signed in and claimed,
/// otherwise "Free credits", which opens the way to them.
///
/// No number is promised before sign-in: the bonus is set by the admin and
/// not every email or phone is eligible, so only the claim names an amount.
/// The balance is read again whenever the app comes back to the front.
class CreditsPill extends ConsumerStatefulWidget {
  const CreditsPill({super.key});

  @override
  ConsumerState<CreditsPill> createState() => _CreditsPillState();
}

class _CreditsPillState extends ConsumerState<CreditsPill> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () {
      if (ref.read(accountFeatureProvider)) {
        unawaited(ref.read(accountProvider.notifier).refresh());
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(accountFeatureProvider)) return const SizedBox.shrink();
    final user = ref.watch(accountProvider).user;
    if (user != null && !user.needsClaim) {
      return _Pill(
        key: const Key('credits_pill_balance'),
        icon: LucideIcons.coins,
        label: '${user.creditBalance}',
      );
    }
    return _Pill(
      key: const Key('credits_pill_free'),
      icon: LucideIcons.gift,
      label: 'Free credits',
      onTap: () => unawaited(
        requireAccount(context, ref, reason: 'Sign in to get free credits'),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.primaryStart),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write the header and place it**

Create `lib/screens/home_header.dart`:

```dart
import 'package:flutter/material.dart';

import '../features/account/widgets/credits_pill.dart';

/// The home screen's top row: the brand on the left, the credits pill on the
/// right. On a narrow phone the brand scales down rather than push the pill
/// off the screen.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.brand});

  final Widget brand;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: brand,
          ),
        ),
        const SizedBox(width: 12),
        const CreditsPill(),
      ],
    );
  }
}
```

In `lib/screens/home_screen.dart`, add `import 'home_header.dart';` and replace the logo row — from `Row(` at line 212 through its `.animate().fadeIn().slideY(begin: -0.2, end: 0,), // Settings header animation` — with:

```dart
                          HomeHeader(
                            brand: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'assets/logo.svg',
                                  width: 44,
                                  height: 44,
                                ),
                                const SizedBox(width: 8),
                                ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                        colors: [
                                          AppColors.textPrimary,
                                          AppColors.textSecondary,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ).createShader(bounds),
                                  child: Text(
                                    'SlimShot AI',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ).animate().fadeIn().slideY(begin: -0.2, end: 0),
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `flutter test test/features/account/widgets/credits_pill_test.dart test/screens/home_header_test.dart`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/account/widgets/credits_pill.dart lib/screens/home_header.dart lib/screens/home_screen.dart test/features/account/widgets/credits_pill_test.dart test/screens/home_header_test.dart
git commit -m "feat(account): credits on the home screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: The Account section in Settings

**Files:**
- Create: `lib/core/widgets/settings_rows.dart` (rows moved out of `settings_screen.dart`)
- Modify: `lib/screens/settings_screen.dart`
- Create: `lib/features/account/widgets/settings_account_section.dart`
- Create: `lib/features/account/widgets/username_sheet.dart`
- Create: `lib/features/account/widgets/delete_account_sheet.dart`
- Create: `test/features/account/widgets/settings_account_section_test.dart`

**Interfaces:**
- Consumes: Task 5 providers; Task 6 frame widgets; Task 7 `UsernameField`, `requireAccount`; `GlassCard`; `ToastUtils`.
- Produces: `SettingsSectionHeader({required String title})`, `SettingsItem({required IconData icon, required String title, required VoidCallback onTap, String? subtitle, bool isDanger = false, bool showChevron = true})`, `SettingsDivider()`; `SettingsAccountSection()`; `UsernameSheet({required String current})`; `DeleteAccountSheet()` (key `delete_account_confirm`).

- [ ] **Step 1: Write the failing tests**

Create `test/features/account/widgets/settings_account_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/features/account/logic/username_rules.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/account/widgets/settings_account_section.dart';

import '../../../support/account_fakes.dart';
import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  late FakeServer server;
  setUp(() {
    server = FakeServer()..on('GET', '/me', (_) => envelope(userJson()));
  });

  Future<void> pumpSection(WidgetTester tester, List<Override> overrides) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SettingsAccountSection()),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  AccountSession signedIn() => signedInSession(refresh: 'r1', profile: userJson());

  testWidgets('a build without a server has no account section', (tester) async {
    await pumpSection(tester, [accountFeatureProvider.overrideWithValue(false)]);
    expect(find.text('ACCOUNT'), findsNothing);
  });

  testWidgets('signed out it offers to sign in', (tester) async {
    await pumpSection(tester, accountOverrides(server));
    expect(find.text('ACCOUNT'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await settle(tester);
    expect(find.text('Sign in to get free credits'), findsOneWidget);
  });

  testWidgets('signed in it shows the username and the email', (tester) async {
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    expect(find.text('ann_1'), findsOneWidget);
    expect(find.text('ann@example.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('signing out ends the session', (tester) async {
    server.on('POST', '/auth/logout', (_) => envelope({'loggedOut': true}));
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Sign out'));
    await settle(tester);

    expect(server.lastBody('POST', '/auth/logout'), {'refreshToken': 'r1'});
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Signed out'), findsOneWidget);
  });

  testWidgets('deleting asks first, then deletes with the confirmation',
      (tester) async {
    server.on('DELETE', '/me', (_) => envelope({'deleted': true}));
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Delete account'));
    await settle(tester);
    expect(find.text("Your credits will be lost. This can't be undone."), findsOneWidget);
    expect(server.to('DELETE', '/me'), isEmpty);

    await tester.tap(find.byKey(const Key('delete_account_confirm')));
    await settle(tester);
    expect(server.lastBody('DELETE', '/me'), {'confirm': 'DELETE'});
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Account deleted'), findsOneWidget);
  });

  testWidgets('a deletion that fails says so and keeps the account',
      (tester) async {
    server.on(
      'DELETE',
      '/me',
      (_) => failure('RATE_LIMITED', 429, details: {'retryAfterSeconds': 30}),
    );
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Delete account'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('delete_account_confirm')));
    await settle(tester);

    expect(find.text('Try again in 30s.'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsAccountSection)),
    );
    expect(container.read(accountProvider).isSignedIn, isTrue);
  });

  testWidgets('the username can be changed', (tester) async {
    server
      ..on(
        'GET',
        '/usernames/ann_2/availability',
        (_) => envelope({'username': 'ann_2', 'available': true}),
      )
      ..on('PATCH', '/me/username', (_) => envelope(userJson(username: 'ann_2')));
    await pumpSection(tester, accountOverrides(server, session: signedIn()));
    await tester.tap(find.text('Username'));
    await settle(tester);

    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('username_field')), 'ann_2');
    await tester.pump(kUsernameCheckDelay);
    await settle(tester);
    await tester.tap(save);
    await settle(tester);

    expect(server.lastBody('PATCH', '/me/username'), {'username': 'ann_2'});
    expect(find.text('ann_2'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/features/account/widgets/settings_account_section_test.dart`
Expected: FAIL — `settings_account_section.dart` not found.

- [ ] **Step 3: Move the settings rows out**

Create `lib/core/widgets/settings_rows.dart` holding the three row widgets from `lib/screens/settings_screen.dart` (lines 288–404), renamed public — the bodies unchanged:

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/lucide_icons.dart';

class SettingsSectionHeader extends StatelessWidget {
  final String title;
  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDanger;
  final bool showChevron;

  const SettingsItem({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.isDanger = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDanger
                      ? AppColors.error.withValues(alpha: 0.15)
                      : AppColors.surfaceLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isDanger ? AppColors.error : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDanger
                            ? AppColors.error
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron)
                const Icon(
                  LucideIcons.chevronRight,
                  color: AppColors.textTertiary,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(height: 1, color: AppColors.border.withValues(alpha: 0.4)),
    );
  }
}
```

In `lib/screens/settings_screen.dart`:
- delete the classes `_SectionHeader`, `_SettingsItem` and `_Divider` (lines 288–404);
- replace every `_SectionHeader(` with `SettingsSectionHeader(`, every `_SettingsItem(` with `SettingsItem(`, and every `_Divider()` with `SettingsDivider()`;
- add `import '../core/widgets/settings_rows.dart';` and `import '../features/account/widgets/settings_account_section.dart';`;
- make the section the first child of the `ListView`:

```dart
                      children: [
                        const SettingsAccountSection(),
                        const SettingsSectionHeader(
                          title: 'GENERAL',
                        ).animate().fadeIn(delay: 100.ms),
```

- [ ] **Step 4: Write the section and its two sheets**

Create `lib/features/account/widgets/settings_account_section.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lucide_icons.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/settings_rows.dart';
import '../../video_editor/widgets/panels/editor_sheet.dart';
import '../account_gate.dart';
import '../providers/account_providers.dart';
import 'delete_account_sheet.dart';
import 'username_sheet.dart';

/// Settings' Account section: Sign in when signed out; username, email,
/// sign out and delete account when signed in. Absent in a build with no
/// server.
class SettingsAccountSection extends ConsumerWidget {
  const SettingsAccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(accountFeatureProvider)) return const SizedBox.shrink();
    final user = ref.watch(accountProvider).user;

    void signIn() => unawaited(
          requireAccount(context, ref, reason: 'Sign in to get free credits'),
        );

    final rows = user == null
        ? [SettingsItem(icon: LucideIcons.user, title: 'Sign in', onTap: signIn)]
        : [
            SettingsItem(
              icon: LucideIcons.atSign,
              title: 'Username',
              subtitle: user.username ?? 'Not set',
              onTap: () {
                final current = user.username;
                if (current == null) {
                  signIn(); // not claimed yet: the claim sets the name
                  return;
                }
                unawaited(showEditorSheet<void>(
                  context,
                  builder: (_) => UsernameSheet(current: current),
                ));
              },
            ),
            const SettingsDivider(),
            SettingsItem(
              icon: LucideIcons.mail,
              title: 'Email',
              subtitle: user.email,
              showChevron: false,
              onTap: () {},
            ),
            const SettingsDivider(),
            SettingsItem(
              icon: LucideIcons.logOut,
              title: 'Sign out',
              showChevron: false,
              onTap: () async {
                await ref.read(accountProvider.notifier).signOut();
                if (context.mounted) ToastUtils.show(context, 'Signed out');
              },
            ),
            const SettingsDivider(),
            SettingsItem(
              icon: LucideIcons.trash2,
              title: 'Delete account',
              isDanger: true,
              onTap: () => unawaited(showEditorSheet<void>(
                context,
                builder: (_) => const DeleteAccountSheet(),
              )),
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionHeader(title: 'ACCOUNT'),
        const SizedBox(height: 8),
        GlassCard(padding: EdgeInsets.zero, child: Column(children: rows)),
        const SizedBox(height: 28),
      ],
    );
  }
}
```

Create `lib/features/account/widgets/username_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/toast_utils.dart';
import '../logic/account_copy.dart';
import '../providers/account_providers.dart';
import 'account_sheet_frame.dart';
import 'username_field.dart';

/// Changing the username, under the claim step's rules. No heading: the
/// row the user tapped already said "Username".
class UsernameSheet extends ConsumerStatefulWidget {
  const UsernameSheet({super.key, required this.current});

  final String current;

  @override
  ConsumerState<UsernameSheet> createState() => _UsernameSheetState();
}

class _UsernameSheetState extends ConsumerState<UsernameSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.current);
  bool _available = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountProvider.notifier).changeUsername(_name.text);
      if (!mounted) return;
      ToastUtils.show(context, 'Username changed');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountSheetFrame(
      children: [
        UsernameField(
          controller: _name,
          current: widget.current,
          onAvailability: (ok) => setState(() => _available = ok),
        ),
        if (_error != null) AccountErrorLine(_error!),
        const SizedBox(height: 16),
        AccountPrimaryButton(
          label: 'Save',
          busy: _busy,
          onPressed: _available ? _save : null,
        ),
      ],
    );
  }
}
```

Create `lib/features/account/widgets/delete_account_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/toast_utils.dart';
import '../logic/account_copy.dart';
import '../providers/account_providers.dart';
import 'account_sheet_frame.dart';

/// The step before deleting an account: what is lost, then a destructive
/// button. The server erases the email, username and Google link and
/// forfeits the credits.
class DeleteAccountSheet extends ConsumerStatefulWidget {
  const DeleteAccountSheet({super.key});

  @override
  ConsumerState<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<DeleteAccountSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountProvider.notifier).deleteAccount();
      if (!mounted) return;
      ToastUtils.show(context, 'Account deleted');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountSheetFrame(
      children: [
        const Text(
          "Your credits will be lost. This can't be undone.",
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        if (_error != null) AccountErrorLine(_error!),
        const SizedBox(height: 20),
        AccountPrimaryButton(
          key: const Key('delete_account_confirm'),
          label: 'Delete account',
          danger: true,
          busy: _busy,
          onPressed: _delete,
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `flutter test test/features/account/ test/core/utils/toast_utils_test.dart`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/settings_rows.dart lib/screens/settings_screen.dart lib/features/account/widgets test/features/account/widgets/settings_account_section_test.dart
git commit -m "feat(account): the Account section in Settings — username, sign out, delete

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Auto captions asks first, and runs as the user

**Files:**
- Modify: `lib/features/video_editor/services/caption_access.dart`
- Modify: `lib/features/video_editor/services/caption_errors.dart`
- Modify: `lib/screens/video_editor_screen.dart` (`_startAutoCaptions`, imports)
- Modify: `test/features/video_editor/services/caption_service_test.dart` (the message table)
- Create: `test/features/video_editor/services/caption_access_test.dart`

**Interfaces:**
- Consumes: `requireAccount` (Task 7); `accountSessionProvider`, `accountProvider` (Task 5).
- Produces: `CaptionAccess.ensureAllowed(BuildContext context, WidgetRef ref) → Future<bool>`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/video_editor/services/caption_access_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/services/caption_access.dart';

import '../../../support/account_harness.dart';
import '../../../support/fake_server.dart';

void main() {
  testWidgets('a signed-out user is asked to sign in, and told why',
      (tester) async {
    await pumpHost(
      tester,
      accountOverrides(FakeServer()),
      (context, ref) => CaptionAccess.ensureAllowed(context, ref),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.text('Sign in to use Auto captions'), findsOneWidget);
  });

  test('Auto captions asks for an account before its options, and runs as '
      'the user', () {
    // The screen needs a native engine to build, so this reads the source,
    // as editor_menu_test does.
    // Line endings normalised: a Windows checkout has CRLF.
    final source = File('lib/screens/video_editor_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final start = source.indexOf('Future<void> _startAutoCaptions()');
    expect(start, isNot(-1));
    final body = source.substring(start, source.indexOf('\n  }\n', start));

    final gate = body.indexOf('CaptionAccess.ensureAllowed(context, ref)');
    final options = body.indexOf('AutoCaptionSheet(');
    expect(gate, isNot(-1), reason: 'the gate is called');
    expect(options, isNot(-1));
    expect(gate, lessThan(options), reason: 'signing in comes first');
    expect(body, contains('session: ref.read(accountSessionProvider)'),
        reason: 'the upload shares the app session');
    expect(body, contains('ref.read(accountProvider.notifier).refresh()'),
        reason: 'the balance follows the charge or refund');
  });
}
```

In `test/features/video_editor/services/caption_service_test.dart`, add three entries to the `expected` map in the `'every cause has its one line'` test:

```dart
        'SIGN_IN_REQUIRED': 'Sign in again to use Auto captions.',
        'INSUFFICIENT_CREDITS': 'Not enough credits for these captions.',
        'ACCOUNT_SUSPENDED': 'This account is suspended.',
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/features/video_editor/services/caption_access_test.dart test/features/video_editor/services/caption_service_test.dart`
Expected: FAIL — `ensureAllowed` takes one argument; the source test cannot find `CaptionAccess.ensureAllowed(context, ref)`; the three codes give the generic transcription line.

- [ ] **Step 3: Implement**

Replace `lib/features/video_editor/services/caption_access.dart` with:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_gate.dart';

/// The one door every auto-caption run passes, before its options open: a
/// signed-in, claimed account. The sign-in and claim sheets come first when
/// it is not.
class CaptionAccess {
  const CaptionAccess._();

  static Future<bool> ensureAllowed(BuildContext context, WidgetRef ref) =>
      requireAccount(context, ref, reason: 'Sign in to use Auto captions');
}
```

In `lib/features/video_editor/services/caption_errors.dart`, add these arms to the `switch` in `captionErrorMessage`, right after the `SlimshotApiException.network` arm:

```dart
    SlimshotApiException.signInRequired => 'Sign in again to use Auto captions.',
    'INSUFFICIENT_CREDITS' => 'Not enough credits for these captions.',
    'ACCOUNT_SUSPENDED' => 'This account is suspended.',
```

In `lib/screens/video_editor_screen.dart`:
- replace `import '../core/services/account_session.dart';` (added in Task 3) with `import '../features/account/providers/account_providers.dart';`;
- in `_startAutoCaptions`, move the gate to the top and drop it from after the options sheet; share the session; refresh the balance after the run. The method's start becomes:

```dart
  Future<void> _startAutoCaptions() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    if (!await CaptionAccess.ensureAllowed(context, ref) || !mounted) return;
    final request = await showEditorSheet<CaptionRequest>(
      context,
      builder: (_) => AutoCaptionSheet(
        initial: ref.read(videoEditorProvider).captionSettings,
      ),
    );
    if (request == null || !mounted) return;
    if (ref.read(videoEditorProvider).hasCaptions &&
        !await confirmReplaceCaptions(context)) {
      return;
    }
    if (!mounted) return;
```

  the client line becomes:

```dart
    final api = SlimshotApi(
      baseUrl: SlimshotApi.configuredBaseUrl,
      session: ref.read(accountSessionProvider),
    );
```

  and right after the progress sheet closes (`api.close();`), add:

```dart
    // The run may have spent credits, or had them refunded: the balance on
    // the home screen follows.
    unawaited(ref.read(accountProvider.notifier).refresh());
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `flutter test test/features/video_editor/services/ test/features/video_editor/widgets/editor_menu_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/video_editor/services/caption_access.dart lib/features/video_editor/services/caption_errors.dart lib/screens/video_editor_screen.dart test/features/video_editor/services
git commit -m "feat(captions): sign in before Auto captions, and caption as the user

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Record it, and verify the whole branch

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

In the "Auto captions — generating a set (Stage 1)" section, replace the sentence

> Sign-in and credits come later and have exactly one hook: `CaptionAccess.ensureAllowed`, called once before any audio is rendered, which always opens today.

with

> Sign-in and credits have exactly one hook: `CaptionAccess.ensureAllowed`, called before the options sheet opens — see "Accounts and credits".

and replace the sentence beginning "It registers the device once, keeps the token in `shared_preferences`" through "a test with the `if` turned into a `while` hangs." with

> Its requests come in three kinds — signed in, sign-in and public — described in "Accounts and credits".

Then add, before "### Decisions already made", this section:

```markdown
### Accounts and credits — stage 1: sign-in, claim, the pill, Settings

**Awaiting device verification.** Spec:
`docs/superpowers/specs/2026-10-05-app-accounts-credits-design.md`; plan
`docs/superpowers/plans/2026-10-05-accounts-stage1.md`. Server contract:
`slimshot_server/docs/app-credits-api.md`. Stages 2 (the price step) and 3 (rewarded ads,
invites, the Credits screen) follow.

**Signing in is optional; Auto captions is the first thing that needs it.** Google (the
phone's account picker through `google_sign_in` 7, the Web client ID from
`--dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=…`, the button hidden without it) or an emailed
6-digit code. The first sign-in makes the account; a new account then chooses a username and
claims its free credits (`ClaimSheet`). **No number is promised before the claim** — the
bonus is the admin's to set and not every email or phone is eligible — so the home pill says
"Free credits" and only the claim names an amount. No Android ID anywhere: the server's
per-device rule is per install.

**Every secret is in the keystore** (`TokenVault`, `flutter_secure_storage`): the access and
refresh tokens, the install token — moved there from `shared_preferences` the first time it is
read — and the cached `/me`. A value that cannot be decrypted (a backup restored without its
keystore key) reads as absent, which leaves the app signed out rather than crashing.

**One session, shared** (`AccountSession`, `accountSessionProvider`). **Refreshes take
turns**: the server lets a refresh token work once and treats a second use as theft, ending
the session, so `refreshAfter` serialises them — a request refused with an access token that
has since been replaced just retries with the new one. Only a **401** on the refresh ends a
session; a 5xx or a proxy page is thrown and the session kept. Any request that ends the
session — a caption upload included — fires `ended`, and `AccountNotifier` flips the whole
app to signed out.

**`SlimshotApi` has three kinds of request.** `send` is signed in: the access token as a
bearer, one refresh on `UNAUTHENTICATED`, then `SIGN_IN_REQUIRED` — never a loop.
`sendWithDevice` is a sign-in: no bearer, the install token in the body, a
`DEVICE_NOT_REGISTERED` install registered again once. `sendPublic` carries neither.
The install token is **not** an access token: the server refuses it as a bearer.

**`requireAccount` is the one door** (`features/account/account_gate.dart`): a kept session
whose profile has not loaded is refreshed rather than asked to sign in; signed out, the
sign-in sheet; unclaimed, the claim sheet. `CaptionAccess.ensureAllowed` is it, called
**before** the Auto captions options sheet, and the caption client is built on the shared
session. After a run the profile is read again so the pill follows the charge — until stage 2
there is no confirm before the server charges.

**The signed-in state is app-wide** (`accountProvider`, not autoDispose): the cached profile
at once, then `/me`; offline, the cached one stays. A profile that lands after sign-out is not
written back (`_adopt` checks the session first). Sign-out works offline — the server is told
if it can be. Account sheets are capped at 480 px and open through `showEditorSheet`.
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze --no-pub`
Expected: `48 issues found.` If higher, fix every new issue the new or changed files introduced and run again.

- [ ] **Step 3: Run the whole suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Build the APK**

Run: `flutter build apk --debug`
Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: accounts stage 1 in CLAUDE.md

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Device test for the owner (after the branch is reviewed)

Run with `flutter run --dart-define=SLIMSHOT_API_URL=http://<lan-ip>:2700 --dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=<web-client-id>` against the server's `feat/accounts-credits` with `EMAIL_SENDER=log` (the code appears in the server console):

1. Home shows "Free credits"; Settings shows Account → Sign in.
2. Email sign-in: code arrives in the server log, wrong code shows tries left, right code signs in.
3. Claim: availability tick, "+100 credits", the pill shows 100.
4. Auto captions while signed out asks to sign in first; signed in, a run captions and the pill drops by the price.
5. Settings: change username, sign out, sign in again, delete account (pill back to "Free credits").
6. Google sign-in, once the Google Cloud clients exist (spec §9).
