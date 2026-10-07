import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/features/account/providers/account_providers.dart';
import 'package:slimshotai/features/account/services/credit_ads.dart';
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

/// The rewarded ad, scripted: [playback] is how the next one ends, and
/// [failure] the reason given when none showed.
class FakeRewardedAdPlayer implements RewardedAdPlayer {
  AdPlayback playback = AdPlayback.earned;
  String? failure;

  /// When set, a play waits on it — an ad still loading.
  Completer<AdPlay>? hold;

  /// (userId, customData) of every ad played.
  final List<(String, String)> plays = [];

  int prepares = 0;

  @override
  Future<void> prepare() async => prepares++;

  @override
  Future<AdPlay> play({
    required String userId,
    required String customData,
  }) async {
    plays.add((userId, customData));
    final held = hold;
    if (held != null) return held.future;
    return AdPlay(playback, failure: failure);
  }
}

/// Accounts switched on, against [server], with [session] (signed out when
/// omitted) and a scripted Google.
List<Override> accountOverrides(
  FakeServer server, {
  AccountSession? session,
  GoogleIdTokens? google,
  FakeRewardedAdPlayer? ads,
  List<String>? shared,
}) {
  final shared0 = session ?? AccountSession(vault: MemoryTokenVault());
  final player = ads ?? FakeRewardedAdPlayer();
  var now = DateTime(2026, 10, 6);
  return [
    accountFeatureProvider.overrideWithValue(true),
    accountSessionProvider.overrideWithValue(shared0),
    accountApiProvider.overrideWithValue(fakeApi(server, session: shared0)),
    googleIdTokensProvider.overrideWithValue(google ?? FakeGoogleIdTokens()),
    rewardedAdPlayerProvider.overrideWithValue(player),
    // The poll on a clock the test owns: no real second goes by.
    creditAdServiceProvider.overrideWith(
      (ref) => CreditAdService(
        account: ref.watch(accountServiceProvider),
        player: player,
        delay: (d) async => now = now.add(d),
        clock: () => now,
      ),
    ),
    shareTextProvider.overrideWithValue((text) async => shared?.add(text)),
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
