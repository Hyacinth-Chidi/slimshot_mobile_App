import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/fonts/data/font_catalog_cache.dart';
import 'package:slimshotai/features/fonts/data/font_client.dart';
import 'package:slimshotai/features/fonts/data/font_library.dart';
import 'package:slimshotai/features/fonts/data/font_preview_cache.dart';
import 'package:slimshotai/features/fonts/font_registry.dart';
import 'package:slimshotai/features/fonts/font_service.dart';
import 'package:slimshotai/features/fonts/providers.dart';
import 'package:slimshotai/features/fonts/widgets/font_grid_view.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_editor_dialog.dart';

import '../../support/test_fonts.dart';
import '../sound_library/support.dart' show deleteTemp;
import 'support.dart';

void main() {
  late Directory root;
  late FakeFontServer server;
  late List<String> registered;

  setUp(() {
    root = Directory.systemTemp.createTempSync('font_grid_view_test');
    server = FakeFontServer();
    registered = [];
  });

  // Windows may still hold a preview file the grid was reading.
  tearDown(() => deleteTemp(root));

  List<Override> overrides() {
    final client = FontClient(server.api());
    final library = FontLibrary(client: server.client, root: root);
    final cache = FontCatalogCache(root: root);
    return [
      fontServerConfiguredProvider.overrideWithValue(true),
      fontClientProvider.overrideWithValue(client),
      fontLibraryProvider.overrideWithValue(library),
      fontCatalogCacheProvider.overrideWithValue(cache),
      fontPreviewCacheProvider.overrideWithValue(FontPreviewCache(client: server.client, root: root)),
      fontServiceProvider.overrideWithValue(FontService(
        client: client,
        library: library,
        cache: cache,
        registry: FontRegistry(loader: (bytes, name) async => registered.add(name)),
      )),
    ];
  }

  /// Lets the real file and network work started by the grid finish.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Finder tile(String name) => find.byKey(ValueKey('font:$name'));

  Future<List<String>> openGrid(WidgetTester tester, {String selected = 'Roboto'}) async {
    final chosen = <String>[];
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: overrides(),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 250,
            child: StatefulBuilder(
              builder: (context, setState) => FontGridView(
                selectedName: selected,
                onSelected: (name) => setState(() {
                  chosen.add(name);
                  selected = name;
                }),
              ),
            ),
          ),
        ),
      ),
    ));
    await pumpUntil(tester, () => tile('Righteous').evaluate().isNotEmpty);
    return chosen;
  }

  testWidgets('tiles in grid order, three to a row', (tester) async {
    await openGrid(tester);
    final order = ['Roboto', 'Montserrat Bold', 'Bebas Neue', 'Poppins', 'Playfair Display'];
    final tops = [for (final name in order) tester.getTopLeft(tile(name))];
    expect(tops[0].dy, tops[1].dy);
    expect(tops[1].dy, tops[2].dy);
    expect(tops[0].dx < tops[1].dx && tops[1].dx < tops[2].dx, isTrue);
    expect(tops[3].dy, greaterThan(tops[2].dy));
    expect(tops[3].dx, tops[0].dx);
    expect(tops[4].dy, tops[3].dy);
    expect(find.descendant(of: tile('Roboto'), matching: find.text('SYSTEM')), findsOneWidget);
  });

  testWidgets('a server tile shows its preview, with an arrow until downloaded', (tester) async {
    await openGrid(tester);
    await pumpUntil(
      tester,
      () => find.descendant(of: tile('Playfair Display'), matching: find.byType(Image)).evaluate().isNotEmpty,
    );
    final image = tester.widget<Image>(
      find.descendant(of: tile('Playfair Display'), matching: find.byType(Image)),
    );
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).imageProvider, isA<FileImage>());
    expect(find.descendant(of: tile('Playfair Display'), matching: find.byIcon(LucideIcons.download)),
        findsOneWidget);
    expect(find.descendant(of: tile('Bebas Neue'), matching: find.byIcon(LucideIcons.download)),
        findsNothing);
  });

  testWidgets("the selected font's tile wears the selected border", (tester) async {
    await openGrid(tester, selected: 'Bebas Neue');
    Color borderOf(String name) {
      final box = tester.widget<Container>(
        find.descendant(of: tile(name), matching: find.byKey(const ValueKey('font-tile-box'))),
      );
      return ((box.decoration as BoxDecoration).border as Border).top.color;
    }

    expect(borderOf('Bebas Neue'), AppColors.primaryStart);
    expect(borderOf('Poppins'), AppColors.border);
  });

  testWidgets('a tap on a bundled tile selects it at once', (tester) async {
    final chosen = await openGrid(tester);
    await tester.tap(tile('Poppins'));
    await tester.pump();
    expect(chosen, ['Poppins']);
    expect(server.hitsFor('download:pp'), 0);
  });

  testWidgets('a tap on a server tile shows a ring, then selects it', (tester) async {
    final chosen = await openGrid(tester);
    final gate = server.gates['file:pd'] = Completer<void>();
    await tester.tap(tile('Playfair Display'));
    await pumpUntil(
      tester,
      () => find.descendant(of: tile('Playfair Display'), matching: find.byType(CircularProgressIndicator))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.descendant(of: tile('Playfair Display'), matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    expect(chosen, isEmpty);
    gate.complete();
    await pumpUntil(tester, () => chosen.isNotEmpty);
    expect(chosen, ['Playfair Display']);
    expect(registered, ['Playfair Display']);
    expect(find.descendant(of: tile('Playfair Display'), matching: find.byIcon(LucideIcons.download)),
        findsNothing);
  });

  testWidgets('typing in search narrows the tiles', (tester) async {
    await openGrid(tester);
    await tester.enterText(find.byType(TextField), 'bebas');
    await tester.pump();
    expect(tile('Bebas Neue'), findsOneWidget);
    expect(tile('Roboto'), findsNothing);
    expect(tile('Playfair Display'), findsNothing);
  });

  testWidgets("the text editor's Font tab is the grid", (tester) async {
    final overlay = TextOverlayModel(id: 't', text: 'Hello', fontFamily: kTestFontFamily);
    final notifier = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(textOverlays: [overlay]);
    await tester.pumpWidget(ProviderScope(
      overrides: [videoEditorProvider.overrideWith((ref) => notifier), ...overrides()],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(videoEditorProvider);
              return ElevatedButton(
                onPressed: () => showTextEditor(
                  context: context,
                  overlay: overlay,
                  ref: ref,
                  initialTool: TextEditorTool.font,
                ),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<FontGridView>(find.byType(FontGridView)).selectedName, kTestFontFamily);
    await pumpUntil(tester, () => tile('Bebas Neue').evaluate().isNotEmpty);
    await tester.tap(tile('Bebas Neue'));
    await tester.pump();
    expect(notifier.state.textOverlays.single.fontFamily, 'Bebas Neue');
  });
}
