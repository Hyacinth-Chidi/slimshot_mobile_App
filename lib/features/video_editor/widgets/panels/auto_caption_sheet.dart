import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/captions/caption_settings.dart';
import '../../services/caption_pipeline.dart';
import 'caption_sheet_parts.dart';
import 'editor_sheet.dart';

/// Text → Auto captions: which sound, which language, how long a caption.
///
/// No title — the user tapped Auto captions to get here. Pops a
/// [CaptionRequest] on Generate, nothing on dismissal.
class AutoCaptionSheet extends StatefulWidget {
  const AutoCaptionSheet({super.key, this.initial});

  /// The project's last choices, so a second run starts where the first did.
  final CaptionSettings? initial;

  @override
  State<AutoCaptionSheet> createState() => _AutoCaptionSheetState();
}

class _AutoCaptionSheetState extends State<AutoCaptionSheet> {
  late CaptionSource _source = widget.initial?.source ?? CaptionSource.video;
  late String? _language = isCaptionLanguage(widget.initial?.language)
      ? widget.initial!.language
      : null;
  late CaptionLength _length = widget.initial?.length ?? CaptionLength.phrase;

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
                    ],
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
