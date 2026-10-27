import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app icon is drawn from `assets/logo.png` (the owner's call: that
/// drawing, not the SVG's nor the old icon's). The old 1024 picture was
/// sharp, but it was the only icon there was, so Android 8+ squeezed the
/// whole square, corners and all, into its own shape and the logo arrived
/// small and soft. The logo is drawn at most 481px tall from its 487, so it
/// is only ever made smaller, never stretched.
///
/// `UPDATE_APP_ICON=1 flutter test test/app_icon_test.dart` redraws the four
/// sources in `assets/icon/` (kept out of the APK — only top-level `assets/`
/// files are bundled); then `dart run flutter_launcher_icons` makes every
/// size from them. Without the variable this checks what is committed.
void main() {
  const size = 1024;
  const dir = 'assets/icon';

  // An adaptive icon is a 108dp canvas; launchers show the middle 72dp and
  // every mask they cut keeps a circle of 66dp.
  const canvasDp = 108.0;
  const visibleDp = 72.0;
  const safeRadiusDp = 33.0;

  if (Platform.environment['UPDATE_APP_ICON'] == '1') {
    testWidgets('redraw the icon sources from the logo', (tester) async {
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          File('assets/logo.png').readAsBytesSync(),
        );
        final logo = (await codec.getNextFrame()).image;
        final logoSize = Size(logo.width * 1.0, logo.height * 1.0);
        await Directory(dir).create(recursive: true);

        // The look the icon has always had: a dark grey fall from top to
        // bottom, the white logo with its purple bars.
        Paint background() => Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            const Offset(0, size * 1.0),
            const [Color(0xFF3D3D3E), Color(0xFF101011)],
          );

        // The logo [height] tall, centred across and a touch above the
        // middle — where it sat in the original artwork.
        void drawLogo(Canvas canvas, double height, double centreY) {
          final width = height * logoSize.width / logoSize.height;
          canvas.drawImageRect(
            logo,
            Offset.zero & logoSize,
            Rect.fromLTWH(
              (size - width) / 2,
              centreY - height / 2,
              width,
              height,
            ),
            Paint()..filterQuality = FilterQuality.high,
          );
        }

        Future<void> write(String name, void Function(Canvas) paint) async {
          final recorder = ui.PictureRecorder();
          paint(Canvas(recorder));
          final image =
              await recorder.endRecording().toImage(size, size);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/$name').writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        }

        const full = Rect.fromLTWH(0, 0, size * 1.0, size * 1.0);
        // The whole icon: the logo 47% of its height.
        const fullLogo = size * 0.47;
        const fullCentre = size * 0.48;

        // Android 7 and older show this as it is, so it carries its own
        // rounded corners.
        await write('app_icon.png', (c) {
          c.drawRRect(
            RRect.fromRectAndRadius(full, const Radius.circular(92)),
            background(),
          );
          drawLogo(c, fullLogo, fullCentre);
        });
        // iOS rounds the corners itself and refuses transparency.
        await write('app_icon_ios.png', (c) {
          c.drawRect(full, background());
          drawLogo(c, fullLogo, fullCentre);
        });
        // Android 8+: two layers the launcher masks to its own shape. The
        // logo keeps its share of what the launcher shows (the middle
        // 72/108), so it is the same size on the phone as in the artwork.
        await write('background.png', (c) => c.drawRect(full, background()));
        await write('foreground.png', (c) {
          const visible = visibleDp / canvasDp;
          drawLogo(
            c,
            fullLogo * visible,
            size / 2 + (fullCentre - size / 2) * visible,
          );
        });
        logo.dispose();
      });
    });
  }

  Future<(int, int, ByteData)> pixels(WidgetTester tester, String path) async {
    return (await tester.runAsync(() async {
      final codec =
          await ui.instantiateImageCodec(File(path).readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final result = (image.width, image.height, data!);
      image.dispose();
      return result;
    }))!;
  }

  int alphaAt(ByteData data, int width, int x, int y) =>
      data.getUint8((y * width + x) * 4 + 3);

  for (final name in [
    'app_icon.png',
    'app_icon_ios.png',
    'background.png',
    'foreground.png',
  ]) {
    testWidgets('$name is a 1024 square', (tester) async {
      final (w, h, _) = await pixels(tester, '$dir/$name');
      expect((w, h), (size, size));
    });
  }

  // Every launcher shape — circle, squircle, rounded square, teardrop —
  // keeps this circle. A logo past it is cut on some phone.
  testWidgets('the logo stays inside the circle every launcher shape keeps',
      (tester) async {
    final (w, h, data) = await pixels(tester, '$dir/foreground.png');
    const safe = safeRadiusDp / canvasDp * size;
    var ink = 0;
    var outside = 0;
    for (var y = 0; y < h; y += 2) {
      for (var x = 0; x < w; x += 2) {
        if (alphaAt(data, w, x, y) == 0) continue;
        ink++;
        if (math.sqrt(math.pow(x - w / 2, 2) + math.pow(y - h / 2, 2)) > safe) {
          outside++;
        }
      }
    }
    expect(ink, greaterThan(10000), reason: 'the logo is drawn');
    expect(outside, 0);
  });

  testWidgets('the background layer has no holes', (tester) async {
    final (w, h, data) = await pixels(tester, '$dir/background.png');
    for (var y = 0; y < h; y += 16) {
      for (var x = 0; x < w; x += 16) {
        expect(alphaAt(data, w, x, y), 255, reason: '($x, $y)');
      }
    }
  });

  // iOS fills a transparent corner with black.
  testWidgets('the iOS icon is opaque to its corners', (tester) async {
    final (w, _, data) = await pixels(tester, '$dir/app_icon_ios.png');
    for (final (x, y) in [(0, 0), (w - 1, 0), (0, w - 1), (w - 1, w - 1)]) {
      expect(alphaAt(data, w, x, y), 255);
    }
  });

  testWidgets('the older Android icon carries its own rounded corners',
      (tester) async {
    final (w, _, data) = await pixels(tester, '$dir/app_icon.png');
    expect(alphaAt(data, w, 0, 0), 0);
    expect(alphaAt(data, w, w ~/ 2, 4), 255);
  });

  // The sources only matter once the generator has made the phone's sizes
  // from them; a source redrawn and not generated would ship the old icon.
  test('Android 8+ gets the adaptive icon made from these layers', () {
    const res = 'android/app/src/main/res';
    final xml =
        File('$res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
    expect(xml, contains('@drawable/ic_launcher_foreground'));
    expect(xml, contains('@drawable/ic_launcher_background'));
    expect(File('$res/drawable-xxxhdpi/ic_launcher_foreground.png').existsSync(),
        isTrue);
    expect(File('$res/drawable-xxxhdpi/ic_launcher_background.png').existsSync(),
        isTrue);
  });
}
