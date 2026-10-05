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
