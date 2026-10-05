import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/widgets/frosted_glass.dart';
import 'package:slimshotai/features/account/widgets/sign_in_sheet.dart';
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

  testWidgets("the sign-in sheet stays plain dark, as the editor's sheets are",
      (tester) async {
    await pumpHost(
      tester,
      accountOverrides(FakeServer()),
      (context, ref) => CaptionAccess.ensureAllowed(context, ref),
    );
    await tester.tap(find.text('open'));
    await settle(tester);

    expect(find.byType(SignInSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SignInSheet),
        matching: find.byType(FrostedGlass),
      ),
      findsNothing,
    );
  });

  test(
      'Auto captions asks for an account before its options, and runs as '
      'the user', () {
    // The screen needs a native engine to build, so this reads the source,
    // as editor_menu_test does. Line endings normalised: a Windows checkout
    // has CRLF.
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
