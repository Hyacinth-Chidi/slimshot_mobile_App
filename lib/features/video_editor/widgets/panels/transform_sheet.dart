import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/animation/clip_keyframes.dart';
import '../../models/media_asset.dart';
import '../../models/video_editor_state.dart';
import '../../models/video_segment.dart';
import '../../providers/video_editor_notifier.dart';
import '../../services/native_timeline_preview_service.dart';
import 'value_ruler.dart';

/// The Transform sheet: **Scale / Rotate / Position**, each driven by a ruler.
///
/// Styled from the curve sheet, which is styled from the effects sheet — the
/// same background and corner radius, the same grab handle, the same pill row
/// for the tabs, one edge inset everything aligns to. That pattern now exists
/// in three places; this does not invent a fourth.
///
/// **No keyframe control, and none needed.** Every ruler writes through the
/// edit rule (`updateClipCanvasTransform` → `_writeClipValue`) and shows what
/// that write will target (`clipEditValue`), so on a clip carrying diamonds a
/// drag keyframes itself and the ruler reads the value at the playhead. The
/// sheet is presentation over parameters the pinch gesture already owns —
/// rotation is the one it adds.
///
/// **The engine hears every frame through the override channel**, exactly as
/// the pinch does, so the picture follows the finger without a timeline push
/// per frame — and the screen catches the engine up once on release.
class TransformSheet extends ConsumerStatefulWidget {
  const TransformSheet({super.key});

  @override
  ConsumerState<TransformSheet> createState() => _TransformSheetState();
}

enum _Tab { scale, rotate, position }

const double _kEdge = 16;
const double _kTabRowHeight = 36;

/// Degrees per pixel on the Rotate ruler: a full turn in 720px, about two
/// drags across a phone.
const double _kDegreesPerPixel = 0.5;

/// Scale per pixel: one whole `×` in 100px, so 1.00→2.00 is a short drag and
/// the readout still moves in hundredths.
const double _kScalePerPixel = 0.01;

/// Canvas fraction per pixel for position: the full canvas width in 200px.
const double _kOffsetPerPixel = 0.005;

class _TransformSheetState extends ConsumerState<TransformSheet> {
  _Tab _tab = _Tab.scale;

  /// The same shared channel the canvas uses. A new instance is fine: the
  /// service's event stream is shared across instances by design.
  final _preview = NativeTimelinePreviewService();

