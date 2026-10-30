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

  test(
      'Auto captions asks for an account before its options, and runs as '
      'the user', () {
    // The screen needs a native engine to build, so this reads the source,
    // as editor_menu_test does. Line endings normalised: a Windows checkout
    // has CRLF.
    final source = File('lib/screens/video_editor_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    String bodyOf(String signature) {
      final start = source.indexOf(signature);
      expect(start, isNot(-1), reason: signature);
      return source.substring(start, source.indexOf('\n  }\n', start));
    }

    final body = bodyOf('Future<void> _startAutoCaptions()');
    final gate = body.indexOf('CaptionAccess.ensureAllowed(context, ref)');
    final options = body.indexOf('AutoCaptionSheet(');
    expect(gate, isNot(-1), reason: 'the gate is called');
    expect(options, isNot(-1));
    expect(gate, lessThan(options), reason: 'signing in comes first');
    expect(body, contains('ref.read(accountProvider.notifier).refresh()'),
        reason: 'the balance follows the charge or refund');

    // The run itself is built in one place, for the editor and for
    // captions made from Home alike.
    final pipeline = bodyOf('_newCaptionPipeline() {');
    expect(pipeline, contains('session: ref.read(accountSessionProvider)'),
        reason: 'the upload shares the app session');
    expect(pipeline, contains('quotePrice:'),
        reason: 'the run is priced by the server before it uploads');
    expect(pipeline, contains('AccountService.autoCaptionsFeature'));
    expect(pipeline, contains('.applyBalance('),
        reason: "the charge's balance reaches the pill at once");

    // From Home, Generate is the same door: signing in before the run.
    final generate = bodyOf('Future<void> _generateCaptions()');
    final homeGate =
        generate.indexOf('CaptionAccess.ensureAllowed(context, ref)');
    expect(homeGate, isNot(-1));
    expect(homeGate, lessThan(generate.indexOf('_newCaptionPipeline()')),
        reason: 'signing in comes first');
  });
}
