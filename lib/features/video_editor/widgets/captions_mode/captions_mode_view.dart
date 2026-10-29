import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/lucide_icons.dart';
import '../../../account/logic/account_copy.dart';
import '../../../account/models/account_models.dart';
import '../../../compression/widgets/compress_panels.dart';
import '../../../compression/widgets/compress_scaffold.dart';
import '../../logic/captions/caption_highlight.dart';
import '../../logic/captions/caption_preset_catalog.dart';
import '../../logic/captions/caption_settings.dart';
import '../../logic/captions/captions_mode.dart';
import '../../logic/text_look.dart';
import '../../services/caption_pipeline.dart';
import '../../services/caption_run.dart';
import '../panels/caption_sheet_parts.dart';
import '../text_overlay/caption_preset_tile.dart';
import '../text_overlay/text_preview_tile.dart';

/// The share of the screen's height the video card takes; the screen
/// scrolls where what is under it does not fit.
const double kCaptionsCardHeightFraction = 0.45;

/// One loop of every style tile — the Caption style sheet's.
const Duration _kTileLoop = Duration(milliseconds: 1800);

const double _kTileWidth = 96;

/// The captions screen: Auto captions from Home, the editor in its captions
/// mode (mockup A, "Card"). A picture of its [step] with callbacks — the
/// editor owns the project, the preview and the run — so it is tested
/// without a device.
///
/// The video sits in a card in the project's frame on plain dark — a
/// caption's colour is judged against the footage, so no Home light here.
/// **Ready** asks Language and Length; **Generating** draws the run on the
/// card — its progress, its stage, a failure's line with Try again, or a
/// shortfall with the ways to earn, each in place; **Done** offers Edit words,
/// the styles, the highlight's colours, Export, and ✎ to the full editor.
/// The phone's Back is the ‹ button.
class CaptionsModeView extends StatefulWidget {
  const CaptionsModeView({
    super.key,
    required this.step,
    required this.preview,
    required this.aspectRatio,
    required this.onBack,
    required this.language,
    required this.length,
    required this.onLanguage,
    required this.onLength,
    required this.onGenerate,
    this.notice,
    this.run,
    required this.onCancel,
    this.earnCredits,
    required this.style,
    required this.onPreset,
    required this.onColor,
    required this.onEditWords,
    required this.onExport,
    required this.onOpenEditor,
    this.presets = kCaptionPresets,
  });

  final CaptionsStep step;

  /// The editor's canvas, drawn in the card.
  final Widget preview;

  /// The project's frame, width over height.
  final double aspectRatio;

  /// ‹ and the phone's Back.
  final VoidCallback onBack;

  /// ISO 639-1, or null for Auto detect.
  final String? language;
  final CaptionLength length;
  final ValueChanged<String?> onLanguage;
  final ValueChanged<CaptionLength> onLength;

  /// Null while it must not be tapped: a run being started, or no video yet.
  final VoidCallback? onGenerate;

  /// A line under the card on Ready — why a run came back.
  final String? notice;

  /// Generating's run.
  final CaptionRun? run;

  /// Stops the run.
  final VoidCallback onCancel;

  /// The ways to earn a shortfall's difference, as the editor's progress
  /// sheet takes them; it reports the server's new balance through
  /// `onEarned`.
  final Widget Function(
    CreditQuote quote,
    void Function(int balance) onEarned,
  )? earnCredits;

  /// The look and highlight the set wears.
  final ({TextLook look, CaptionHighlight highlight}) style;
  final ValueChanged<CaptionPreset> onPreset;
  final ValueChanged<Color> onColor;
  final VoidCallback onEditWords;

  /// Null while an export is opening.
  final VoidCallback? onExport;
  final VoidCallback onOpenEditor;

  /// Taken as a parameter because a test cannot load the downloaded faces.
  final List<CaptionPreset> presets;

  @override
  State<CaptionsModeView> createState() => _CaptionsModeViewState();
}

