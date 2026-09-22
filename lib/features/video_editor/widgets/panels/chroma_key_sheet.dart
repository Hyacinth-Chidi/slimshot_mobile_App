import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/chroma/chroma_key.dart';
import '../../providers/video_editor_notifier.dart';
import 'editor_sheet.dart';
import 'value_ruler.dart';

/// One edge inset, matching every other sheet's.
const double _kEdge = 16;

/// How much one pixel of ruler travel moves a 0..1 chroma parameter. 250px end
/// to end: a full sweep is a comfortable thumb drag, and the fine control that
/// a key actually needs is there without a second gesture.
const double kChromaUnitsPerPixel = 0.004;

/// Which parameter the one ruler is showing.
enum _ChromaParameter { similarity, smoothness, spill }

/// The Chroma key sheet — drop a colour so the background shows through.
///
/// A sheet by the project's rule: this is a set of choices about the picture,
/// not an edit made on the canvas. It writes `VideoSegment.chromaKey`, which
/// the shader resolves as a coverage exactly where the mask's is — so the key
/// composites against the project background, and every transition inherits it.
///
/// **The toggle is not destructive.** Turning the key off keeps its colour and
/// tuning, so a user comparing keyed against unkeyed does not lose their work
/// and have to dial it in again.
class ChromaKeySheet extends ConsumerStatefulWidget {
  const ChromaKeySheet({super.key});

  @override
  ConsumerState<ChromaKeySheet> createState() => _ChromaKeySheetState();
}

class _ChromaKeySheetState extends ConsumerState<ChromaKeySheet> {
  _ChromaParameter _param = _ChromaParameter.similarity;

  VideoEditorNotifier get _notifier => ref.read(videoEditorProvider.notifier);

  /// The screen colours a key is actually set to in practice. Anything else is
  /// reachable by picking one of these and tuning, which is a better trade than
  /// a colour wheel nobody needs for a green screen.
  static const List<({String id, String label, Color colour})> _presets = [
    (id: 'green', label: 'Green', colour: Color(0xFF00FF00)),
    (id: 'blue', label: 'Blue', colour: Color(0xFF0000FF)),
    (id: 'white', label: 'White', colour: Color(0xFFFFFFFF)),
    (id: 'black', label: 'Black', colour: Color(0xFF000000)),
  ];

  /// Whatever is selected — a clip, a photo overlay or a video overlay. One
  /// chroma editor for all three, so there is no second one to drift from it.
  ChromaKey get _key => _notifier.chromaKeyOnSelection;

  void _write(ChromaKey key, {bool live = false}) =>
      _notifier.setChromaKeyOnSelection(key, live: live);

  void _toggle() {
    HapticFeedback.selectionClick();
    _write(_key.copyWith(enabled: !_key.enabled));
  }

  void _chooseColour(Color colour) {
    HapticFeedback.selectionClick();
    // Choosing a colour is also how a user turns the key on — asking them to
    // flip the switch first would be a step with no decision in it.
    _write(_key.copyWith(
      enabled: true,
      keyR: colour.r,
      keyG: colour.g,
      keyB: colour.b,
    ));
  }

  double _valueOf(ChromaKey key) => switch (_param) {
        _ChromaParameter.similarity => key.similarity,
        _ChromaParameter.smoothness => key.smoothness,
        _ChromaParameter.spill => key.spill,
      };

  ChromaKey _withValue(ChromaKey key, double v) {
    final c = v.clamp(0.0, 1.0).toDouble();
    return switch (_param) {
      _ChromaParameter.similarity => key.copyWith(similarity: c),
      _ChromaParameter.smoothness => key.copyWith(smoothness: c),
      _ChromaParameter.spill => key.copyWith(spill: c),
    };
  }

  static String _label(_ChromaParameter p) => switch (p) {
        _ChromaParameter.similarity => 'Similarity',
        _ChromaParameter.smoothness => 'Smoothness',
        _ChromaParameter.spill => 'Spill',
      };

  @override
  Widget build(BuildContext context) {
    // Watched so the sheet rebuilds as the key is tuned; the value itself
    // comes from the notifier, which resolves whichever thing is selected.
    ref.watch(videoEditorProvider);
    final key = _notifier.chromaKeyOnSelection;
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
              _handle(),
              _header(key),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 4),
                      _colourRow(key),
                      // The tuning appears only once there is something to
                      // tune, so an unkeyed clip shows two controls, not five.
                      if (key.enabled) ...[
                        const SizedBox(height: 14),
                        _pillRow(),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: _kEdge),
                          child: ValueRuler(
                            key: ValueKey(_param),
                            value: _valueOf(key),
                            min: 0,
                            max: 1,
                            unitsPerPixel: kChromaUnitsPerPixel,
                            onChangeStart: _notifier.beginChromaKeyOnSelection,
                            onChanged: (v) =>
                                _write(_withValue(_key, v), live: true),
                            format: (v) => v.toStringAsFixed(2),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ChromaKey key) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kEdge),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Chroma key',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          Row(
            children: [
              GestureDetector(
                key: const Key('chroma_enabled'),
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Icon(
                    key.enabled ? LucideIcons.toggleRight : LucideIcons.toggleLeft,
                    color: key.enabled
                        ? AppColors.primaryStart
                        : AppColors.textSecondary,
                    size: 26,
                  ),
                ),
              ),
              GestureDetector(
                key: const Key('chroma_done'),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop();
                },
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    LucideIcons.check,
                    color: AppColors.primaryStart,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Whether [key] is currently keying [colour], within a tolerance that lets
  /// a hand-tuned value still read as "green".
  bool _isCurrent(ChromaKey key, Color colour) {
    if (!key.enabled) return false;
    const tolerance = 0.01;
    return (key.keyR - colour.r).abs() < tolerance &&
        (key.keyG - colour.g).abs() < tolerance &&
        (key.keyB - colour.b).abs() < tolerance;
  }

  Widget _colourRow(ChromaKey key) {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        children: [
          for (final p in _presets)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                key: Key('chroma_colour_${p.id}'),
                onTap: () => _chooseColour(p.colour),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: p.colour,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isCurrent(key, p.colour)
                          ? AppColors.primaryStart
                          : AppColors.border,
                      width: _isCurrent(key, p.colour) ? 2.5 : 1.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pillRow() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        children: [
          for (final p in _ChromaParameter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                key: Key('chroma_tab_${p.name}'),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _param = p);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        _param == p ? AppColors.primaryStart : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    _label(p),
                    style: TextStyle(
                      color: _param == p ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _handle() {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
