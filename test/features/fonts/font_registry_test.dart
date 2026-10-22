import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/fonts/font_registry.dart';

void main() {
  late Directory root;
  late List<String> loaded;
  late bool refuse;

  setUp(() {
    root = Directory.systemTemp.createTempSync('font_registry_test');
    loaded = [];
    refuse = false;
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  FontRegistry registry() => FontRegistry(loader: (Uint8List bytes, String name) async {
        if (refuse) throw Exception('not a font');
        loaded.add(name);
      });

  String fontFile(String name) {
    final file = File('${root.path}/$name.ttf')..writeAsBytesSync([0, 1, 0, 0]);
    return file.path;
  }

  test('local names are always available', () {
    final fonts = registry();
    expect(fonts.isAvailable('Roboto'), isTrue);
    expect(fonts.isAvailable('Montserrat Bold'), isTrue);
    expect(fonts.isAvailable('bebas neue'), isTrue);
    expect(fonts.isAvailable('Poppins'), isTrue);
    expect(fonts.isAvailable('Playfair Display'), isFalse);
  });

  test('a registered name is available', () async {
    final fonts = registry();
    expect(await fonts.registerFile('Playfair Display', fontFile('pd')), isTrue);
    expect(fonts.isAvailable('Playfair Display'), isTrue);
    expect(loaded, ['Playfair Display']);
  });

  test('a name registers once', () async {
    final fonts = registry();
    final path = fontFile('pd');
    await Future.wait([
      fonts.registerFile('Playfair Display', path),
      fonts.registerFile('Playfair Display', path),
    ]);
    await fonts.registerFile('Playfair Display', path);
    expect(loaded, ['Playfair Display']);
  });

  test('registering notifies changes', () async {
    final fonts = registry();
    var notified = 0;
    fonts.changes.addListener(() => notified++);
    await fonts.registerFile('Playfair Display', fontFile('pd'));
    await fonts.registerFile('Playfair Display', fontFile('pd'));
    expect(notified, 1);
  });

  test('a file the engine refuses is not registered and does not throw', () async {
    final fonts = registry();
    refuse = true;
    expect(await fonts.registerFile('Playfair Display', fontFile('pd')), isFalse);
    expect(fonts.isAvailable('Playfair Display'), isFalse);
    refuse = false;
    expect(await fonts.registerFile('Playfair Display', fontFile('pd')), isTrue);
    expect(loaded, ['Playfair Display']);
  });

  test('a missing file answers false', () async {
    final fonts = registry();
    expect(await fonts.registerFile('Playfair Display', '${root.path}/gone.ttf'), isFalse);
    expect(fonts.isAvailable('Playfair Display'), isFalse);
    expect(loaded, isEmpty);
  });
}
