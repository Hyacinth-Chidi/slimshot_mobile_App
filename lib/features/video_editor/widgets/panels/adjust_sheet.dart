import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/color/color_adjustments.dart';
import '../../providers/video_editor_notifier.dart';
import 'apply_to_all_toggle.dart';
import 'editor_sheet.dart';
import 'value_ruler.dart';

/// How much one pixel of ruler travel moves an adjustment (-1..1 range).
/// 200px end to end: a whole-thumb sweep for a full swing, finer than that
/// for a nudge.
const double kAdjustUnitsPerPixel = 0.005;

/// One edge inset for the sheet, matching every other sheet's.
const double _kEdge = 16;

/// The Adjust sheet: brightness, contrast, saturation and temperature, one
/// ruler at a time behind four pills, writing live.
///
/// **Which level a drag writes** is the apply-to-all toggle's, the same control
/// Filters and Transitions use. Opened from the clip menu it starts on the
/// selected clip; opened from the root menu — nothing selected — it is the
/// project's, and the toggle is not shown because there is no other target.
/// The ruler always shows the level it writes, so a project set warm and a
/// clip pulled cool never share one reading.
///
/// The maths lives in `logic/color/color_adjustments.dart` and composes into
/// the colour matrices the engine already grades with, so this sheet has no
/// engine of its own to drift from the preview.
class AdjustSheet extends ConsumerStatefulWidget {
  const AdjustSheet({super.key});

  @override
  ConsumerState<AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends ConsumerState<AdjustSheet> {
  AdjustParameter _param = AdjustParameter.brightness;

  /// Writing the project (true) or the selected clip (false). Starts on the
  /// clip when one is selected, because that is what the user opened it on.
  late bool _toProject =
      ref.read(videoEditorProvider).selectedSegment == null;

  VideoEditorNotifier get _notifier => ref.read(videoEditorProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoEditorProvider);
    final segment = state.selectedSegment;
    final toProject = _toProject || segment == null;
    final current = toProject
        ? state.adjustments
        : (segment.adjustments);
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _kEdge),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Adjust',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    GestureDetector(
                      key: const Key('adjust_done'),
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
              ),
              // Loose, so the body takes only its height on a tall screen and
              // scrolls under the cap on a short or landscape one rather than
              // overflowing.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (segment != null)
                        ApplyToAllToggle(
                          value: _toProject,
                          subtitle: _toProject
                              ? 'Adjusting the whole video'
                              : 'Adjusting the selected clip only',
                          onChanged: (v) => setState(() => _toProject = v),
                        ),
                      const SizedBox(height: 6),
                      _pillRow(),
                      const SizedBox(height: 14),
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(_kEdge, 0, _kEdge, _kEdge),
                        child: ValueRuler(
                          value: current.valueOf(_param),
                          min: -1.0,
                          max: 1.0,
                          unitsPerPixel: kAdjustUnitsPerPixel,
                          snapPoints: const [0.0],
                          format: _format,
                          // One undo snapshot per drag; the frames below
                          // write live.
                          onChangeStart: _notifier.saveStateForUndo,
                          onChanged: (next) => _write(
                            current.withValue(_param, next),
                            toProject: toProject,
                            takeUndoSnapshot: false,
                          ),
                          onReset: () => _write(
                            current.withValue(_param, 0.0),
                            toProject: toProject,
                            takeUndoSnapshot: true,
                          ),
                        ),
                      ),
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

  void _write(
    ColorAdjustments next, {
    required bool toProject,
    required bool takeUndoSnapshot,
  }) {
    if (toProject) {
      _notifier.setProjectAdjustments(next, takeUndoSnapshot: takeUndoSnapshot);
    } else {
      _notifier.setClipAdjustments(next, takeUndoSnapshot: takeUndoSnapshot);
    }
  }

  /// `+35`, `-20`, `0`: a signed percentage of the range, the way every
  /// editor's Adjust reads.
  static String _format(double v) {
    final pct = (v * 100).round();
    if (pct == 0) return '0';
    return '${pct > 0 ? '+' : ''}$pct';
  }

  /// The parameter row, in the same pill shape the other sheets use for their
  /// categories: a filled capsule for the active one, plain text otherwise.
  Widget _pillRow() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        children: [
          for (final p in AdjustParameter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                key: Key('adjust_tab_${p.name}'),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _param = p);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _param == p ? AppColors.primaryStart : Colors.transparent,
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

  static String _label(AdjustParameter p) => switch (p) {
        AdjustParameter.brightness => 'Brightness',
        AdjustParameter.contrast => 'Contrast',
        AdjustParameter.saturation => 'Saturation',
        AdjustParameter.temperature => 'Temperature',
      };

  /// The grab handle, drawn exactly as every other sheet in the app draws it.
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
