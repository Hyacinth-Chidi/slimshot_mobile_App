import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tool surfaces take their text and icon colours from `AppColors`.
///
/// CLAUDE.md: "Colours from `AppColors`, never hard-coded." An audit found the
/// rule held in the five newer sheets and had never been applied to the five
/// older drawers, which were still on `Colors.white` and `Colors.white54` —
/// 24 sites. That is not pedantry: `textPrimary` is Zinc 50 (#FAFAFA) and
/// `textSecondary` is Zinc 400, a different hue *and* weight from pure white
/// and 54% white, so the two generations of sheet read differently side by
/// side. Titles diverged too, 13px against 14px.
///
/// **What this does not forbid**, because both generations already agree and
/// the theme has no token for them: `Colors.white24` for a grab handle,
/// `white12` for an inactive slider track, `white10` for a divider, and pure
/// white for a glyph sitting *on* the purple accent, where the contrast is the
/// point.
void main() {
  /// **Scoped to the tool panels deliberately.** The timeline is a different
  /// surface with its own rules — the playhead is pure white so it reads
  /// against any footage, and a clip's label sits on a coloured clip body
  /// rather than on the panel background — so sweeping it to the text tokens
  /// would be wrong, not merely unreviewed. It is worth its own audit; this
  /// guard covers what has had one.
  final dirs = [
    Directory('lib/features/video_editor/widgets/panels'),
  ];

  Iterable<File> dartFiles() sync* {
    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync()) {
        if (entity is File && entity.path.endsWith('.dart')) yield entity;
      }
    }
  }

  test('no tool surface hard-codes a text or icon colour', () {
    // `color: Colors.white` and `color: Colors.white54` — the two that carry
    // text and icons. Low-alpha whites are chrome and stay.
    final offender = RegExp(r'color: Colors\.white(54)?[,)]');

    final strays = <String>[];
    for (final entity in dartFiles()) {
      final name = entity.uri.pathSegments.last;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!offender.hasMatch(lines[i])) continue;
        // A glyph on the purple accent is deliberately pure white.
        if (lines[i].contains('LucideIcons.check')) continue;
        if (lines[i].contains('_kCaptionStyle.copyWith')) continue;
        strays.add('$name:${i + 1}  ${lines[i].trim()}');
      }
    }

    expect(
      strays,
      isEmpty,
      reason: 'Use AppColors.textPrimary / textSecondary:\n${strays.join('\n')}',
    );
  });

  test('every sheet title is the same size', () {
    // The drawers were 13px where every sheet was 14. One size, or the
    // headers read as two different apps stacked on the same screen.
    final strays = <String>[];
    for (final entity in dartFiles()) {
      final name = entity.uri.pathSegments.last;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('fontSize: 13') &&
            lines[i].contains('FontWeight.w600')) {
          strays.add('$name:${i + 1}');
        }
      }
    }
    expect(strays, isEmpty, reason: 'Titles are 14px: ${strays.join(', ')}');
  });
}
