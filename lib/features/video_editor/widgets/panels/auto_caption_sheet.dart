import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/captions/caption_highlight.dart';
import '../../logic/captions/caption_preset_catalog.dart';
import '../../logic/captions/caption_settings.dart';
import '../../logic/text_look.dart';
import '../../services/caption_pipeline.dart';
import '../text_overlay/caption_preset_tile.dart';
import '../text_overlay/text_preview_tile.dart';
import 'caption_sheet_parts.dart';
import 'editor_sheet.dart';

/// Text → Auto captions: which sound, which language, how long a caption,
/// how the word being spoken lights up, and the whole style.
///
/// No title — the user tapped Auto captions to get here. Pops a
/// [CaptionRequest] on Generate, nothing on dismissal.
///
/// **A look needs no new transcription**, so with a set already on the
/// timeline each highlight or style chosen reaches it at once, through
/// [onHighlightChanged] and [onPresetChosen] — kept, like any sheet's live
/// edit, when the sheet is dismissed.
class AutoCaptionSheet extends StatefulWidget {
  const AutoCaptionSheet({
    super.key,
    this.initial,
    this.initialLook,
    this.onHighlightChanged,
    this.onPresetChosen,
    this.presets = kCaptionPresets,
  });

  /// The project's last choices, so a second run starts where the first did.
  final CaptionSettings? initial;

  /// The set's look — its first caption's — or null with no set. A new set is
  /// built in it, so a look tuned by hand survives a regeneration.
  final TextLook? initialLook;

  /// Applies a highlight to the set on the timeline; null when there is none.
  final ValueChanged<CaptionHighlight>? onHighlightChanged;

  /// Applies a style to the set on the timeline; null when there is none.
  final ValueChanged<CaptionPreset>? onPresetChosen;

  /// The styles offered — the catalog, unless a test supplies its own: the
  /// catalog's downloaded faces cannot load in a test.
  final List<CaptionPreset> presets;

  @override
  State<AutoCaptionSheet> createState() => _AutoCaptionSheetState();
}

class _AutoCaptionSheetState extends State<AutoCaptionSheet>
    with SingleTickerProviderStateMixin {
  /// One loop of every style tile: long enough for a sample's words to light
  /// one after another.
  static const Duration _kTileLoop = Duration(milliseconds: 1800);

  /// One clock for every tile, held while the sheet scrolls.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _kTileLoop,
  )..repeat();

  /// A new set starts on the first style — the default look.
  late TextLook _look = widget.initialLook ??
      (widget.presets.isEmpty ? kCaptionDefaultLook : widget.presets.first.look);

  late CaptionSource _source = widget.initial?.source ?? CaptionSource.video;
  late String? _language = isCaptionLanguage(widget.initial?.language)
      ? widget.initial!.language
      : null;
  late CaptionLength _length = widget.initial?.length ?? CaptionLength.phrase;
  late CaptionHighlight _highlight =
      widget.initial?.highlight ?? CaptionHighlight.none;

  void _setHighlight(CaptionHighlight highlight) {
    if (highlight == _highlight) return;
    setState(() => _highlight = highlight);
    widget.onHighlightChanged?.call(highlight);
  }

  /// A style is a look and a highlight; the Highlight row follows it, so the
  /// highlight can be tuned from there.
  void _choosePreset(CaptionPreset preset) {
    setState(() {
      _look = preset.look;
      _highlight = preset.highlight;
    });
    widget.onPresetChosen?.call(preset);
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

  static String _sourceLabel(CaptionSource s) => switch (s) {
    CaptionSource.video => 'Video sound',
    CaptionSource.tracks => 'Audio tracks',
    CaptionSource.all => 'All',
  };

  static String _lengthLabel(CaptionLength l) => switch (l) {
    CaptionLength.word => 'Word',
    CaptionLength.phrase => 'Phrase',
    CaptionLength.line => 'Line',
  };

  static String _languageLabel(String? code) => code == null
      ? 'Auto detect'
      : kCaptionLanguages.firstWhere((l) => l.code == code).name;

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: Text(
      title,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        MediaQuery.sizeOf(context).height * kEditorSheetPreviewFraction;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetGrabHandle(),
              Flexible(
                // The style tiles are still while the sheet scrolls — see
                // [holdPreviewClockWhileScrolling].
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) =>
                      mounted &&
                      holdPreviewClockWhileScrolling(notification, _clock),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _section('Source'),
                        CaptionPillRow<CaptionSource>(
                          values: CaptionSource.values,
                          selected: _source,
                          label: _sourceLabel,
                          keyFor: (s) => Key('caption_source_${s.name}'),
                          onSelected: (s) => setState(() => _source = s),
                        ),
                        _section('Language'),
                        CaptionPillRow<String?>(
                          values: [
                            null,
                            for (final l in kCaptionLanguages) l.code,
                          ],
                          selected: _language,
                          label: _languageLabel,
                          keyFor: (c) => Key('caption_language_${c ?? 'auto'}'),
                          onSelected: (c) => setState(() => _language = c),
                        ),
                        _section('Length'),
                        CaptionPillRow<CaptionLength>(
                          values: CaptionLength.values,
                          selected: _length,
                          label: _lengthLabel,
                          keyFor: (l) => Key('caption_length_${l.name}'),
                          onSelected: (l) => setState(() => _length = l),
                        ),
                        _section('Highlight'),
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
                        _section('Style'),
                        CaptionPresetGrid(
                          presets: widget.presets,
                          selectedId: _currentPresetId,
                          clock: _clock,
                          onSelected: _choosePreset,
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: SheetActionButton(
                    key: const Key('caption_generate'),
                    label: 'Generate',
                    filled: true,
                    onTap: () => Navigator.of(context).pop(
                      CaptionRequest(
                        source: _source,
                        language: _language,
                        length: _length,
                        highlight: _highlight,
                        look: _look,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
