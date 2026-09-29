import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/lucide_icons.dart';
import '../../logic/captions/caption_settings.dart';
import '../../models/text_overlay_model.dart';
import '../../providers/video_editor_notifier.dart';
import 'caption_sheet_parts.dart';

/// A caption's start as the list shows it: `1:04.2`.
String formatCaptionTime(Duration time) {
  final ms = math.max(0, time.inMilliseconds);
  final minutes = ms ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  final tenths = (ms % 1000) ~/ 100;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
}

/// Every caption of the project, in the order spoken: read down it, fix what
/// was misheard.
///
/// A list to read and type into rather than a choice about the picture, so it
/// takes the taller height the audio library has and rides above the
/// keyboard. No title — the user tapped Captions to get here.
///
/// **Typing is one undo step per caption**, taken on the first change and not
/// on focus: a field only looked at leaves nothing to undo. The words' timing
/// is kept by the notifier, not here — see `VideoEditorNotifier._setText`.
class CaptionBatchSheet extends ConsumerStatefulWidget {
  const CaptionBatchSheet({
    super.key,
    this.initialCaptionId,
    required this.onSeek,
  });

  /// The caption the list opens on — the one it was opened from.
  final String? initialCaptionId;

  /// Moves the playhead to a timeline instant, in seconds.
  final ValueChanged<double> onSeek;

  @override
  ConsumerState<CaptionBatchSheet> createState() => _CaptionBatchSheetState();
}

class _CaptionBatchSheetState extends ConsumerState<CaptionBatchSheet> {
  /// Fixed, so the list can open on a caption without laying out the ones
  /// before it.
  static const double _rowExtent = 60;
  static const double _actionSize = 40;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  /// The caption whose typing has taken its undo step.
  String? _editingId;

  late final ScrollController _scroll;

  static List<TextOverlayModel> _captionsOf(List<TextOverlayModel> texts) =>
      texts.where((t) => t.isCaption).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  @override
  void initState() {
    super.initState();
    final captions = _captionsOf(ref.read(videoEditorProvider).textOverlays);
    final index = captions.indexWhere((c) => c.id == widget.initialCaptionId);
    _scroll = ScrollController(
      initialScrollOffset: math.max(0, index) * _rowExtent,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(TextOverlayModel caption) =>
      _controllers.putIfAbsent(
        caption.id,
        () => TextEditingController(text: caption.text),
      );

  FocusNode _focusFor(String id) => _focusNodes.putIfAbsent(id, () {
        final node = FocusNode();
        node.addListener(() {
          if (!node.hasFocus && _editingId == id) _editingId = null;
        });
        return node;
      });

  /// Brings the fields into line with the project after a change that did not
  /// come from typing in them: an undo, a split, a re-cut.
  void _syncFields(List<TextOverlayModel> texts) {
    final captions = {for (final c in _captionsOf(texts)) c.id: c};
    for (final entry in _controllers.entries) {
      final caption = captions[entry.key];
      if (caption != null && entry.value.text != caption.text) {
        entry.value.text = caption.text;
      }
    }
    final gone = [
      for (final id in _controllers.keys)
        if (!captions.containsKey(id)) id,
    ];
    for (final id in gone) {
      _controllers.remove(id)?.dispose();
      _focusNodes.remove(id)?.dispose();
      if (_editingId == id) _editingId = null;
    }
  }

  void _onTyped(String id, String text) {
    final notifier = ref.read(videoEditorProvider.notifier);
    if (_editingId != id) {
      notifier.saveStateForUndo();
      _editingId = id;
    }
    notifier.updateTextOverlayLive(id, (o) => o.copyWith(text: text));
  }

  void _split(TextOverlayModel caption) {
    final cursor = _controllerFor(caption).selection.baseOffset;
    HapticFeedback.selectionClick();
    ref.read(videoEditorProvider.notifier).splitCaptionAt(
          caption.id,
          cursor < 0 ? caption.text.length ~/ 2 : cursor,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      videoEditorProvider.select((s) => s.textOverlays),
      (_, texts) => _syncFields(texts),
    );
    final state = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final captions = _captionsOf(state.textOverlays);
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetGrabHandle(),
                Row(
                  children: [
                    Expanded(
                      child: CaptionPillRow<CaptionLength>(
                        values: CaptionLength.values,
                        selected: state.captionSettings?.length ??
                            CaptionLength.phrase,
                        label: (l) => switch (l) {
                          CaptionLength.word => 'Word',
                          CaptionLength.phrase => 'Phrase',
                          CaptionLength.line => 'Line',
                        },
                        keyFor: (l) => Key('caption_length_${l.name}'),
                        onSelected: notifier.recutCaptions,
                      ),
                    ),
                    GestureDetector(
                      key: const Key('caption_delete_all'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        notifier.deleteAllCaptions();
                        Navigator.of(context).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.trash2,
                              size: 16,
                              color: AppColors.error,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Delete all',
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    itemExtent: _rowExtent,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: captions.length,
                    itemBuilder: (context, i) => _row(
                      captions[i],
                      isLast: i == captions.length - 1,
                      notifier: notifier,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    TextOverlayModel caption, {
    required bool isLast,
    required VideoEditorNotifier notifier,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          GestureDetector(
            key: Key('caption_time_${caption.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              notifier.selectTextOverlay(caption.id);
              widget.onSeek(caption.startTime.inMilliseconds / 1000);
            },
            child: SizedBox(
              width: 64,
              height: _rowExtent,
              child: Center(
                child: Text(
                  formatCaptionTime(caption.startTime),
                  style: const TextStyle(
                    color: AppColors.primaryStart,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              key: Key('caption_field_${caption.id}'),
              controller: _controllerFor(caption),
              focusNode: _focusFor(caption.id),
              maxLines: 1,
              textInputAction: TextInputAction.done,
              cursorColor: AppColors.primaryStart,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (text) => _onTyped(caption.id, text),
            ),
          ),
          _action(
            key: 'caption_split_${caption.id}',
            icon: LucideIcons.scissors,
            tooltip: 'Split',
            onTap: () => _split(caption),
          ),
          if (isLast)
            const SizedBox(width: _actionSize)
          else
            _action(
              key: 'caption_merge_${caption.id}',
              icon: LucideIcons.merge,
              tooltip: 'Merge with next',
              onTap: () {
                HapticFeedback.selectionClick();
                notifier.mergeCaptionWithNext(caption.id);
              },
            ),
          _action(
            key: 'caption_delete_${caption.id}',
            icon: LucideIcons.trash2,
            tooltip: 'Delete',
            onTap: () {
              HapticFeedback.selectionClick();
              notifier.deleteTextOverlay(caption.id);
            },
          ),
        ],
      ),
    );
  }

  Widget _action({
    required String key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: Key(key),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _actionSize,
          height: _rowExtent,
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
