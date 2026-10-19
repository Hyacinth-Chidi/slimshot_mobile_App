import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/sound_library/data/sound_library.dart';
import 'package:slimshotai/features/sound_library/sound_effects_controller.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/sound_effects_sheet.dart';

import '../../sound_library/support.dart';

void main() {
  late Directory root;
  late ControllerHarness h;
  late SoundEffectsController c;
  late List<LibrarySound> added;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sfx_sheet_test');
    h = ControllerHarness(root);
    added = [];
  });

  tearDown(() => deleteTemp(root));

  /// Taps [finder] in real time: what the tap starts writes real files,
  /// which a fake clock never lets finish.
  Future<void> tapAndWork(
    WidgetTester tester,
    Finder finder, {
    bool Function()? until_,
  }) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      if (until_ != null) {
        await until(until_);
      } else {
        await settle();
      }
    });
    await tester.pump();
  }

  /// Opens the sheet over a page, the way the editor does, with the
  /// controller already past its first load.
  Future<void> openSheet(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    double textScale = 1.0,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    c = h.build();
    await tester.runAsync(() async {
      await c.open();
      await settle();
    });
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showEditorSheet<void>(
                context,
                builder: (_) => SoundEffectsSheet(controller: c, onAdd: added.add),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('shows Downloaded first and the server pills after', (tester) async {
    await openSheet(tester);
    final downloaded = tester.getTopLeft(find.text('Downloaded'));
    final impacts = tester.getTopLeft(find.text('Impacts'));
    final memes = tester.getTopLeft(find.text('Funny & Memes'));
    expect(downloaded.dx, lessThan(impacts.dx));
    expect(impacts.dx, lessThan(memes.dx));
  });

  testWidgets('a sound not on the phone shows download, never +', (tester) async {
    await openSheet(tester);
    expect(find.text('Sound a'), findsOneWidget);
    expect(find.text('0.8s'), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.download), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.plus), findsNothing);
  });

  testWidgets('the download icon downloads, then the row offers +', (tester) async {
    await openSheet(tester);
    await tapAndWork(tester, find.byKey(const ValueKey('sfx_download_a')),
        until_: () => c.inLibrary('a'));
    expect(h.player.played, isEmpty, reason: 'downloading is not listening');
    expect(added, isEmpty, reason: 'downloading is not adding');
    expect(find.byKey(const ValueKey('sfx_add_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('sfx_download_b')), findsOneWidget);
  });

  testWidgets('tapping + adds, closes, and calls onAdd once', (tester) async {
    await openSheet(tester);
    await tapAndWork(tester, find.byKey(const ValueKey('sfx_download_a')),
        until_: () => c.inLibrary('a'));
    await tapAndWork(tester, find.byKey(const ValueKey('sfx_add_a')),
        until_: () => added.isNotEmpty);
    await tester.pump(const Duration(milliseconds: 600));
    expect(added.map((s) => s.id), ['a']);
    expect(find.byType(SoundEffectsSheet), findsNothing);
  });

  testWidgets('tapping a row plays it and shows pause', (tester) async {
    await openSheet(tester);
    await tapAndWork(tester, find.text('Sound a'),
        until_: () => h.player.played.isNotEmpty);
    expect(h.player.played.single, endsWith('a.mp3'));
    expect(find.byIcon(LucideIcons.pause), findsOneWidget);
  });

  testWidgets('offline shows the line and Retry asks again', (tester) async {
    h.server.overrides['categories'] = () => throw const SocketException('down');
    await openSheet(tester);
    expect(find.text("You're offline"), findsOneWidget);
    h.server.overrides.remove('categories');
    final before = h.server.hitsFor('categories');
    await tapAndWork(tester, find.text('Retry'),
        until_: () => !c.offline);
    expect(h.server.hitsFor('categories'), before + 1);
    expect(find.text("You're offline"), findsNothing);
  });

  testWidgets('a pill with a second page loads it without a build error',
      (tester) async {
    h.server.pages['impacts'] = [
      [soundRow('a'), soundRow('b')],
      [soundRow('c')],
    ];
    await openSheet(tester);
    await tester.runAsync(() => until(() => !c.hasMore));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Sound c'), findsOneWidget);
  });

  testWidgets('offline, rows stay as they are and download says why it cannot',
      (tester) async {
    await openSheet(tester);
    // The connection drops after the rows were shown.
    h.server.overrides['categories'] = () => throw const SocketException('down');
    h.server.overrides['assets:impacts:-'] = () => throw const SocketException('down');
    h.server.overrides['download:a'] = () => throw const SocketException('down');
    await tester.runAsync(() async {
      await c.refresh();
      await settle();
    });
    await tester.pump();
    expect(c.offline, isTrue);
    expect(find.text("You're offline"), findsOneWidget);
    final row = find.ancestor(of: find.text('Sound a'), matching: find.byType(Opacity));
    for (final o in tester.widgetList<Opacity>(row)) {
      expect(o.opacity, 1.0, reason: 'not dimmed');
    }
    await tapAndWork(tester, find.byKey(const ValueKey('sfx_download_a')),
        until_: () => h.server.hitsFor('download:a') > 0 && c.progressOf('a') == null);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No internet connection'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an empty pill says so', (tester) async {
    h.server.pages['impacts'] = [[]];
    await openSheet(tester);
    expect(find.text('No sounds here yet.'), findsOneWidget);
  });

  testWidgets('search narrows the rows', (tester) async {
    await openSheet(tester);
    expect(find.text('Search'), findsOneWidget, reason: "the old sheet's field");
    await tester.enterText(find.byType(TextField), 'sound b');
    await tester.pump();
    expect(find.text('Sound a'), findsNothing);
    expect(find.text('Sound b'), findsOneWidget);
  });

  testWidgets('the categories are tabs, the current one underlined', (tester) async {
    await openSheet(tester);
    final tab = tester.widget<Container>(find
        .ancestor(of: find.text('Impacts'), matching: find.byType(Container))
        .first);
    final border = (tab.decoration as BoxDecoration?)?.border as Border?;
    expect(border?.bottom.width, 2);
  });

  testWidgets('a failed download toasts', (tester) async {
    h.server.overrides['download:a'] = () => FakeCatalogServer.error('INTERNAL', 500);
    await openSheet(tester);
    await tapAndWork(tester, find.byKey(const ValueKey('sfx_download_a')),
        until_: () => c.progressOf('a') == null && h.server.hitsFor('download:a') > 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Couldn't download Sound a"), findsOneWidget);
    expect(added, isEmpty);
    // Let the toast leave.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('no overflow at 320px with text at 1.3x', (tester) async {
    final long = List.filled(12, 'Extraordinarily').join(' ');
    h.server.pages['impacts'] = [
      [
        {...soundRow('a'), 'title': long},
        {...soundRow('b', durationMs: 65000), 'title': long},
      ],
    ];
    h.server.categories = [
      {'id': 'i', 'slug': 'impacts', 'name': 'Impacts', 'children': []},
      for (final name in ['Funny & Memes', 'Objects & Machines', 'Tech & Digital'])
        {'id': name, 'slug': name.toLowerCase().replaceAll(' ', ''), 'name': name, 'children': []},
    ];
    await openSheet(tester, size: const Size(320, 640), textScale: 1.3);
    expect(find.text(long), findsNWidgets(2));
    expect(find.text('1:05'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapAndWork(tester, find.text(long).first);
    expect(tester.takeException(), isNull);
  });
}
