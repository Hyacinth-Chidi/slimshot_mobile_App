import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/legal/legal_links.dart';
import 'package:slimshotai/core/legal/settings_legal_section.dart';

void main() {
  late List<Uri> opened;
  late bool opens;

  setUp(() {
    opened = [];
    opens = true;
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        legalLinkOpenerProvider.overrideWithValue((url) async {
          opened.add(url);
          return opens;
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SettingsLegalSection())),
      ),
    ));
    await tester.pump();
  }

  testWidgets('offers the privacy policy, the terms and the licences',
      (tester) async {
    await pump(tester);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Open-source licences'), findsOneWidget);
  });

  testWidgets('each page opens at its own address', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Terms of Service'));
    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();
    expect(opened, [Uri.parse(kTermsOfServiceUrl), Uri.parse(kPrivacyPolicyUrl)]);
  });

  testWidgets('a page that will not open says so', (tester) async {
    opens = false;
    await pump(tester);
    await tester.tap(find.text('Terms of Service'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Could not open the Terms of Service'), findsOneWidget);
  });

  test('both pages live on the SlimShot website, over HTTPS', () {
    for (final url in [kPrivacyPolicyUrl, kTermsOfServiceUrl]) {
      final uri = Uri.parse(url);
      expect(uri.scheme, 'https');
      expect(uri.host, 'slimshotai.vercel.app');
    }
    expect(Uri.parse(kTermsOfServiceUrl).path, '/terms');
    expect(Uri.parse(kPrivacyPolicyUrl).path, '/privacy');
  });
}
