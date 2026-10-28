import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/core/widgets/frosted_glass.dart';
import 'package:slimshotai/main.dart';

/// The gallery, scripted: every pick returns [images].
class _FakePicker extends ImagePickerPlatform {
  _FakePicker(this.images);

  final List<XFile> images;
  int picks = 0;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    picks++;
    return images;
  }

  /// What "New video" asks for: videos and photos together.
  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async {
    picks++;
    return media;
  }

  List<XFile> media = const [];
}

Future<void> _settle(WidgetTester tester) async {
  // The home screen has looping animations, so it never settles by itself.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _FakePicker picker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('home_cards');
    final photo = File('${dir.path}/a.png')
      ..writeAsBytesSync(File('assets/logo.png').readAsBytesSync());
    picker = _FakePicker([XFile(photo.path)]);
    ImagePickerPlatform.instance = picker;
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    initializeAppRouter('/home');
    await tester.pumpWidget(
        const ProviderScope(child: SlimShotApp(enableShareIntents: false)));
    await _settle(tester);
  }

  // Device-reported: a tap near a card's corner sometimes opened a blank
  // page with only the floating nav, until Back. The corner held a
  // decorative circle that was an `OpenContainer` — a widget that opens a
  // page when tapped — whose page was an empty box, pushed inside the home
  // tab. Wherever a card is touched, it must do what the card says.
  for (final (card, route) in [
    ('Compress\nPhoto', '/compress/image'),
    ('Privacy\nStrip', '/privacy'),
  ]) {
    testWidgets('a tap anywhere on "$card" opens the gallery and its screen',
        (tester) async {
      await pumpHome(tester);
      final box = tester.getRect(find.ancestor(
        of: find.text(card),
        matching: find.byType(GestureDetector),
      ).first);
      // The bottom-right corner, where the decorative circle sits.
      await tester.tapAt(box.bottomRight - const Offset(10, 10));
      await _settle(tester);

      expect(picker.picks, 1);
      expect(
        appRouter.routerDelegate.currentConfiguration.matches
            .map((m) => m.matchedLocation),
        ['/home', route],
      );
    });
  }

  // It read as a banner — a slogan and a 3D picture, nothing that looked
  // pressable — so people did not know it starts a project.
  testWidgets('the edit card is a plus and "New Video", and a tap anywhere opens the gallery',
      (tester) async {
    await pumpHome(tester);
    expect(find.text('New Video'), findsOneWidget);
    // The owner's design: three photos fanned on the right.
    for (final side in ['left', 'middle', 'right']) {
      expect(
        find.descendant(
          of: find.byKey(const Key('home_new_video')),
          // Decoded small, so the asset sits inside a ResizeImage.
          matching: find.byWidgetPredicate((w) =>
              w is Image &&
              w.image is ResizeImage &&
              (w.image as ResizeImage).imageProvider ==
                  AssetImage('assets/home/new_video_$side.webp')),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Edit New'), findsNothing);
    final card = find.byKey(const Key('home_new_video'));
    expect(find.descendant(of: card, matching: find.byIcon(LucideIcons.plus)), findsOneWidget);
    final plus = tester.getRect(find.descendant(of: card, matching: find.byIcon(LucideIcons.plus)));
    final label = tester.getRect(find.text('New Video'));
    expect(label.top, greaterThan(plus.bottom), reason: 'the words sit under the plus');

    // The fan of clips on the right is part of the button too.
    await tester.tapAt(tester.getRect(card).centerRight - const Offset(40, 0));
    await _settle(tester);
    expect(picker.picks, 1);
  });

  // The owner's call: beside the New Video card, glass did not fit. The three
  // tools are solid tiles.
  testWidgets('the three tool cards are solid, not glass', (tester) async {
    await pumpHome(tester);
    for (final title in ['Compress\nVideo', 'Compress\nPhoto', 'Privacy\nStrip']) {
      final text = find.text(title);
      expect(find.ancestor(of: text, matching: find.byType(FrostedGlass)),
          findsNothing, reason: title);
      expect(
        find.ancestor(
          of: text,
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == AppColors.surface),
        ),
        findsOneWidget,
        reason: title,
      );
      // The circle in the corner is white, not purple (the owner's call).
      final circle = find.descendant(
        of: find.ancestor(of: text, matching: find.byType(Stack)).first,
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle),
      );
      final colour =
          ((tester.widget<Container>(circle).decoration!) as BoxDecoration).color!;
      expect(colour.r, closeTo(AppColors.textPrimary.r, 0.01), reason: title);
      expect(colour.b, closeTo(AppColors.textPrimary.b, 0.01), reason: title);
    }
  });
}
