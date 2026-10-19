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

  tearDown(() async {
    // Windows may still hold a file the sheet just wrote; a temp folder left
    // behind is not a failure of the sheet.
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } on FileSystemException {
      // left for the OS to sweep
    }
  });

  /// Taps [finder] in real time: what the tap starts writes real files,
  /// which a fake clock never lets finish.
  Future<void> tapAndWork(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await settle();
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

  testWidgets('a row shows title, duration and a plus', (tester) async {
    await openSheet(tester);
    expect(find.text('Sound a'), findsOneWidget);
    expect(find.text('0.8s'), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.plus), findsNWidgets(2));
  });

  testWidgets('tapping + adds, closes, and calls onAdd once', (tester) async {
    await openSheet(tester);
    await tapAndWork(tester, find.byKey(const ValueKey('sfx_add_a')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(added.map((s) => s.id), ['a']);
    expect(find.byType(SoundEffectsSheet), findsNothing);
  });

  testWidgets('tapping a row plays it and shows pause', (tester) async {
    await openSheet(tester);
    await tapAndWork(tester, find.text('Sound a'));
    expect(h.player.played.single, endsWith('a.mp3'));
    expect(find.byIcon(LucideIcons.pause), findsOneWidget);
  });

  testWidgets('offline shows the line and Retry asks again', (tester) async {
    h.server.overrides['categories'] = () => throw const SocketException('down');
    await openSheet(tester);
    expect(find.text("You're offline"), findsOneWidget);
    h.server.overrides.remove('categories');
    final before = h.server.hitsFor('categories');
    await tapAndWork(tester, find.text('Retry'));
    expect(h.server.hitsFor('categories'), before + 1);
    expect(find.text("You're offline"), findsNothing);
  });

  testWidgets('an empty pill says so', (tester) async {
    h.server.pages['impacts'] = [[]];
    await openSheet(tester);
    expect(find.text('No sounds here yet.'), findsOneWidget);
  });

  testWidgets('a failed download toasts', (tester) async {
    h.server.overrides['download:a'] = () => FakeCatalogServer.error('INTERNAL', 500);
    await openSheet(tester);
    await tapAndWork(tester, find.byKey(const ValueKey('sfx_add_a')));
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