  VideoEditorNotifier get _notifier => ref.read(videoEditorProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoEditorProvider);
    final segment = state.selectedSegment;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            if (segment == null)
              const Padding(
                padding: EdgeInsets.fromLTRB(_kEdge, 8, _kEdge, 28),
                child: Text(
                  'Select a clip to transform.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              _tabRow(),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _kEdge),
                child: _body(state, segment),
              ),
              const SizedBox(height: _kEdge),
            ],
          ],
        ),
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

  /// The pill row, as the effects and curve sheets draw theirs.
  Widget _tabRow() {
    const labels = {
      _Tab.scale: 'Scale',
      _Tab.rotate: 'Rotate',
      _Tab.position: 'Position',
    };
    return SizedBox(
      height: _kTabRowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        itemCount: _Tab.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = _Tab.values[index];
          final isActive = tab == _tab;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tab = tab),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                labels[tab]!,
                style: TextStyle(
                  color:
                      isActive ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(VideoEditorState state, VideoSegment segment) {
    // What each ruler shows: the value its write will target.
    double shown(ClipProperty p) => state.clipEditValue(segment, p);

    switch (_tab) {
      case _Tab.scale:
        return _ruler(
          segment: segment,
          property: ClipProperty.canvasScale,
          value: shown(ClipProperty.canvasScale),
          min: kMinClipCanvasScale,
          max: kMaxClipCanvasScale,
          unitsPerPixel: _kScalePerPixel,
          snapPoints: const [1.0],
          resetTo: 1.0,
          format: (v) => '${v.toStringAsFixed(2)}×',
        );
      case _Tab.rotate:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ruler(
              segment: segment,
              property: ClipProperty.canvasRotation,
              value: shown(ClipProperty.canvasRotation),
              min: -180,
              max: 180,
              unitsPerPixel: _kDegreesPerPixel,
              // Right angles are what a rotation is usually reaching for; a
              // reading of 89.6° is a mistake nobody meant.
              snapPoints: const [0, 90, -90, 180, -180],
              resetTo: 0.0,
              format: (v) => '${v.toStringAsFixed(1)}°',
            ),
            const SizedBox(height: 12),
            // Mirrors live with rotation because that is where a user looks
            // for them, and because a mirror is the one orientation change a
            // rotation cannot make.
            Row(
              children: [
                _flipToggle(
                  key: const Key('flip_horizontal'),
                  icon: LucideIcons.flipHorizontal,
                  label: 'Flip H',
                  on: segment.flipHorizontal,
                  onTap: () => _notifier.toggleClipFlip(horizontal: true),
                ),
                const SizedBox(width: 10),
                _flipToggle(
                  key: const Key('flip_vertical'),
                  icon: LucideIcons.flipVertical,
                  label: 'Flip V',
                  on: segment.flipVertical,
                  onTap: () => _notifier.toggleClipFlip(horizontal: false),
                ),
              ],
            ),
          ],
        );
      case _Tab.position:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _labelled(
              'X',
              _ruler(
                segment: segment,
                property: ClipProperty.canvasOffsetX,
                value: shown(ClipProperty.canvasOffsetX),
                min: -1.5,
                max: 1.5,
                unitsPerPixel: _kOffsetPerPixel,
                snapPoints: const [0.0],
                resetTo: 0.0,
                format: _percent,
              ),
            ),
            const SizedBox(height: 10),
            _labelled(
              'Y',
              _ruler(
                segment: segment,
                property: ClipProperty.canvasOffsetY,
                value: shown(ClipProperty.canvasOffsetY),
                min: -1.5,
                max: 1.5,
                unitsPerPixel: _kOffsetPerPixel,
                snapPoints: const [0.0],
                resetTo: 0.0,
                format: _percent,
              ),
            ),
          ],
        );
    }
  }

  /// A mirror toggle in the sheet's selection language: `primaryStart` border
  /// over `highlight` fill when on, the plain surface when off.
  Widget _flipToggle({
    required Key key,
    required IconData icon,
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? AppColors.highlight : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: on ? AppColors.primaryStart : AppColors.border,
            width: on ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: on ? AppColors.textPrimary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: on ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Position as a signed percentage of the canvas — `+12%` reads as "a bit
  /// right", where `0.12` reads as nothing in particular.
  static String _percent(double v) {
    final pct = (v * 100).round();
    if (pct == 0) return '0%';
    return '${pct > 0 ? '+' : ''}$pct%';
  }

  Widget _labelled(String axis, Widget ruler) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          child: Text(
            axis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: ruler),
      ],
    );
  }

  Widget _ruler({
    required VideoSegment segment,
    required ClipProperty property,
    required double value,
    required double min,
    required double max,
    required double unitsPerPixel,
    required List<double> snapPoints,
    required double resetTo,
    required String Function(double) format,
  }) {
    return ValueRuler(
      value: value,
      min: min,
      max: max,
      unitsPerPixel: unitsPerPixel,
      snapPoints: snapPoints,
      format: format,
      // One undo snapshot per drag, taken here; the frames below write live.
      onChangeStart: _notifier.beginClipCanvasTransform,
      onChanged: (next) => _write(segment, property, next),
      onChangeEnd: _notifier.endClipCanvasTransform,
      // A one-shot write through the snapshotting setter: undoable on its own,
      // and the screen pushes the timeline once the state settles.
      onReset: () => _notifier.setClipProperty(property, resetTo),
    );
  }

  /// One property moves; the other three are handed back exactly as they are
  /// **shown** — the edit-target values — so on a keyframed clip they write
  /// their own resolved value back to the same keyframe, which is a no-op, and
  /// on an unkeyframed one they write base to base.
  void _write(VideoSegment segment, ClipProperty property, double next) {
    final state = ref.read(videoEditorProvider);
    double current(ClipProperty p) =>
        p == property ? next : state.clipEditValue(segment, p);

    final scale = current(ClipProperty.canvasScale);
    final offsetX = current(ClipProperty.canvasOffsetX);
    final offsetY = current(ClipProperty.canvasOffsetY);
    final rotation = current(ClipProperty.canvasRotation);

    // State for persistence and undo; the override channel for the live
    // picture. The full timeline push is gated until the gesture ends — the
    // identical split the canvas pinch makes.
    _notifier.updateClipCanvasTransform(
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY,
      rotation: rotation,
    );
    _preview.setClipTransform(
      clipId: segment.id,
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY,
      rotation: rotation,
    );
  }
}
