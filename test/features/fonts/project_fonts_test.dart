import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/fonts/font_names.dart';
import 'package:slimshotai/features/fonts/project_fonts.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_preset_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/text_template_catalog.dart';

void main() {
  test('only fonts neither available nor asked are fetched', () {
    final fetch = fontsToFetch(
      ['Roboto', 'Oswald', 'Lato Bold', 'Righteous', 'Lato Bold'],
      {'Oswald'},
      (name) => isLocalFontName(name) || name == 'Righteous',
    );
    expect(fetch, {'Lato Bold'});
  });

  test('template and caption fonts leave out the local ones', () {
    final templates = templateFontNames(kTextTemplates);
    expect(templates, containsAll(['Righteous', 'Playfair Display']));
    expect(templates, isNot(contains('Bebas Neue')));
    expect(templates.any(isLocalFontName), isFalse);

    final captions = captionPresetFontNames(kCaptionPresets);
    expect(captions, contains('Righteous'));
    expect(captions, isNot(contains('Montserrat Bold')));
    expect(captions.any(isLocalFontName), isFalse);
  });

  test('the message names no font', () {
    expect(kFontUnavailableMessage, "A font in this project couldn't be downloaded");
  });
}
