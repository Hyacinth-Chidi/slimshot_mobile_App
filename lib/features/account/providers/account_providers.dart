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
    final ticket = _nextTicket();
    try {
      await _adopt(await _service.me(), ticket);
    } on SlimshotApiException catch (e) {
      debugPrint('AccountNotifier.refresh: ${e.code}');
    }
  }

  Future<void> completeSignIn(SignInResult result) async {
    final ticket = _nextTicket();
    await _session.save(result.tokens);
    await _adopt(result.user, ticket);
  }

  Future<ClaimResult> claim({
    required String username,
    String? referralCode,
  }) async {
    final ticket = _nextTicket();
    final result = await _service.claim(
      username: username,
      referralCode: referralCode,
    );
    await _adopt(result.user, ticket);
    return result;
  }

  Future<void> changeUsername(String name) async {
    final ticket = _nextTicket();
    await _adopt(await _service.changeUsername(name), ticket);
  }

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
    await _forget();
  }

  /// Deletes the account on the server, then forgets it here. A refusal
  /// keeps everything and throws, so the confirm sheet can say why.
  Future<void> deleteAccount() async {
    await _service.deleteAccount();
    await _forget();
  }

  /// Ends the session and shows it ended **now**: the session's `ended`
  /// event is delivered a step later, and whoever awaited a sign-out reads
  /// the state straight after it.
  Future<void> _forget() async {
    unawaited(_google.signOut());
    await _session.end();
    if (mounted) state = const AccountState();
  }

  /// Every request whose answer becomes the profile takes a ticket when it
  /// **starts**. Answers can land in any order — the launch's `/me` after a
  /// claim made since, say — and an answer older than the last one adopted
  /// would put back a profile the user has already moved past.
  int _issued = 0;
  int _adopted = 0;

  int _nextTicket() => ++_issued;

  /// Shows and keeps [user], the answer to the request that took [ticket] —
  /// unless a newer answer was adopted first, or the session ended while it
  /// was on its way, in which case nothing personal is written back.
  ///
  /// The ticket and the state change together, with no wait between: an
  /// answer dropped as older can then rely on the newer one already being on
  /// screen. A keystore write is slow enough for a sign-out to land in the
  /// middle of it, so the session is checked again once the profile is
  /// written, and a profile that outlived its session is taken back.
  Future<void> _adopt(AccountUser user, int ticket) async {
    if (ticket < _adopted || await _session.read() == null) return;
    if (ticket < _adopted) return; // a newer answer landed during the read
    _adopted = ticket;
    if (mounted) state = AccountState(user: user);
    await _session.saveProfile(jsonEncode(user.toJson()));
    if (await _session.read() == null) await _session.end();
  }

  @override
  void dispose() {
    unawaited(_ended.cancel());
    super.dispose();
  }
}
