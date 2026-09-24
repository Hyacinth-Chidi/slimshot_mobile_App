import 'package:flutter/material.dart';

import '../../logic/text_template_catalog.dart';
import 'text_preview_tile.dart';
import 'text_template_tile.dart';

/// A grid of live template tiles — the one both ways into templates show.
///
/// The Text submenu's Templates sheet shows it with no words, so each tile
/// plays its template's own sample: choose, then type. The text editor's
/// Templates tab shows it with the text's own [text] and the template it is
/// wearing as [selectedId]: type, then choose, and choose again.
///
/// **One clock for every tile**, owned here rather than a `Ticker` per tile.
/// It loops longer than the animation tab's because a template tile plays an
/// entrance, a hold and an exit in one loop, where an animation tile plays one
/// motion.
class TextTemplateGrid extends StatefulWidget {
  const TextTemplateGrid({
    super.key,
    required this.templates,
    required this.onSelected,
    this.text,
    this.selectedId,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final List<TextTemplate> templates;

  /// Fired once per tap with the template tapped.
  final ValueChanged<TextTemplate> onSelected;

  /// The words every tile shows; empty or null shows each template's sample.
  final String? text;

  /// The template the text is wearing, highlighted — or null.
  final String? selectedId;

  final EdgeInsets padding;

  @override
  State<TextTemplateGrid> createState() => _TextTemplateGridState();
}

class _TextTemplateGridState extends State<TextTemplateGrid>
    with SingleTickerProviderStateMixin {
  static const Duration _kTileLoop = Duration(milliseconds: 2400);

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
    return GridView.builder(
      padding: widget.padding,
      gridDelegate: kTextPreviewGrid,
      itemCount: widget.templates.length,
      itemBuilder: (context, index) {
        final template = widget.templates[index];
        return TextTemplateTile(
          template: template,
          text: widget.text,
          isSelected: template.id == widget.selectedId,
          clock: _clock,
          onTap: () => widget.onSelected(template),
        );
      },
    );
  }
}
