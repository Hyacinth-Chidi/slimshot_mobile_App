import 'package:flutter/material.dart';

import '../../logic/captions/caption_highlight.dart';
import '../../logic/captions/caption_preset_catalog.dart';
import '../../logic/text_look.dart';
import '../text_overlay/caption_preset_tile.dart';
import '../text_overlay/text_preview_tile.dart';
import 'caption_sheet_parts.dart';
import 'editor_sheet.dart';

/// A caption's menu → Caption style: how the whole set looks, one tap.
///
/// The styles first — a style is a whole look, highlight included, so it is
/// picked first — and the Highlight row under them, to tune it. No title: the
/// user tapped Caption style to get here.
///
/// **Every tap reaches the whole set at once**, through [onPresetChosen] and
/// [onHighlightChanged], one undo step each: a set where one caption looks
/// different reads as broken. A single caption is still the text editor's,
/// with "Apply to all captions" turned off.
class CaptionStyleSheet extends StatefulWidget {
  const CaptionStyleSheet({
    super.key,
    required this.look,
    required this.highlight,
    required this.onPresetChosen,
    required this.onHighlightChanged,
    this.presets = kCaptionPresets,
  });

  /// The look and highlight of the caption the sheet was opened from.
  final TextLook look;
  final CaptionHighlight highlight;

  /// Restyles the set: a style's look and highlight together.
  final ValueChanged<CaptionPreset> onPresetChosen;

  /// Changes the set's highlight, its look kept.
  final ValueChanged<CaptionHighlight> onHighlightChanged;

  /// The styles offered — the catalog, unless a test supplies its own: the
  /// catalog's downloaded faces cannot load in a test.
  final List<CaptionPreset> presets;

  @override
  State<CaptionStyleSheet> createState() => _CaptionStyleSheetState();
}

class _CaptionStyleSheetState extends State<CaptionStyleSheet>
    with SingleTickerProviderStateMixin {
  /// One loop of every style tile: long enough for a sample's words to light
  /// one after another.
  static const Duration _kTileLoop = Duration(milliseconds: 1800);

  /// One clock for every tile, held while the sheet scrolls.
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: _kTileLoop)..repeat();

  late TextLook _look = widget.look;
  late CaptionHighlight _highlight = widget.highlight;

  /// A style is a look and a highlight; the Highlight row follows it, so the
  /// highlight can be tuned from there.
  void _choosePreset(CaptionPreset preset) {
    setState(() {
      _look = preset.look;
      _highlight = preset.highlight;
    });
    widget.onPresetChosen(preset);
  }

  void _setHighlight(CaptionHighlight highlight) {
    if (highlight == _highlight) return;
    setState(() => _highlight = highlight);
    widget.onHighlightChanged(highlight);
  }

  /// The style the set is wearing, found rather than remembered: a hand edit
  /// makes none current, which is the truth.
  String? get _currentPresetId {
    for (final p in widget.presets) {
      if (p.look.sameLookAs(_look) && p.highlight == _highlight) return p.id;
    }
    return null;
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        MediaQuery.sizeOf(context).height * kEditorSheetPreviewFraction;
    return CaptionSheetFrame(
      maxHeight: maxHeight,
      children: [
        Flexible(
          // The style tiles are still while the sheet scrolls — see
          // [holdPreviewClockWhileScrolling].
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) =>
                mounted && holdPreviewClockWhileScrolling(notification, _clock),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CaptionPresetGrid(
                    presets: widget.presets,
                    selectedId: _currentPresetId,
                    clock: _clock,
                    onSelected: _choosePreset,
                  ),
                  const SheetSectionLabel('Highlight'),
                  CaptionPillRow<CaptionHighlightStyle>(
                    values: CaptionHighlightStyle.values,
                    selected: _highlight.style,
                    label: captionHighlightLabel,
                    keyFor: (s) => Key('caption_highlight_${s.name}'),
                    onSelected: (s) =>
                        _setHighlight(_highlight.copyWith(style: s)),
                  ),
                  if (captionHighlightUsesColor(_highlight.style)) ...[
                    const SizedBox(height: 12),
                    CaptionColorRow(
                      colors: kCaptionHighlightColors,
                      selected: _highlight.color,
                      keyFor: (i) => Key('caption_highlight_color_$i'),
                      onSelected: (c) =>
                          _setHighlight(_highlight.copyWith(color: c)),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
