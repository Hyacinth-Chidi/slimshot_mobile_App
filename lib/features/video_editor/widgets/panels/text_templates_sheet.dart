import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/text_template_catalog.dart';
import '../text_overlay/text_template_tile.dart';
import 'editor_sheet.dart';

/// The Text submenu's Templates: a grid of complete starting looks, each tile
/// playing its template live.
///
/// **No title.** The tool that opened it is called Templates; saying so again
/// is a line of chrome describing what the user just did.
///
/// **It stops at [kEditorSheetPreviewFraction]**, like the emoji picker and
/// for the same reason: choosing a look is a choice *for a frame*, and the
/// canvas above stays in view. The grid scrolls, so it loses nothing to the
/// cap.
///
/// Tapping a tile closes the sheet and reports the template; the caller makes
/// the new text (empty, wearing the template) and opens the editor on it.
class TextTemplatesSheet extends StatefulWidget {
  const TextTemplatesSheet({
    super.key,
    required this.onTemplateSelected,
    this.templates = kTextTemplates,
  });

  /// Called with the chosen template, after the sheet has closed — so the
  /// canvas is visible when the new text lands on it.
  final ValueChanged<TextTemplate> onTemplateSelected;

  /// The catalog, unless a test supplies its own: the catalog's families are
  /// Google Fonts, which a widget test cannot load.
  final List<TextTemplate> templates;

  @override
  State<TextTemplatesSheet> createState() => _TextTemplatesSheetState();
}

class _TextTemplatesSheetState extends State<TextTemplatesSheet>
    with SingleTickerProviderStateMixin {
  /// One loop of every visible tile.
  ///
  /// Longer than the animation tab's: a template tile plays an entrance, a
  /// hold and an exit in one loop, where an animation tile plays one motion.
  static const Duration _kTileLoop = Duration(milliseconds: 2400);

  static const double _kEdge = 16;

  /// **One clock for every tile**, rather than a `Ticker` per tile.
  late final AnimationController _clock;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: _kTileLoop)..repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * kEditorSheetPreviewFraction,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    // The grab handle's white24 — the one white the theme
                    // guard allows here, shared by every sheet.
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(_kEdge, 0, _kEdge, _kEdge),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.1,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: widget.templates.length,
                  itemBuilder: (context, index) {
                    final template = widget.templates[index];
                    return TextTemplateTile(
                      template: template,
                      clock: _clock,
                      onTap: () {
                        // Close first: the text lands on the canvas, and a
                        // sheet still covering it would hide what the tap did.
                        Navigator.of(context).pop();
                        widget.onTemplateSelected(template);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
