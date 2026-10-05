import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/screens/home_header.dart';

import '../support/account_fakes.dart';
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

  testWidgets('a short balance sits at the right edge, clear of the brand',
      (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final server = FakeServer()
      ..on('GET', '/me', (_) => envelope(userJson(balance: 500)));
    await tester.pumpWidget(
      ProviderScope(
        overrides: accountOverrides(
          server,
          session: signedInSession(profile: userJson(balance: 500)),
        ),
        child: const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: HomeHeader(
                brand: SizedBox(key: Key('brand'), width: 230, height: 44),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    final pill = tester.getRect(find.byKey(const Key('credits_pill_balance')));
    final brand = tester.getRect(find.byKey(const Key('brand')));
    expect(pill.right, closeTo(400 - 24, 0.01), reason: 'pinned to the edge');
    expect(pill.left - brand.right, greaterThanOrEqualTo(16));
  });
}
