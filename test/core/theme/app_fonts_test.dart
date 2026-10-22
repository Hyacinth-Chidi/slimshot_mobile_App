import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_fonts.dart';
import 'package:slimshotai/core/theme/app_theme.dart';

/// The interface font is bundled, never fetched: every text style in the
/// theme names the bundled family, where `google_fonts` named generated
/// families such as `PlusJakartaSans_regular` it downloaded at runtime.
void main() {
  test('the theme reads the bundled interface font', () {
    final theme = AppTheme.darkTheme.textTheme;
    expect(theme.bodyMedium!.fontFamily, kInterfaceFontFamily);
    final styles = [
      theme.displayLarge, theme.displayMedium, theme.displaySmall,
      theme.headlineLarge, theme.headlineMedium, theme.headlineSmall,
      theme.titleLarge, theme.titleMedium, theme.titleSmall,
      theme.bodyLarge, theme.bodyMedium, theme.bodySmall,
      theme.labelLarge, theme.labelMedium, theme.labelSmall,
    ];
    for (final style in styles) {
      expect(style!.fontFamily, kInterfaceFontFamily);
    }
  });
}
