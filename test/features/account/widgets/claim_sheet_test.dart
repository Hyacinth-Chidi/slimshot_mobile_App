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
  // The server's truth: an account is unclaimed until a claim succeeds.
  late bool claimed;

  setUp(() {
    claimed = false;
    server = FakeServer()
      ..on(
        'GET',
        '/me',
        (_) => envelope(
          claimed ? userJson() : userJson(needsClaim: true, balance: 0),
        ),
      )
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
      ..on('POST', '/me/claim', (_) {
        claimed = true;
        return envelope({
          'user': userJson(balance: 100),
          'bonus': {'granted': true, 'credits': 100},
          'referral': null,
        });
      });
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
    // As in the app, the account is known before the claim sheet opens: the
    // gate that opens it reads it first.
    containerOf(tester).read(accountProvider);
    await settle(tester);
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
