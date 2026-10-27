import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/widgets/launch_splash.dart';

/// The splash's pictures, all made from `assets/logo.png`.
///
/// `UPDATE_SPLASH_ART=1 flutter test test/launch_splash_art_test.dart`
/// redraws them, then `dart run flutter_native_splash:create` writes the
/// native splash from the two in `assets/native_splash/` (out of the APK;
/// only the four layers in `assets/splash/` are bundled, for the app's own
/// frames). Without the variable this checks what is committed.
void main() {
  const logoPath = 'assets/logo.png';
  // Straight (not premultiplied) RGBA, so a half-transparent edge keeps the
  // colour it is an edge of.
  Future<(int, int, Uint8List)> pixels(WidgetTester tester, String path) async {
    return (await tester.runAsync(() async {
      final codec =
          await ui.instantiateImageCodec(File(path).readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      final result = (image.width, image.height, data!.buffer.asUint8List());
      image.dispose();
      return result;
    }))!;
  }

  // The logo is two colours: white, and the purple of its three bars.
  bool isBar(Uint8List p, int i) => p[i + 3] > 0 && p[i + 1] < 163;

  if (Platform.environment['UPDATE_SPLASH_ART'] == '1') {
    testWidgets('redraw the splash pictures from logo.png', (tester) async {
      final (w, h, logo) = await pixels(tester, logoPath);

      // The bars are three separate shapes; find each by flood fill, since
      // they are slanted and their rows overlap.
      final label = Int32List(w * h)..fillRange(0, w * h, -1);
      final bars = <List<int>>[];
      for (var start = 0; start < w * h; start++) {
        if (label[start] != -1 || !isBar(logo, start * 4)) continue;
        final shape = <int>[];
        final queue = Queue<int>()..add(start);
        label[start] = bars.length;
        while (queue.isNotEmpty) {
          final at = queue.removeFirst();
          shape.add(at);
          final x = at % w, y = at ~/ w;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = x + dx, ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
              final n = ny * w + nx;
              if (label[n] == -1 && isBar(logo, n * 4)) {
                label[n] = bars.length;
                queue.add(n);
              }
            }
          }
        }
        bars.add(shape);
      }
      expect(bars, hasLength(3));
      // Top first.
      bars.sort((a, b) => a.reduce(math.min).compareTo(b.reduce(math.min)));

      Uint8List layer(bool Function(int pixel) keep) {
        final out = Uint8List(w * h * 4);
        for (var p = 0; p < w * h; p++) {
          if (!keep(p)) continue;
          out.setRange(p * 4, p * 4 + 4, logo, p * 4);
        }
        return out;
      }

      await tester.runAsync(() async {
        await Directory('assets/splash').create(recursive: true);
        await Directory('assets/native_splash').create(recursive: true);
        await _writePng('assets/splash/body.png', w, h,
            layer((p) => logo[p * 4 + 3] > 0 && !isBar(logo, p * 4)));
        for (var i = 0; i < 3; i++) {
          final mine = bars[i].toSet();
          await _writePng('assets/splash/bar_$i.png', w, h,
              layer(mine.contains));
        }

        // The native splash: the whole logo, dim. The app lights it up.
        final dim = Uint8List.fromList(logo);
        for (var i = 3; i < dim.length; i += 4) {
          dim[i] = (dim[i] * kLaunchLogoRestingOpacity).round();
        }
        await _writePng('assets/native_splash/logo.png', w, h, dim);

        // Android 12+: a 288dp canvas at 4x, the logo 1:1 in its middle,
        // the same size on screen as everywhere else.
        const canvas = 1152;
        final icon = Uint8List(canvas * canvas * 4);
        final ox = (canvas - w) ~/ 2, oy = (canvas - h) ~/ 2;
        for (var y = 0; y < h; y++) {
          icon.setRange(((oy + y) * canvas + ox) * 4,
              ((oy + y) * canvas + ox + w) * 4, dim, y * w * 4);
        }
        await _writePng(
            'assets/native_splash/logo_android12.png', canvas, canvas, icon);
      });
    });
  }

  // The hand-over: the native splash draws its picture at 4x, so the app's
  // first frame must draw the logo at a quarter of its pixels.
  test('the app draws the logo at the size the native splash does', () {
    final png = File(logoPath).readAsBytesSync();
    final header = ByteData.sublistView(png, 16, 24);
    expect(
      kLaunchLogoSize,
      Size(header.getUint32(0) / 4, header.getUint32(4) / 4),
    );
  });

  testWidgets('the body and the three bars, laid together, are logo.png',
      (tester) async {
    final (w, h, logo) = await pixels(tester, logoPath);
    final layers = <Uint8List>[];
    for (final path in kLaunchSplashLayers) {
      final (lw, lh, data) = await pixels(tester, path);
      expect((lw, lh), (w, h), reason: path);
      layers.add(data);
    }
    var mismatched = 0;
    for (var i = 0; i < logo.length; i += 4) {
      final holders = [
        for (final layer in layers)
          if (layer[i + 3] > 0) layer,
      ];
      expect(holders.length, lessThanOrEqualTo(1),
          reason: 'one pixel in two layers would be drawn twice');
      if (logo[i + 3] == 0) {
        expect(holders, isEmpty);
        continue;
      }
      expect(holders, hasLength(1), reason: 'a pixel of the logo was lost');
      final mine = holders.single;
      if ((mine[i + 3] - logo[i + 3]).abs() > 1) mismatched++;
      // Colour only where there is enough of it to see.
      if (logo[i + 3] >= 64) {
        for (var c = 0; c < 3; c++) {
          if ((mine[i + c] - logo[i + c]).abs() > 3) mismatched++;
        }
      }
    }
    expect(mismatched, 0);
  });

  testWidgets('the bars are purple and come top first; the body is white',
      (tester) async {
    double topOf(Uint8List p, int w) {
      for (var i = 0; i < p.length; i += 4) {
        if (p[i + 3] > 0) return (i ~/ 4 ~/ w).toDouble();
      }
      return double.infinity;
    }

    final (w, _, body) = await pixels(tester, kLaunchSplashLayers.first);
    for (var i = 0; i < body.length; i += 4) {
      if (body[i + 3] > 0) expect(isBar(body, i), isFalse);
    }
    var previousTop = -1.0;
    for (final path in kLaunchSplashLayers.skip(1)) {
      final (_, _, bar) = await pixels(tester, path);
      var ink = 0;
      for (var i = 0; i < bar.length; i += 4) {
        if (bar[i + 3] == 0) continue;
        ink++;
        expect(isBar(bar, i), isTrue, reason: path);
      }
      expect(ink, greaterThan(1000), reason: path);
      final top = topOf(bar, w);
      expect(top, greaterThan(previousTop), reason: path);
      previousTop = top;
    }
  });

  testWidgets('the native splash shows logo.png at the resting opacity',
      (tester) async {
    final (w, h, logo) = await pixels(tester, logoPath);
    final (nw, nh, dim) =
        await pixels(tester, 'assets/native_splash/logo.png');
    expect((nw, nh), (w, h));
    for (var i = 0; i < logo.length; i += 4) {
      expect(dim[i + 3],
          closeTo(logo[i + 3] * kLaunchLogoRestingOpacity, 1.01));
    }
  });

  // Android 12+ shows a 288dp canvas and keeps only a 192dp circle of it.
  testWidgets("Android 12's splash icon keeps the logo inside the circle the "
      'system shows', (tester) async {
    final (w, h, icon) =
        await pixels(tester, 'assets/native_splash/logo_android12.png');
    expect((w, h), (1152, 1152));
    const radius = 1152 * 192 / 288 / 2;
    var ink = 0;
    for (var y = 0; y < h; y += 2) {
      for (var x = 0; x < w; x += 2) {
        if (icon[(y * w + x) * 4 + 3] == 0) continue;
        ink++;
        final d = math.sqrt(math.pow(x - w / 2, 2) + math.pow(y - h / 2, 2));
        expect(d, lessThanOrEqualTo(radius), reason: '($x, $y)');
      }
    }
    expect(ink, greaterThan(10000));
  });

  // The pictures only matter once the generator has written them into the
  // platform's launch screen.
  group('the native splash as Android draws it', () {
    const res = 'android/app/src/main/res';

    for (final v31 in ['values-v31', 'values-night-v31']) {
      test('$v31: the dim logo on the app\'s own black, no circle behind it',
          () {
        final styles = File('$res/$v31/styles.xml').readAsStringSync();
        expect(styles,
            contains('<item name="android:windowSplashScreenBackground">'
                '#09090B</item>'));
        expect(styles,
            contains('<item name="android:windowSplashScreenAnimatedIcon">'
                '@drawable/android12splash</item>'));
        expect(styles, isNot(contains('windowSplashScreenIconBackgroundColor')));
      });
    }

    test('Android 11 and older: the dim logo in the middle of the screen', () {
      for (final dir in ['drawable', 'drawable-v21']) {
        final xml = File('$res/$dir/launch_background.xml').readAsStringSync();
        expect(xml, contains('android:gravity="center"'));
        expect(xml, contains('@drawable/splash'));
        expect(xml, contains('@drawable/background'));
      }
    });

    testWidgets('the background is the app\'s own black, #09090B',
        (tester) async {
      final (_, _, bg) = await pixels(tester, '$res/drawable/background.png');
      expect(bg.sublist(0, 4), [0x09, 0x09, 0x0B, 0xFF]);
    });

    testWidgets('the splash pictures are the native ones, 1:1 at 4x',
        (tester) async {
      final (w, h, _) = await pixels(tester, '$res/drawable-xxxhdpi/splash.png');
      final (nw, nh, _) =
          await pixels(tester, 'assets/native_splash/logo.png');
      expect((w, h), (nw, nh));
      final (aw, ah, _) =
          await pixels(tester, '$res/drawable-xxxhdpi/android12splash.png');
      expect((aw, ah), (1152, 1152));
    });
  });
}

/// Writes straight-alpha RGBA as a PNG. `decodeImageFromPixels` takes
/// premultiplied pixels; the round trip is what the "laid together" test
/// checks.
Future<void> _writePng(String path, int w, int h, Uint8List straight) async {
  final premultiplied = Uint8List(straight.length);
  for (var i = 0; i < straight.length; i += 4) {
    final a = straight[i + 3];
    for (var c = 0; c < 3; c++) {
      premultiplied[i + c] = (straight[i + c] * a / 255).round();
    }
    premultiplied[i + 3] = a;
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      premultiplied, w, h, ui.PixelFormat.rgba8888, done.complete);
  final image = await done.future;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
  image.dispose();
}
