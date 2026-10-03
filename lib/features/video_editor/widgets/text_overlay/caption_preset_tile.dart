import 'package:flutter/material.dart';

import '../../logic/captions/caption_preset_catalog.dart';
import '../../logic/captions/caption_word.dart';
import '../../models/text_overlay_model.dart';
import 'text_preview_tile.dart';

/// How long each sample word is spoken in a tile — long enough to read the
/// highlight land on it, short enough that a loop does not drag.
const double kCaptionPresetWordSeconds = 0.45;

/// A live preview of one caption style: a caption wearing the preset's look,
/// in its sample words, **with the words timed across the loop** so the
/// highlight plays as it will on the canvas.
///
/// Painted by the canvas's own painter through [TextPreviewTile], like every
/// text preview tile — a tile that drew its own idea of a highlight would
/// promise something the canvas and the export do not deliver.
class CaptionPresetTile extends StatelessWidget {
  const CaptionPresetTile({
    super.key,
    required this.preset,
    required this.onTap,
    this.clock,
    this.isSelected = false,
  });

  final CaptionPreset preset;
  final VoidCallback onTap;
  final Listenable? clock;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final text = preset.sampleText.trim();
    final matches = RegExp(r'\S+').allMatches(text).toList();
    final span =
        matches.length * kCaptionPresetWordSeconds + kTextPreviewRestSeconds;
    Duration at(double seconds) =>
        Duration(microseconds: (seconds * 1e6).round());

    final caption = preset.look.applyTo(
      TextOverlayModel(
        id: 'tile-${preset.id}',
        text: text,
        startTime: Duration.zero,
        endTime: at(span),
        referenceCanvasSize: kTextPreviewCanvas,
        captionSetId: 'tile',
        captionWords: [
          for (var i = 0; i < matches.length; i++)
            CaptionWord(
              textStart: matches[i].start,
              textEnd: matches[i].end,
              start: at(i * kCaptionPresetWordSeconds),
              end: at((i + 0.85) * kCaptionPresetWordSeconds),
            ),
        ],
        highlight: preset.highlight,
      ),
    );

    return TextPreviewTile(
      overlay: caption,
      spanSeconds: span,
      label: preset.name,
      isSelected: isSelected,
      onTap: onTap,
      clock: clock,
    );
  }
}

/// The caption styles, three to a row like every grid of text previews.
///
/// **Not a scrollable of its own**: it sits in the caption sheet's scroll, so
/// the sheet owns the [clock] and holds it while it scrolls
/// (`holdPreviewClockWhileScrolling`).
class CaptionPresetGrid extends StatelessWidget {
  const CaptionPresetGrid({
    super.key,
    required this.presets,
    required this.onSelected,
    this.selectedId,
    this.clock,
  });

  final List<CaptionPreset> presets;

  /// Fired once per tap with the preset tapped.
  final ValueChanged<CaptionPreset> onSelected;

  /// The preset the set is wearing, highlighted — or null.
  final String? selectedId;

  final Listenable? clock;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: kTextPreviewGrid,
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final preset = presets[index];
        return CaptionPresetTile(
          key: Key('caption_preset_${preset.id}'),
          preset: preset,
          isSelected: preset.id == selectedId,
          clock: clock,
          onTap: () => onSelected(preset),
        );
      },
    );
  }
}