class _CaptionsModeViewState extends State<CaptionsModeView>
    with SingleTickerProviderStateMixin {
  /// One clock for every style tile, running only on Done.
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: _kTileLoop);

  @override
  void initState() {
    super.initState();
    widget.run?.addListener(_runChanged);
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant CaptionsModeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run != widget.run) {
      oldWidget.run?.removeListener(_runChanged);
      widget.run?.addListener(_runChanged);
    }
    _syncClock();
  }

  @override
  void dispose() {
    widget.run?.removeListener(_runChanged);
    _clock.dispose();
    super.dispose();
  }

  void _runChanged() {
    if (mounted) setState(() {});
  }

  /// The tiles play only where they are shown.
  void _syncClock() {
    if (widget.step == CaptionsStep.done) {
      if (!_clock.isAnimating) _clock.repeat();
    } else if (_clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              CompressTopBar(
                title: 'Auto captions',
                titleKey: const Key('captions_title'),
                backKey: const Key('captions_back'),
                onBack: widget.onBack,
                trailing: widget.step == CaptionsStep.done
                    ? CompressGlassIconAction(
                        key: const Key('captions_open_editor'),
                        icon: LucideIcons.pencil,
                        label: 'Open in editor',
                        onPressed: widget.onOpenEditor,
                      )
                    : null,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _card(),
                      ...switch (widget.step) {
                        CaptionsStep.ready => _ready(),
                        CaptionsStep.generating => _generating(),
                        CaptionsStep.done => _done(),
                      },
                    ],
                  ),
                ),
              ),
              CompressBottomBar(child: _action()),
            ],
          ),
        ),
      ),
    );
  }

  /// The video in the project's frame; while the words are made, dimmed
  /// under the run's ring.
  Widget _card() {
    final run = widget.run;
    final working = widget.step == CaptionsStep.generating &&
        run?.error == null &&
        run?.shortfall == null;
    final progress = run?.progress;
    return LayoutBuilder(
      builder: (context, constraints) {
        var height =
            MediaQuery.sizeOf(context).height * kCaptionsCardHeightFraction;
        var width = height * widget.aspectRatio;
        final room = constraints.maxWidth - 32;
        if (width > room) {
          width = room;
          height = width / widget.aspectRatio;
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Center(
            child: SizedBox(
              key: const Key('captions_card'),
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.preview,
                    if (widget.step == CaptionsStep.generating)
                      ColoredBox(
                        color: AppColors.background.withValues(alpha: 0.55),
                      ),
                    if (working)
                      Center(
                        child: CompressProgressRing(
                          progress == null ? null : progress * 100,
                          null,
                          key: const Key('captions_ring'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _ready() => [
        if (widget.notice case final notice?)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Text(
              notice,
              key: const Key('captions_notice'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        const SheetSectionLabel('Language'),
        CaptionLanguagePills(
          selected: widget.language,
          onSelected: widget.onLanguage,
        ),
        const SheetSectionLabel('Length'),
        CaptionLengthPills(
          selected: widget.length,
          onSelected: widget.onLength,
        ),
      ];

  List<Widget> _generating() {
    final run = widget.run;
    if (run?.error case final error?) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text(
            error,
            key: const Key('caption_error'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
        ),
      ];
    }
    if (run?.shortfall case final quote?) {
      final earn = widget.earnCredits;
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text(
            shortfallLine(quote.credits, quote.balance),
            key: const Key('caption_price'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (earn != null && run != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: earn(quote, run.earned),
          ),
      ];
    }
    return [
      const SizedBox(height: 16),
      const Text(
        'Writing captions…',
        key: Key('captions_writing'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        captionStageLabel(run?.stage ?? CaptionStage.preparing),
        key: const Key('caption_progress_stage'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    ];
  }

  List<Widget> _done() {
    final style = widget.style;
    return [
      const SizedBox(height: 12),
      Center(child: _EditWordsChip(onTap: widget.onEditWords)),
      const SheetSectionLabel('Style'),
      SizedBox(
        height: _kTileWidth / kTextPreviewGrid.childAspectRatio,
        // The tiles are still while the row scrolls — see
        // [holdPreviewClockWhileScrolling].
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) =>
              mounted && holdPreviewClockWhileScrolling(notification, _clock),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final preset = widget.presets[i];
              return SizedBox(
                width: _kTileWidth,
                child: CaptionPresetTile(
                  key: Key('captions_style_${preset.id}'),
                  preset: preset,
                  clock: _clock,
                  // Found, not remembered: a hand edit marks none.
                  isSelected: preset.look.sameLookAs(style.look) &&
                      preset.highlight == style.highlight,
                  onTap: () => widget.onPreset(preset),
                ),
              );
            },
          ),
        ),
      ),
      const SheetSectionLabel('Colour'),
      // Dimmed and deaf where the highlight lights in no colour, never
      // hidden: a row that came and went would move the button under it.
      CaptionColorRow(
        colors: kCaptionHighlightColors,
        selected: style.highlight.color,
        enabled: captionHighlightUsesColor(style.highlight.style),
        keyFor: (i) => Key('captions_color_$i'),
        onSelected: widget.onColor,
      ),
    ];
  }

  Widget _action() {
    final run = widget.run;
    return switch (widget.step) {
      CaptionsStep.ready => CompressPrimaryButton(
          key: const Key('captions_generate'),
          label: 'Generate captions',
          icon: LucideIcons.subtitles,
          onPressed: widget.onGenerate,
        ),
      CaptionsStep.generating when run != null && run.error != null => Row(
          children: [
            Expanded(
              child: CompressGlassButton(
                key: const Key('captions_cancel'),
                label: 'Cancel',
                onPressed: widget.onCancel,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CompressPrimaryButton(
                key: const Key('captions_retry'),
                label: 'Try again',
                icon: LucideIcons.rotateCcw,
                onPressed: run.retry,
              ),
            ),
          ],
        ),
      CaptionsStep.generating => CompressGlassButton(
          key: const Key('captions_cancel'),
          label: 'Cancel',
          onPressed: widget.onCancel,
        ),
      CaptionsStep.done => CompressPrimaryButton(
          key: const Key('captions_export'),
          label: 'Export',
          icon: LucideIcons.download,
          onPressed: widget.onExport,
        ),
    };
  }
}

/// "Aa Edit words": the caption list, for a misheard word.
class _EditWordsChip extends StatelessWidget {
  const _EditWordsChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          key: const Key('captions_edit_words'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.caseSensitive,
                  size: 16,
                  color: AppColors.textPrimary,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Edit words',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
