import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/legal/third_party_licences.dart';

/// The ported transitions ship compiled into the app, so MIT asks for their
/// notice in it — a code comment is stripped from the APK and does not count.
void main() {
  Future<List<LicenseEntry>> glEntries() async => [
        await for (final entry in LicenseRegistry.licenses)
          if (entry.packages.contains(kGlTransitionsPackage)) entry,
      ];

  test('the GL Transitions notice is on the licences page, once', () async {
    registerThirdPartyLicences();
    registerThirdPartyLicences();
    final entries = await glEntries();
    expect(entries, hasLength(1));
    final text = entries.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('Copyright (c) 2017-present gl-transitions contributors'));
    expect(text, contains('Permission is hereby granted, free of charge'));
    for (final author in kGlTransitionsAuthors) {
      expect(text, contains(author), reason: author);
    }
  });

  test('the bundled fonts carry their OFL notices', () async {
    registerThirdPartyLicences();
    final entries = await LicenseRegistry.licenses.toList();
    for (final font in ['Montserrat', 'Bebas Neue', 'Poppins', 'Plus Jakarta Sans']) {
      final notices = entries.where((e) => e.packages.contains(font)).toList();
      expect(notices, hasLength(1), reason: font);
      final text = notices.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL Open Font License'), reason: font);
      expect(text, contains('Copyright'), reason: font);
    }
  });

  testWidgets('the licences open on the root navigator, over the tabs', (tester) async {
    final root = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: root,
      home: Scaffold(
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (context) => TextButton(
              onPressed: () => openSourceLicences(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LicensePage), findsOneWidget);
    // Pushed on the app's own navigator, not the tab's nested one.
    expect(root.currentState!.canPop(), isTrue);
  });
}
