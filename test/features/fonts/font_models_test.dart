import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/fonts/data/font_models.dart';

import 'support.dart';

void main() {
  test('a Regular face is named by its family', () {
    expect(fontNameFor('Playfair Display', 'Regular'), 'Playfair Display');
    expect(fontNameFor('Inter', ' regular '), 'Inter');
  });

  test('any other face adds its style', () {
    expect(fontNameFor('Lato', 'Bold'), 'Lato Bold');
    expect(fontNameFor('Lato', 'Bold Italic'), 'Lato Bold Italic');
  });

  test('a row missing id or family is skipped, a missing preview is not', () {
    final fonts = parseServerFonts([
      fontRow('pd', 'Playfair Display'),
      {'displayName': 'No id', 'familyName': 'X', 'styleName': 'Regular', 'version': 1, 'format': 'ttf'},
      {'id': 'nf', 'displayName': 'No family', 'styleName': 'Regular', 'version': 1, 'format': 'ttf'},
      fontRow('np', 'Nunito', preview: false),
      'not a row',
    ]);
    expect(fonts.map((f) => f.id), ['pd', 'np']);
    expect(fonts.first.previewUrl, 'https://cdn.test/previews/pd-v1.png');
    expect(fonts.last.previewUrl, isNull);
    expect(fonts.first.name, 'Playfair Display');
  });

  test('toJson round-trips', () {
    final font = ServerFont.tryParse(fontRow('lb', 'Lato', style: 'Bold', version: 3))!;
    final again = ServerFont.tryParse(font.toJson())!;
    expect(again.id, 'lb');
    expect(again.displayName, 'Lato Bold');
    expect(again.familyName, 'Lato');
    expect(again.styleName, 'Bold');
    expect(again.version, 3);
    expect(again.format, 'ttf');
    expect(again.previewUrl, font.previewUrl);
    expect(again.name, 'Lato Bold');
  });

  test('a ticket reads its version', () {
    final ticket = FontDownloadTicket.tryParse({
      'url': 'https://cdn.test/fonts/pd-v2.ttf',
      'filename': 'pd.ttf',
      'format': 'ttf',
      'byteSize': 301268,
      'version': 2,
    })!;
    expect(ticket.version, 2);
    expect(ticket.byteSize, 301268);
    expect(FontDownloadTicket.tryParse({'filename': 'x'}), isNull);
  });
}
