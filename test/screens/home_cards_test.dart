import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      ..writeAsBytesSync(File('assets/app_icon.png').readAsBytesSync());
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
}
