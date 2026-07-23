import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/services/media_picker_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/permission_dialog.dart';
import '../core/services/ad_service.dart';
import 'export_video_screen.dart';
import '../features/video_editor/widgets/panels/transitions_drawer.dart';
import '../features/video_editor/models/text_overlay_model.dart';
import '../features/video_editor/models/image_overlay_model.dart';
import '../features/video_editor/models/video_segment.dart';
import '../features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/filter_preset.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import '../features/video_editor/logic/filter_presets.dart';
import '../features/video_editor/providers/video_editor_notifier.dart';
import '../features/video_editor/services/video_editor_service.dart';
import '../core/models/draft_project.dart';
import '../features/video_editor/widgets/editor_playback_controls.dart';
import '../features/video_editor/widgets/timeline/scrollable_timeline.dart';
import 'package:flutter/scheduler.dart';
import '../features/video_editor/widgets/video_editor_top_bar.dart';
import '../features/video_editor/widgets/panels/audio_drawer.dart';
import '../features/video_editor/widgets/panels/filters_drawer.dart';
import '../features/video_editor/widgets/panels/stickers_drawer.dart';
import '../features/video_editor/services/audio_player_manager.dart';
import '../features/video_editor/models/audio_track_model.dart';
import '../features/video_editor/widgets/text_overlay/text_editor_dialog.dart';
import '../features/video_editor/widgets/canvas/video_preview_canvas.dart';
import '../features/video_editor/widgets/panels/audio_panel.dart';
import '../features/video_editor/widgets/panels/crop_panel.dart';
import '../features/video_editor/widgets/panels/placeholder_panel.dart';
import '../features/video_editor/widgets/panels/speed_panel.dart';
import '../features/video_editor/widgets/panels/trim_panel.dart';
import '../features/video_editor/widgets/panels/volume_panel.dart';
import '../features/video_editor/widgets/panels/zoom_panel.dart';
import '../features/video_editor/widgets/panels/text_panels.dart';
import '../features/video_editor/widgets/panels/background_panel.dart';
import '../features/video_editor/widgets/panels/opacity_panel.dart';
import '../features/video_editor/widgets/panels/animation_drawer.dart';

class EditorTool {
  final String id;
  final String label;
  final IconData icon;
  final bool hasSubMenu;

  const EditorTool({
    required this.id,
    required this.label,
    required this.icon,
    this.hasSubMenu = false,
  });
}

class EditorMenu {
  final String id;
  final List<EditorTool> tools;
  const EditorMenu({required this.id, required this.tools});
}

const EditorMenu _rootMenu = EditorMenu(
  id: 'root',
  tools: [
    EditorTool(
      id: 'edit',
      label: 'Edit',
      icon: LucideIcons.scissors,
      hasSubMenu: true,
    ),
    EditorTool(
      id: 'audio',
      label: 'Audio',
      icon: LucideIcons.music,
      hasSubMenu: true,
    ),
    EditorTool(
      id: 'text',
      label: 'Text',
      icon: LucideIcons.type,
      hasSubMenu: true,
    ),
    EditorTool(id: 'overlay', label: 'Overlay', icon: LucideIcons.layers),
    EditorTool(
      id: 'transform',
      label: 'Transform',
      icon: LucideIcons.move,
      hasSubMenu: true,
    ),
    EditorTool(id: 'filters', label: 'Filters', icon: LucideIcons.sliders),
    EditorTool(id: 'animate', label: 'Animate', icon: LucideIcons.clapperboard),
    EditorTool(id: 'effects', label: 'Effects', icon: LucideIcons.sparkles),
    EditorTool(id: 'stickers', label: 'Stickers', icon: LucideIcons.smile),
  ],
);

const EditorMenu _editMenu = EditorMenu(
  id: 'edit',
  tools: [
    EditorTool(
      id: 'split',
      label: 'Split',
      icon: LucideIcons.splitSquareHorizontal,
    ),
    EditorTool(id: 'speed', label: 'Speed', icon: LucideIcons.gauge),
    EditorTool(id: 'volume', label: 'Volume', icon: LucideIcons.volume2),
    EditorTool(
      id: 'transition',
      label: 'Transition',
      icon: LucideIcons.arrowLeftRight,
    ),
    EditorTool(id: 'reverse', label: 'Reverse', icon: LucideIcons.rewind),
    EditorTool(id: 'delete', label: 'Delete', icon: LucideIcons.trash2),
  ],
);

const EditorMenu _audioMenu = EditorMenu(
  id: 'audio',
  tools: [
    EditorTool(id: 'sounds', label: 'Sounds', icon: LucideIcons.music),
    EditorTool(id: 'effects', label: 'Effects', icon: LucideIcons.sparkles),
    EditorTool(id: 'extract', label: 'Extract', icon: LucideIcons.folderOpen),
    EditorTool(id: 'record', label: 'Record', icon: LucideIcons.mic),
  ],
);

const EditorMenu _transformMenu = EditorMenu(
  id: 'transform',
  tools: [
    EditorTool(id: 'crop', label: 'Crop', icon: LucideIcons.crop),
    EditorTool(id: 'zoom', label: 'Zoom', icon: LucideIcons.zoomIn),
    EditorTool(id: 'rotate', label: 'Rotate', icon: LucideIcons.rotateCcw),
    EditorTool(id: 'background', label: 'Background', icon: LucideIcons.image),
  ],
);

const EditorMenu _imageOverlayMenu = EditorMenu(
  id: 'image_overlay',
  tools: [
    EditorTool(
      id: 'animation',
      label: 'Animation',
      icon: LucideIcons.playCircle,
    ),
    EditorTool(id: 'opacity', label: 'Opacity', icon: LucideIcons.contrast),
    EditorTool(id: 'duplicate', label: 'Copy', icon: LucideIcons.copy),
    EditorTool(id: 'delete', label: 'Delete', icon: LucideIcons.trash2),
  ],
);

const EditorMenu _videoOverlayMenu = EditorMenu(
  id: 'video_overlay',
  tools: [
    EditorTool(
      id: 'split',
      label: 'Split',
      icon: LucideIcons.splitSquareHorizontal,
    ),
    EditorTool(
      id: 'animation',
      label: 'Animation',
      icon: LucideIcons.playCircle,
    ),
    EditorTool(id: 'volume', label: 'Volume', icon: LucideIcons.volume2),
    EditorTool(id: 'opacity', label: 'Opacity', icon: LucideIcons.contrast),
    EditorTool(id: 'duplicate', label: 'Copy', icon: LucideIcons.copy),
    EditorTool(id: 'delete', label: 'Delete', icon: LucideIcons.trash2),
  ],
);

final Map<String, EditorMenu> _menus = {
  'root': _rootMenu,
  'edit': _editMenu,

  'audio': _audioMenu,
  'transform': _transformMenu,
  'image_overlay': _imageOverlayMenu,
  'video_overlay': _videoOverlayMenu,
  'transition': const EditorMenu(
    id: 'transition',
    tools: [],
  ), // Transitions drawer replaces the tools list
};

class VideoEditorScreen extends ConsumerStatefulWidget {
  final XFile? initialVideo;
  final DraftProject? draft;

  const VideoEditorScreen({super.key, this.initialVideo, this.draft});

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayerManager _audioPlayerManager = AudioPlayerManager();

  late final Ticker _ticker;
  DateTime? _lastTick;

  Player? _player;
  VideoController? _videoController;

  bool _isFullscreen = false;

  int _exportHeight = 1080;
  int _exportFps = 30;
  final GlobalKey _resolutionButtonKey = GlobalKey();

  String get _resolutionLabel {
    if (_exportHeight <= 720) return 'SD';
    if (_exportHeight == 1080) return 'HD';
    if (_exportHeight == 1440) return '2K';
    return '4K';
  }

  double _videoTimelineDuration(List<VideoSegment> segments) {
    return segments.fold(0.0, (sum, segment) => sum + segment.duration);
  }

  double _timelineTimeToSourceTime(
    double timelineTime,
    List<VideoSegment> segments,
  ) {
    if (segments.isEmpty) return timelineTime;
    double accumulated = 0.0;
    for (final segment in segments) {
      if (timelineTime >= accumulated &&
          timelineTime <= accumulated + segment.duration) {
        return segment.sourceStart +
            ((timelineTime - accumulated) * segment.speed);
      }
      accumulated += segment.duration;
    }
    return segments.last.sourceEnd;
  }

  Future<void> _syncVideoLayerToTimeline(
    double timelinePosition,
    VideoEditorState editorState, {
    required bool shouldPlay,
    double seekThresholdSeconds = 0.08,
  }) async {
    final player = _player;
    if (player == null) return;

    final videoDuration = _videoTimelineDuration(editorState.segments);
    if (timelinePosition >= videoDuration) {
      if (player.state.playing) {
        await player.pause();
      }
      return;
    }

    final sourceTarget = _timelineTimeToSourceTime(
      timelinePosition,
      editorState.segments,
    );
    final currentSource = player.state.position.inMilliseconds / 1000.0;
    if ((currentSource - sourceTarget).abs() > seekThresholdSeconds) {
      await player.seek(Duration(milliseconds: (sourceTarget * 1000).round()));
    }

    if (shouldPlay && !player.state.playing) {
      await player.play();
    } else if (!shouldPlay && player.state.playing) {
      await player.pause();
    }
  }

  String _getToolLabel(String id) {
    for (final menu in _menus.values) {
      for (final tool in menu.tools) {
        if (tool.id == id) return tool.label;
      }
    }
    return 'Tool';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(videoEditorProvider.notifier).reset();

      final draft = widget.draft;
      final initialVideo = widget.initialVideo;

      if (draft != null) {
        _loadDraft(draft);
      } else if (initialVideo != null) {
        _loadVideo(initialVideo);
      } else {
        // Fallback if navigated without a video or draft
        if (mounted) context.pop();
      }
    });

    _ticker = createTicker(_onTick);
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now();
    final delta = _lastTick != null
        ? now.difference(_lastTick!).inMilliseconds / 1000.0
        : 0.0;
    _lastTick = now;

    final editorState = ref.read(videoEditorProvider);
    if (!editorState.isPlaying) return;

    final notifier = ref.read(videoEditorProvider.notifier);
    final videoDuration = _videoTimelineDuration(editorState.segments);
    final totalDuration = ref.read(totalEditedDurationProvider);

    final newPos = editorState.currentPlaybackPosition + delta;
    if (newPos >= totalDuration) {
      notifier.updatePlaybackPosition(0.0);
      notifier.setPlaying(false);
      _audioPlayerManager.pauseAll();
      return;
    }

    notifier.updatePlaybackPosition(newPos);

    if (newPos >= videoDuration) {
      if (_player?.state.playing == true) {
        _player?.pause();
      }
    } else {
      final player = _player;
      if (player != null) {
        if (!player.state.playing) {
          player.play();
        }
      }
    }

    if (_player?.state.playing == true) {
      _handlePlayerUpdate();
    }

    _audioPlayerManager.seekAndPlaySync(newPos, editorState.audioTracks, true);
  }

  @override
  void dispose() {
    // Save draft when leaving the editor
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(videoEditorProvider.notifier).saveDraft();
    });

    _ticker.dispose();
    _audioPlayerManager.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _loadDraft(DraftProject draft) async {
    final notifier = ref.read(videoEditorProvider.notifier);
    try {
      final oldPlayer = _player;
      final player = Player();
      final controller = VideoController(player);

      await player.open(Media(draft.sourceVideoPath), play: false);
      await oldPlayer?.dispose();

      if (!mounted) {
        await player.dispose();
        return;
      }

      setState(() {
        _player = player;
        _videoController = controller;
      });
      ref.read(playerProvider.notifier).state = player;

      await notifier.loadDraft(draft);
    } catch (e) {
      if (!mounted) return;
      ToastUtils.show(context, 'Error loading draft: $e', isError: true);
    }
  }

  Future<void> _loadVideo(XFile video) async {
    final notifier = ref.read(videoEditorProvider.notifier);
    try {
      final oldPlayer = _player;
      final player = Player();
      final controller = VideoController(player);

      await player.open(Media(video.path), play: false);
      await oldPlayer?.dispose();

      if (!mounted) {
        await player.dispose();
        return;
      }

      var durationMs = player.state.duration.inMilliseconds;
      if (durationMs == 0) {
        final durationObj = await player.stream.duration.firstWhere(
          (d) => d != Duration.zero,
          orElse: () => const Duration(seconds: 1),
        );
        durationMs = durationObj.inMilliseconds;
      }
      final duration = durationMs / 1000.0;

      setState(() {
        _player = player;
        _videoController = controller;
      });
      ref.read(playerProvider.notifier).state = player;

      await notifier.loadAndInitializeVideo(
        video: video,
        durationSeconds: duration > 0 ? duration : 1.0, // fallback
      );
    } catch (e) {
      if (!mounted) return;
      ToastUtils.show(context, 'Error loading video: $e', isError: true);
    }
  }

  void _togglePreview() {
    if (_player != null) {
      ref.read(videoEditorProvider.notifier).togglePreview();
    }
  }

  void _handlePlayerUpdate() {
    final player = _player;
    final editorState = ref.read(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    if (!mounted || player == null) {
      return;
    }

    final state = player.state;
    final positionSeconds = state.position.inMilliseconds / 1000.0;

    if (state.playing) {
      int currentIndex = -1;
      for (int i = 0; i < editorState.segments.length; i++) {
        if (positionSeconds >= editorState.segments[i].sourceStart &&
            positionSeconds < editorState.segments[i].sourceEnd) {
          currentIndex = i;
          break;
        }
      }

      if (currentIndex != -1) {
        double expectedVolume = editorState.segments[currentIndex].volume;
        if (editorState.activeToolId == 'volume' &&
            editorState.previewVolume != null &&
            editorState.selectedAudioId == null) {
          final activeSegment = notifier.getActiveSegment();
          if (activeSegment != null &&
              activeSegment.id == editorState.segments[currentIndex].id) {
            expectedVolume = editorState.previewVolume!;
          }
        }

        final targetPlayerVolume =
            expectedVolume * expectedVolume * 100; // media_kit volume is 0-100
        if ((state.volume - targetPlayerVolume).abs() > 1.0) {
          player.setVolume(targetPlayerVolume);
        }

        double expectedSpeed = editorState.segments[currentIndex].speed;
        if (editorState.activeToolId == 'speed' &&
            editorState.previewSpeed != null) {
          final activeSegment = notifier.getActiveSegment();
          if (activeSegment != null &&
              activeSegment.id == editorState.segments[currentIndex].id) {
            expectedSpeed = editorState.previewSpeed!;
          }
        }

        // Apply negative speed if reversed
        if (editorState.segments[currentIndex].isReversed) {
          expectedSpeed = -expectedSpeed;
        }

        if ((state.rate - expectedSpeed).abs() > 0.01) {
          player.setRate(expectedSpeed);
        }

        if (positionSeconds >=
            editorState.segments[currentIndex].sourceEnd - 0.05) {
          if (currentIndex < editorState.segments.length - 1) {
            final nextSegment = editorState.segments[currentIndex + 1];
            if ((nextSegment.sourceStart -
                        editorState.segments[currentIndex].sourceEnd)
                    .abs() >
                0.05) {
              player.seek(
                Duration(
                  milliseconds: (nextSegment.sourceStart * 1000).round(),
                ),
              );
            }
          } else if (editorState.segments.isNotEmpty) {
            // Video reached the end of its last segment
            final totalDuration = ref.read(totalEditedDurationProvider);
            final videoDuration = _videoTimelineDuration(editorState.segments);
            if (totalDuration > videoDuration) {
              // Audio extends beyond video — only pause player,
              // let the ticker keep driving audio playback
              notifier.updatePlaybackPosition(videoDuration);
              player.pause();
            } else {
              // No audio extends beyond — stop everything
              player.pause();
              notifier.setPlaying(false);
              player.seek(
                Duration(
                  milliseconds: (editorState.segments.first.sourceStart * 1000)
                      .round(),
                ),
              );
            }
          }
        }
      } else {
        VideoSegment? nextSegment;
        for (final seg in editorState.segments) {
          if (seg.sourceStart > positionSeconds) {
            nextSegment = seg;
            break;
          }
        }
        if (nextSegment != null) {
          _player!.seek(
            Duration(milliseconds: (nextSegment.sourceStart * 1000).round()),
          );
        } else if (editorState.segments.isNotEmpty) {
          final totalDuration = ref.read(totalEditedDurationProvider);
          final videoDuration = _videoTimelineDuration(editorState.segments);
          if (totalDuration > videoDuration &&
              editorState.currentPlaybackPosition >= videoDuration - 0.05) {
            notifier.updatePlaybackPosition(videoDuration);
            _player!.pause();
          } else {
            _player!.pause();
            notifier.setPlaying(false);
            _player!.seek(
              Duration(
                milliseconds: (editorState.segments.first.sourceStart * 1000)
                    .round(),
              ),
            );
          }
        }
      }
    }

    if (editorState.isPlaying) {
      return;
    }

    // Only sync video controller's play state to global state if we're not in
    // an audio-only phase (where video is paused but audio continues playing)
    if (editorState.isPlaying != _player!.state.playing) {
      if (_player!.state.playing) {
        // Video started playing — sync
        notifier.setPlaying(true);
      } else {
        // Video paused — only stop global playback if audio doesn't extend beyond video
        final totalDuration = ref.read(totalEditedDurationProvider);
        final videoDuration = _videoTimelineDuration(editorState.segments);
        final audioExtendsBeyond = totalDuration > videoDuration;
        if (!audioExtendsBeyond) {
          notifier.setPlaying(false);
        }
      }
    }
  }

  void _showPermissionDialog() {
    PermissionDialog.showGalleryAccessRequired(
      context: context,
      message:
          'SlimShotAI needs access to your gallery to select videos for editing. Please allow access in settings.',
      onCancel: () {
        if (mounted) context.pop();
      },
    );
  }

  void _setTrimRange(RangeValues value) {
    final notifier = ref.read(videoEditorProvider.notifier);
    final player = _player;
    if (player == null) return;
    notifier.setTrimRangeAndSeek(value, player);
  }

  void _splitAtPlayhead() {
    final notifier = ref.read(videoEditorProvider.notifier);
    final controller = _player;
    if (controller == null) return;
    final position = controller.state.position.inMilliseconds / 1000.0;
    try {
      notifier.splitAtPlayhead(position);
      HapticFeedback.selectionClick();
    } catch (e) {
      ToastUtils.show(context, e.toString(), isError: true);
    }
  }

  void _selectSegment(String? segmentId) {
    if (segmentId == null) {
      ref.read(videoEditorProvider.notifier).deselectAll();
    } else {
      final notifier = ref.read(videoEditorProvider.notifier);
      notifier.selectSegment(segmentId);
      notifier.setCurrentMenu('edit');
    }
  }

  void _deleteSelectedSegment() {
    ref.read(videoEditorProvider.notifier).deleteSelectedSegment();
    HapticFeedback.mediumImpact();
  }

  Future<void> _pickImageOverlay() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final editorState = ref.read(videoEditorProvider);
      final notifier = ref.read(videoEditorProvider.notifier);

      var proposedStart = Duration(
        milliseconds: (editorState.currentPlaybackPosition * 1000).toInt(),
      );
      var proposedEnd = proposedStart + const Duration(seconds: 5);
      final totalDuration = Duration(
        milliseconds: (editorState.durationSeconds * 1000).toInt(),
      );

      if (proposedEnd > totalDuration) {
        proposedEnd = totalDuration;
        if ((proposedEnd - proposedStart) < const Duration(milliseconds: 500)) {
          proposedStart = proposedEnd - const Duration(seconds: 5);
          if (proposedStart < Duration.zero) proposedStart = Duration.zero;
        }
      }

      final overlay = ImageOverlayModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        imagePath: picked.path,
        startTime: proposedStart,
        endTime: proposedEnd,
      );
      notifier.addImageOverlay(overlay);
    } catch (e) {
      if (mounted) {
        ToastUtils.show(context, 'Failed to pick image: $e', isError: true);
      }
    }
  }

  Future<void> _pickVideoOverlay() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;

      final editorState = ref.read(videoEditorProvider);
      final notifier = ref.read(videoEditorProvider.notifier);

      // We need to find the duration of the selected video
      final tempPlayer = Player();
      await tempPlayer.open(Media(picked.path), play: false);
      Duration videoDuration = tempPlayer.state.duration;
      if (videoDuration.inMilliseconds == 0) {
        videoDuration = await tempPlayer.stream.duration.firstWhere(
          (d) => d.inMilliseconds > 0,
          orElse: () => const Duration(seconds: 5),
        );
      }
      await tempPlayer.dispose();

      var proposedStart = Duration(
        milliseconds: (editorState.currentPlaybackPosition * 1000).toInt(),
      );
      var proposedEnd = proposedStart + videoDuration;
      final totalDuration = Duration(
        milliseconds: (editorState.durationSeconds * 1000).toInt(),
      );

      if (proposedEnd > totalDuration) {
        proposedEnd = totalDuration;
      }

      final overlay = VideoOverlayModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        videoPath: picked.path,
        timelineStart: proposedStart,
        timelineEnd: proposedEnd,
        sourceStart: 0.0,
        sourceEnd: videoDuration.inMilliseconds / 1000.0,
      );
      notifier.addVideoOverlay(overlay);
    } catch (e) {
      if (mounted) {
        ToastUtils.show(context, 'Failed to pick video: $e', isError: true);
      }
    }
  }

  void _showOverlaySelectionMenu(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final Offset buttonPosition = button.localToGlobal(Offset.zero);

    showDialog(
      context: buttonContext,
      barrierColor: Colors.transparent,
      builder: (context) {
        return Stack(
          children: [
            Positioned(
              left: (buttonPosition.dx - 20).clamp(
                8.0,
                MediaQuery.of(context).size.width - 170,
              ),
              bottom:
                  MediaQuery.of(context).size.height - buttonPosition.dy + 10,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 160,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16, left: 4),
                        child: Text(
                          'Add from',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.pop(context);
                          _pickVideoOverlay();
                        },
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                LucideIcons.film,
                                color: AppColors.textPrimary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Video',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.pop(context);
                          _pickImageOverlay();
                        },
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                LucideIcons.camera,
                                color: AppColors.textPrimary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Photos',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _undoLastTimelineEdit() {
    ref.read(videoEditorProvider.notifier).undo();
    HapticFeedback.selectionClick();
  }

  void _redoLastTimelineEdit() {
    ref.read(videoEditorProvider.notifier).redo();
    HapticFeedback.selectionClick();
  }

  Future<void> _exportVideo() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    final exportParams = ref.read(exportPayloadProvider);

    if (exportParams == null) {
      ToastUtils.show(
        context,
        "Cannot export video. Missing parameters.",
        isError: true,
      );
      return;
    }

    final targetHeight = _exportHeight;
    final targetFps = _exportFps;

    try {
      notifier.setExporting(true);

      void navigateToExport() {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ExportVideoScreen(
              sourceVideo: exportParams['sourceVideo'],
              segments: exportParams['segments'],
              muteAudio: exportParams['muteAudio'],
              targetAspectRatio: exportParams['targetAspectRatio'],
              customCropRect: exportParams['customCropRect'],
              originalVideoSize: exportParams['originalVideoSize'],
              previewCanvasSize: exportParams['previewCanvasSize'],
              renderId: exportParams['renderId'],
              colorFilterMatrix: exportParams['colorFilterMatrix'],
              textOverlays: exportParams['textOverlays'],
              imageOverlays: exportParams['imageOverlays'],
              videoOverlays: exportParams['videoOverlays'],
              audioTracks: exportParams['audioTracks'],
              backgroundType: exportParams['backgroundType']
                  .toString()
                  .split('.')
                  .last,
              backgroundColor: exportParams['backgroundColor'],
              backgroundBlurIntensity: exportParams['backgroundBlurIntensity'],
              targetHeight: targetHeight,
              targetFps: targetFps,
            ),
          ),
        ).then((_) {
          if (mounted) {
            notifier.setExporting(false);
          }
        });
      }

      // If they unlocked 4K, they already watched a Rewarded Ad. Skip Interstitial.
      if (targetHeight == 2160) {
        navigateToExport();
      } else {
        AdService.showInterstitialAd(context, onAdDismissed: navigateToExport);
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.show(context, e.toString(), isError: true);
        notifier.setExporting(false);
      }
    }
  }

  String _formatDuration(double seconds) {
    final duration = Duration(milliseconds: (seconds * 1000).round());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  // --- UI Builders ---

  Widget _buildTopBar() {
    final editorState = ref.watch(videoEditorProvider);
    String title = 'Video';
    final video = editorState.sourceVideo;
    if (video != null) {
      title = video.name;
      final extIndex = title.lastIndexOf('.');
      if (extIndex > 0) {
        title = title.substring(0, extIndex);
      }
      if (title.length > 9) {
        title = '${title.substring(0, 9)}...';
      }
    }

    final totalEditedDuration = ref.watch(totalEditedDurationProvider);
    return VideoEditorTopBar(
      title: title,
      durationLabel: _formatDuration(totalEditedDuration),
      isExporting: editorState.isExporting,
      hasSourceVideo: video != null,
      onExport: _exportVideo,
      currentResolutionLabel: _resolutionLabel,
      onResolutionTap: _showExportOptionsPopup,
      resolutionButtonKey: _resolutionButtonKey,
      onBack: () async {
        await ref.read(videoEditorProvider.notifier).saveDraft();
        if (context.mounted) {
          context.pop();
        }
      },
    ).animate().fadeIn().slideX(begin: 0.2);
  }

  void _showExportOptionsPopup() {
    final RenderBox renderBox =
        _resolutionButtonKey.currentContext!.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) {
        return Stack(
          children: [
            Positioned(
              top: position.dy + size.height + 8,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: StatefulBuilder(
                  builder: (context, setPopupState) {
                    Widget buildToggles(
                      List<int> values,
                      int currentValue,
                      String Function(int) labelBuilder,
                      void Function(int) onChanged, {
                      bool Function(int)? isProBuilder,
                    }) {
                      return Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: values.map((val) {
                            final isSelected = val == currentValue;
                            return Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  if (isProBuilder != null &&
                                      isProBuilder(val) &&
                                      !isSelected) {
                                    AdService.showRewardedAd(
                                      context,
                                      onRewardEarned: () {
                                        if (context.mounted) {
                                          onChanged(val);
                                          setPopupState(() {});
                                          setState(() {});
                                          ToastUtils.show(
                                            context,
                                            '${labelBuilder(val)} Unlocked!',
                                            isError: false,
                                          );
                                        }
                                      },
                                      onFailed: () {
                                        if (context.mounted) {
                                          ToastUtils.show(
                                            context,
                                            'Please check your internet connection to unlock Pro features.',
                                            isWarning: true,
                                            title: 'No Internet Connection',
                                          );
                                        }
                                      },
                                    );
                                  } else {
                                    onChanged(val);
                                    setPopupState(() {});
                                    setState(() {});
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primaryStart
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        labelBuilder(val),
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (isProBuilder != null &&
                                          isProBuilder(val)) ...[
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF8B5CF6),
                                                Color(0xFFD946EF),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'PRO',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              SizedBox(width: 2),
                                              Icon(
                                                LucideIcons.play,
                                                color: Colors.white,
                                                size: 8,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }

                    return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                width: 250,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.surface.withValues(
                                    alpha: 0.85,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppColors.border.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Resolution (limited to HD)',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    buildToggles(
                                      [720, 1080, 2160],
                                      _exportHeight,
                                      (val) => val == 720
                                          ? 'SD'
                                          : val == 1080
                                          ? 'HD'
                                          : '4K',
                                      (val) => _exportHeight = val,
                                      isProBuilder: (val) => val == 2160,
                                    ),
                                    const SizedBox(height: 20),
                                    const Text(
                                      'Frame rate (limited to 30)',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    buildToggles(
                                      [24, 30, 60],
                                      _exportFps,
                                      (val) => val.toString(),
                                      (val) => _exportFps = val,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 200.ms)
                        .scale(
                          begin: const Offset(0.95, 0.95),
                          curve: Curves.easeOutBack,
                        );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- Playback Controls ---
  Widget _buildPlaybackControls() {
    final editorState = ref.watch(videoEditorProvider);
    final totalEditedDuration = ref.watch(totalEditedDurationProvider);
    final timelinePosition = editorState.currentPlaybackPosition
        .clamp(0.0, totalEditedDuration)
        .toDouble();
    return EditorPlaybackControls(
      isPlaying: editorState.isPlaying,
      timelineLabel:
          '${_formatDuration(timelinePosition)} / ${_formatDuration(totalEditedDuration)}',
      canUndo: editorState.canUndo,
      canRedo: editorState.canRedo,
      onTogglePreview: _togglePreview,
      onUndo: _undoLastTimelineEdit,
      onRedo: _redoLastTimelineEdit,
      onExpandPreview: () => _openFullscreenPreview(),
    );
  }

  void _openFullscreenPreview() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  // --- Toolbar Panels ---

  Widget _buildAudioContextMenu() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    final tools = [
      const EditorTool(id: 'split', label: 'Split', icon: LucideIcons.scissors),
      const EditorTool(
        id: 'volume',
        label: 'Volume',
        icon: LucideIcons.volume2,
      ),
      const EditorTool(id: 'delete', label: 'Delete', icon: LucideIcons.trash2),
      const EditorTool(
        id: 'duplicate',
        label: 'Duplicate',
        icon: LucideIcons.copy,
      ),
    ];

    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: tools.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                notifier.selectAudioTrack(null);
              },
              child: Container(
                width: 56,
                margin: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Colors.white24, width: 1),
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.chevronLeft,
                      color: Colors.white70,
                      size: 20,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Back',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final tool = tools[index - 1];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              if (tool.id == 'split') {
                try {
                  notifier.splitAudioTrack(editorState.currentPlaybackPosition);
                  HapticFeedback.selectionClick();
                } catch (e) {
                  ToastUtils.show(context, e.toString(), isError: true);
                }
              } else if (tool.id == 'volume') {
                notifier.setActiveTool('volume');
              } else if (tool.id == 'delete') {
                if (editorState.selectedAudioId != null) {
                  notifier.deleteAudioTrack(editorState.selectedAudioId!);
                  notifier.selectAudioTrack(null);
                }
              } else if (tool.id == 'duplicate') {
                if (editorState.selectedAudioId != null) {
                  final audioTrack = editorState.audioTracks.firstWhere(
                    (a) => a.id == editorState.selectedAudioId,
                  );
                  final duplicate = audioTrack.copyWith(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    timelineStart: audioTrack.timelineEnd,
                  );
                  notifier.addAudioTrack(duplicate);
                  notifier.selectAudioTrack(duplicate.id);
                }
              }
            },
            child: Container(
              width: 56,
              margin: const EdgeInsets.only(right: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(tool.icon, color: Colors.white, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    tool.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHomeToolbar() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final menu = _menus[editorState.currentMenuId] ?? _menus['root']!;

    final canDelete = ref.watch(canDeleteSegmentProvider);
    final isSplitEnabled = ref.watch(isSplitToolEnabledProvider);
    final visibleTools = menu.tools.where((tool) {
      if (tool.id == 'delete') {
        if (editorState.selectedTextId != null ||
            editorState.selectedImageId != null ||
            editorState.selectedVideoOverlayId != null) {
          return true;
        }
        return canDelete;
      }
      if (tool.id == 'split') {
        return isSplitEnabled;
      }
      if (tool.id == 'volume' || tool.id == 'speed') {
        if (editorState.segments.length > 1 && !editorState.isClipSelected) {
          return false;
        }
        return true;
      }
      if (tool.id == 'animation') {
        if (editorState.selectedVideoOverlayId != null) {
          return false;
        }
        return true;
      }
      return true;
    }).toList();

    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: editorState.currentMenuId == 'root'
            ? visibleTools.length
            : visibleTools.length + 1,
        itemBuilder: (context, index) {
          if (editorState.currentMenuId != 'root' && index == 0) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                notifier.setCurrentMenu('root');
                notifier.deselectAll();
              },
              child: Container(
                width: 56,
                margin: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Colors.white24, width: 1),
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.chevronLeft,
                      color: Colors.white70,
                      size: 20,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Back',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final toolIndex = editorState.currentMenuId == 'root'
              ? index
              : index - 1;
          final tool = visibleTools[toolIndex];

          return Builder(
            builder: (buttonContext) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (tool.id == 'audio') {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const AudioDrawer(),
                    );
                  } else if (tool.id == 'filters') {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const FiltersDrawer(),
                    );
                  } else if (tool.id == 'stickers') {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const StickersDrawer(),
                    );
                  } else if (tool.id == 'text' &&
                      editorState.currentMenuId == 'root') {
                    // From root menu, directly add a new text overlay
                    var proposedStartTime = Duration(
                      milliseconds: (editorState.currentPlaybackPosition * 1000)
                          .toInt(),
                    );
                    var proposedEndTime =
                        proposedStartTime + const Duration(seconds: 3);
                    final totalDuration = Duration(
                      milliseconds: (editorState.durationSeconds * 1000)
                          .toInt(),
                    );

                    if (proposedEndTime > totalDuration) {
                      proposedEndTime = totalDuration;
                      if ((proposedEndTime - proposedStartTime) <
                          const Duration(milliseconds: 500)) {
                        proposedStartTime =
                            proposedEndTime - const Duration(seconds: 3);
                        if (proposedStartTime < Duration.zero)
                          proposedStartTime = Duration.zero;
                      }
                    }

                    final canvasSize = ref.read(videoCanvasSizeProvider);
                    final newOverlay = TextOverlayModel(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      text: 'Double Tap to Edit',
                      startTime: proposedStartTime,
                      endTime: proposedEndTime,
                      referenceCanvasSize: canvasSize,
                    );
                    notifier.addTextOverlay(newOverlay);
                    notifier.selectTextOverlay(newOverlay.id);
                    showTextEditor(
                      context: context,
                      overlay: newOverlay,
                      ref: ref,
                    );
                  } else if (tool.hasSubMenu) {
                    notifier.setCurrentMenu(tool.id);
                    if (tool.id == 'edit' &&
                        editorState.selectedSegmentId == null &&
                        editorState.segments.isNotEmpty) {
                      notifier.selectSegment(editorState.segments.first.id);
                    }
                  } else if (tool.id == 'split') {
                    if (editorState.selectedVideoOverlayId != null) {
                      try {
                        notifier.splitVideoOverlay(
                          editorState.currentPlaybackPosition,
                        );
                      } catch (e) {
                        ToastUtils.show(context, e.toString(), isError: true);
                      }
                    } else {
                      _splitAtPlayhead();
                    }
                  } else if (tool.id == 'delete') {
                    if (editorState.selectedTextId != null) {
                      notifier.deleteTextOverlay(editorState.selectedTextId!);
                      notifier.selectTextOverlay(null);
                    } else if (editorState.selectedImageId != null) {
                      notifier.deleteImageOverlay(editorState.selectedImageId!);
                      notifier.selectImageOverlay(null);
                    } else if (editorState.selectedVideoOverlayId != null) {
                      notifier.deleteVideoOverlay(
                        editorState.selectedVideoOverlayId!,
                      );
                      notifier.selectVideoOverlay(null);
                    } else {
                      _deleteSelectedSegment();
                    }
                  } else if (tool.id == 'transition') {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const TransitionsDrawer(),
                    );
                  } else if (tool.id == 'reverse') {
                    if (editorState.selectedSegmentId != null) {
                      notifier.toggleReverse(editorState.selectedSegmentId!);
                      ToastUtils.show(context, 'Reversed clip', isError: false);
                    } else {
                      ToastUtils.show(
                        context,
                        'Please select a clip to reverse',
                        isError: true,
                      );
                    }
                  } else if (tool.id == 'opacity') {
                    notifier.setActiveTool('opacity');
                  } else if (tool.id == 'animation') {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const AnimationDrawer(),
                    );
                  } else if (tool.id == 'duplicate') {
                    if (editorState.selectedTextId != null) {
                      notifier.duplicateTextOverlay(
                        editorState.selectedTextId!,
                      );
                    } else if (editorState.selectedImageId != null) {
                      notifier.duplicateImageOverlay(
                        editorState.selectedImageId!,
                      );
                    } else if (editorState.selectedVideoOverlayId != null) {
                      notifier.duplicateVideoOverlay(
                        editorState.selectedVideoOverlayId!,
                      );
                    }
                  } else if (tool.id == 'add_text') {
                    var proposedStartTime = Duration(
                      milliseconds: (editorState.currentPlaybackPosition * 1000)
                          .toInt(),
                    );
                    var proposedEndTime =
                        proposedStartTime + const Duration(seconds: 3);
                    final totalDuration = Duration(
                      milliseconds: (editorState.durationSeconds * 1000)
                          .toInt(),
                    );

                    if (proposedEndTime > totalDuration) {
                      proposedEndTime = totalDuration;
                      if ((proposedEndTime - proposedStartTime) <
                          const Duration(milliseconds: 500)) {
                        proposedStartTime =
                            proposedEndTime - const Duration(seconds: 3);
                        if (proposedStartTime < Duration.zero)
                          proposedStartTime = Duration.zero;
                      }
                    }

                    final canvasSize = ref.read(videoCanvasSizeProvider);
                    final newOverlay = TextOverlayModel(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      text: 'Double Tap to Edit',
                      startTime: proposedStartTime,
                      endTime: proposedEndTime,
                      referenceCanvasSize: canvasSize,
                    );
                    notifier.addTextOverlay(newOverlay);
                    showTextEditor(
                      context: buttonContext,
                      overlay: newOverlay,
                      ref: ref,
                    );
                  } else if (tool.id == 'overlay') {
                    _showOverlaySelectionMenu(buttonContext);
                  } else {
                    notifier.setActiveTool(tool.id);
                    if (tool.id == 'zoom') {
                      notifier.setPreviewVideoTransform(
                        previewVideoScale: editorState.videoScale,
                        previewVideoPan: editorState.videoPan,
                      );
                    }
                  }
                },
                child: Container(
                  width: 56,
                  margin: const EdgeInsets.only(right: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(tool.icon, color: Colors.white, size: 24),
                      const SizedBox(height: 4),
                      Text(
                        tool.label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildActiveToolPanel() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final activeToolId = editorState.activeToolId;
    if (activeToolId == null) {
      return const SizedBox.shrink();
    }

    Widget content;
    switch (activeToolId) {
      case 'edit':
        content = _buildTrimPanel();
        break;
      case 'audio':
        content = _buildAudioPanel();
        break;
      case 'volume':
        content = _buildVolumePanel();
        break;
      case 'speed':
        content = _buildSpeedPanel();
        break;
      case 'crop':
        content = _buildCropPanel();
        break;
      case 'zoom':
        content = _buildZoomPanel();
        break;
      case 'style':
        content = _buildTextStylePanel();
        break;
      case 'font':
        content = _buildTextFontPanel();
        break;
      case 'animation':
        content = _buildTextAnimationPanel();
        break;
      case 'templates':
        content = const Center(
          child: Text(
            'Templates coming soon!',
            style: TextStyle(color: Colors.white54),
          ),
        );
        break;
      case 'background':
        content = BackgroundPanel(onClose: notifier.closeActiveTool);
        break;
      case 'opacity':
        content = _buildOpacityPanel();
        break;
      default:
        content = _buildPlaceholderPanel(_getToolLabel(activeToolId));
        break;
    }

    double panelHeight = 160;
    if (['style', 'font', 'animation'].contains(activeToolId)) {
      panelHeight = 260;
    } else if (activeToolId == 'background') {
      panelHeight = 200;
    }

    return Container(
      key: ValueKey(activeToolId),
      height: panelHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  final activeSegment = notifier.getActiveSegment();
                  if (activeToolId == 'volume' &&
                      editorState.previewVolume != null &&
                      editorState.selectedAudioId == null &&
                      activeSegment != null) {
                    _player?.setVolume(
                      (activeSegment.volume * activeSegment.volume * 100.0),
                    );
                  }
                  if (activeToolId == 'speed' &&
                      editorState.previewSpeed != null &&
                      activeSegment != null) {
                    _player?.setRate(activeSegment.speed);
                  }
                  notifier.closeActiveTool();
                },
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    LucideIcons.x,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
              Text(
                _getToolLabel(activeToolId),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();

                  if (activeToolId == 'volume' &&
                      editorState.previewVolume != null) {
                    if (editorState.selectedAudioId != null) {
                      final track = editorState.audioTracks.firstWhere(
                        (a) => a.id == editorState.selectedAudioId!,
                      );
                      notifier.updateAudioTrack(
                        track.copyWith(volume: editorState.previewVolume!),
                      );
                      notifier.setPreviewVolume(
                        null,
                      ); // just clears the preview state
                    } else if (editorState.selectedVideoOverlayId != null) {
                      notifier.setPreviewVolume(
                        null,
                      ); // already updated in the panel
                    } else {
                      notifier.commitPreviewVolume();
                    }
                  }

                  if (activeToolId == 'speed' &&
                      editorState.previewSpeed != null) {
                    notifier.commitPreviewSpeed();
                  }
                  if (activeToolId == 'zoom' &&
                      editorState.previewVideoScale != null) {
                    notifier.commitPreviewVideoTransform();
                  }
                  notifier.closeActiveTool();
                },
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    LucideIcons.check,
                    color: AppColors.primaryStart,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildTrimPanel() {
    final editorState = ref.watch(videoEditorProvider);
    final trimDuration =
        (editorState.trimRange.end - editorState.trimRange.start)
            .clamp(0.0, editorState.durationSeconds)
            .toDouble();

    return TrimPanel(
      trimLabel: _formatDuration(trimDuration),
      segmentCount: editorState.segments.length,
      onSplit: _splitAtPlayhead,
    );
  }

  Widget _buildSplitMarkersSummary() {
    final editorState = ref.watch(videoEditorProvider);
    if (editorState.segments.length <= 1) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        'Clips: ${editorState.segments.length}',
        style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildAudioPanel() {
    final editorState = ref.watch(videoEditorProvider);
    return AudioPanel(
      isMuted: editorState.isMuted,
      onChanged: (value) {
        HapticFeedback.selectionClick();
        ref.read(videoEditorProvider.notifier).setMuted(value);
      },
    );
  }

  Widget _buildVolumePanel() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    if (editorState.selectedAudioId != null) {
      final audioTrack = editorState.audioTracks.firstWhere(
        (a) => a.id == editorState.selectedAudioId,
      );
      return VolumePanel(
        displayVolume: editorState.previewVolume ?? audioTrack.volume,
        emptyMessage: null,
        onChanged: (value) {
          notifier.setPreviewVolume(value);
          _audioPlayerManager.setVolumeSync(audioTrack.id, value);
        },
      );
    }

    if (editorState.selectedVideoOverlayId != null) {
      final videoOverlay = editorState.videoOverlays.firstWhere(
        (v) => v.id == editorState.selectedVideoOverlayId,
      );
      return VolumePanel(
        displayVolume: editorState.previewVolume ?? videoOverlay.volume,
        emptyMessage: null,
        onChanged: (value) {
          // Immediately update actual model so video playback engine reacts
          notifier.setPreviewVolume(value);
          notifier.updateVideoOverlay(
            videoOverlay.id,
            (v) => v.copyWith(volume: value),
          );
        },
      );
    }

    final activeSegment = ref.watch(activeSegmentProvider);
    return VolumePanel(
      displayVolume: editorState.previewVolume ?? activeSegment?.volume ?? 0,
      emptyMessage: activeSegment == null
          ? 'Select a clip to adjust volume'
          : null,
      onChanged: (value) {
        notifier.setPreviewVolume(value);
        _player?.setVolume(value * value * 100.0);
      },
    );
  }

  Widget _buildSpeedPanel() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final activeSegment = ref.watch(activeSegmentProvider);

    return SpeedPanel(
      displaySpeed: editorState.previewSpeed ?? activeSegment?.speed ?? 1.0,
      emptyMessage: activeSegment == null
          ? 'Select a clip to adjust speed'
          : null,
      onChanged: (value) {
        notifier.setPreviewSpeed(value);
        _player?.setRate(value);
      },
    );
  }

  Widget _buildOpacityPanel() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    double currentOpacity = 1.0;
    if (editorState.selectedImageId != null) {
      currentOpacity = editorState.imageOverlays
          .firstWhere((i) => i.id == editorState.selectedImageId)
          .opacity;
    } else if (editorState.selectedVideoOverlayId != null) {
      currentOpacity = editorState.videoOverlays
          .firstWhere((v) => v.id == editorState.selectedVideoOverlayId)
          .opacity;
    }

    return OpacityPanel(
      opacity: currentOpacity,
      onChanged: (value) {
        notifier.setOverlayOpacity(value);
      },
    );
  }

  Widget _buildCropPanel() {
    final editorState = ref.watch(videoEditorProvider);
    return CropPanel(
      selectedRatio: editorState.selectedRatio,
      onRatioSelected: (ratio) {
        HapticFeedback.selectionClick();
        ref.read(videoEditorProvider.notifier).setSelectedRatio(ratio);
      },
    );
  }

  Widget _buildZoomPanel() {
    final editorState = ref.watch(videoEditorProvider);
    final currentScale =
        editorState.previewVideoScale ?? editorState.videoScale;

    return ZoomPanel(
      currentScale: currentScale,
      onChanged: (value) {
        ref
            .read(videoEditorProvider.notifier)
            .setPreviewVideoTransform(
              previewVideoScale: value,
              previewVideoPan:
                  editorState.previewVideoPan ?? editorState.videoPan,
            );
      },
      onReset: () {
        HapticFeedback.selectionClick();
        ref
            .read(videoEditorProvider.notifier)
            .setPreviewVideoTransform(
              previewVideoScale: 1.0,
              previewVideoPan: Offset.zero,
            );
      },
    );
  }

  Widget _buildTextStylePanel() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final textModel = editorState.selectedTextId != null
        ? editorState.textOverlays.firstWhere(
            (t) => t.id == editorState.selectedTextId,
            orElse: () => editorState.textOverlays.first,
          )
        : null;

    return TextStylePanel(
      textModel: textModel,
      onColorChanged: (val) => textModel != null
          ? notifier.updateTextOverlay(
              textModel.id,
              (c) => c.copyWith(color: val),
            )
          : null,
      onBackgroundColorChanged: (val) => textModel != null
          ? notifier.updateTextOverlay(
              textModel.id,
              (c) => c.copyWith(backgroundColor: val),
            )
          : null,
      onStrokeColorChanged: (val) => textModel != null
          ? notifier.updateTextOverlay(
              textModel.id,
              (c) => c.copyWith(strokeColor: val),
            )
          : null,
      onStrokeWidthChanged: (val) => textModel != null
          ? notifier.updateTextOverlay(
              textModel.id,
              (c) => c.copyWith(strokeWidth: val),
            )
          : null,
      onShadowColorChanged: (val) => textModel != null
          ? notifier.updateTextOverlay(
              textModel.id,
              (c) => c.copyWith(shadowColor: val),
            )
          : null,
      onShadowBlurChanged: (val) => textModel != null
          ? notifier.updateTextOverlay(
              textModel.id,
              (c) => c.copyWith(shadowBlurRadius: val),
            )
          : null,
    );
  }

  Widget _buildTextFontPanel() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final textModel = editorState.selectedTextId != null
        ? editorState.textOverlays.firstWhere(
            (t) => t.id == editorState.selectedTextId,
            orElse: () => editorState.textOverlays.first,
          )
        : null;

    return TextFontPanel(
      textModel: textModel,
      onFontChanged: (val) => textModel != null
          ? notifier.updateTextOverlay(
              textModel.id,
              (c) => c.copyWith(fontFamily: val),
            )
          : null,
    );
  }

  Widget _buildTextAnimationPanel() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final textModel = editorState.selectedTextId != null
        ? editorState.textOverlays.firstWhere(
            (t) => t.id == editorState.selectedTextId,
            orElse: () => editorState.textOverlays.first,
          )
        : null;

    return TextAnimationPanel(
      textModel: textModel,
      onInAnimationChanged: (val) => textModel != null
          ? notifier.updateTextOverlay(
              textModel.id,
              (c) => c.copyWith(inAnimation: val),
            )
          : null,
      onOutAnimationChanged: (val) => textModel != null
          ? notifier.updateTextOverlay(
              textModel.id,
              (c) => c.copyWith(outAnimation: val),
            )
          : null,
    );
  }

  Widget _buildPlaceholderPanel(String toolName) {
    return PlaceholderPanel(toolName: toolName);
  }

  Widget _buildScrollableTimeline() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final sourceVideo = editorState.sourceVideo;
    if (sourceVideo == null || _player == null) {
      return const SizedBox(height: 120);
    }

    List<VideoSegment> displaySegments = editorState.segments;
    if (editorState.activeToolId == 'speed' &&
        editorState.previewSpeed != null) {
      final activeId =
          editorState.isClipSelected && editorState.selectedSegmentId != null
          ? editorState.selectedSegmentId
          : editorState.segments.first.id;

      displaySegments = editorState.segments.map((segment) {
        if (segment.id == activeId) {
          return segment.copyWith(speed: editorState.previewSpeed!);
        }
        return segment;
      }).toList();
    }

    return ScrollableTimeline(
      player: _player!,
      inputPath: sourceVideo.path,
      durationSeconds: editorState.durationSeconds,
      timelinePositionSeconds: editorState.currentPlaybackPosition,
      trimRange: editorState.trimRange,
      segments: displaySegments,
      selectedSegmentId: editorState.selectedSegmentId,
      onSegmentTapped: _selectSegment,
      onTrimChanged: editorState.isExporting ? null : _setTrimRange,
      textOverlays: editorState.textOverlays,
      selectedTextId: editorState.selectedTextId,
      onTextTapped: (id) {
        notifier.selectTextOverlay(id);
      },
      onTextDoubleTapped: (id) {
        notifier.selectTextOverlay(id);
        if (id != null) {
          final overlay = editorState.textOverlays.firstWhere(
            (text) => text.id == id,
          );
          showTextEditor(
            context: context,
            overlay: overlay,
            ref: ref,
            initialTool: TextEditorTool.keyboard,
          );
        }
      },
      onTextTrimChanged: (id, start, end, {newLaneIndex}) {
        notifier.updateTextOverlay(
          id,
          (current) => current.copyWith(startTime: start, endTime: end),
          newLaneIndex: newLaneIndex,
        );
      },
      imageOverlays: editorState.imageOverlays,
      selectedImageId: editorState.selectedImageId,
      onImageTapped: notifier.selectImageOverlay,
      onImageTrimChanged: (id, start, end, {newLaneIndex}) {
        notifier.updateImageOverlay(
          id,
          (current) => current.copyWith(startTime: start, endTime: end),
          newLaneIndex: newLaneIndex,
        );
      },
      videoOverlays: editorState.videoOverlays,
      selectedVideoId: editorState.selectedVideoOverlayId,
      onVideoTapped: notifier.selectVideoOverlay,
      onVideoTrimChanged: (id, start, end, {newLaneIndex}) {
        notifier.updateVideoOverlay(
          id,
          (current) => current.copyWith(timelineStart: start, timelineEnd: end),
          newLaneIndex: newLaneIndex,
        );
      },
      audioTracks: editorState.audioTracks,
      selectedAudioId: editorState.selectedAudioId,
      onAudioTapped: (id) => notifier.selectAudioTrack(id),
      onAudioDragChanged: (id, newStart, {newLaneIndex}) {
        final track = editorState.audioTracks.firstWhere((a) => a.id == id);
        notifier.updateAudioTrack(
          track.copyWith(timelineStart: newStart),
          newLaneIndex: newLaneIndex,
        );
      },
      onAudioTrimChanged: (id, newTimelineStart, newSourceStart, newSourceEnd) {
        final track = editorState.audioTracks.firstWhere((a) => a.id == id);
        notifier.updateAudioTrack(
          track.copyWith(
            timelineStart: newTimelineStart,
            sourceStart: newSourceStart,
            sourceEnd: newSourceEnd,
          ),
        );
      },
      onTimelinePositionChanged: notifier.updatePlaybackPosition,
      onDragEnd: notifier.saveStateForUndo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);

    // Listen to play/pause state to start/stop Ticker and manage play/pause of the global clock
    ref.listen<bool>(videoEditorProvider.select((s) => s.isPlaying), (
      prev,
      isPlaying,
    ) {
      if (isPlaying) {
        _lastTick = DateTime.now();
        // Ensure audio players are loaded before playing
        final state = ref.read(videoEditorProvider);
        _audioPlayerManager.syncTracks(state.audioTracks);
        _syncVideoLayerToTimeline(
          state.currentPlaybackPosition,
          state,
          shouldPlay: true,
          seekThresholdSeconds: 0.5,
        );
        _ticker.start();
      } else {
        _ticker.stop();
        _player?.pause();
        _audioPlayerManager.pauseAll();
      }
    });

    // Sync audio player instances whenever the track list changes (import, delete, etc.)
    ref.listen<List<AudioTrackModel>>(
      videoEditorProvider.select((s) => s.audioTracks),
      (prev, tracks) {
        _audioPlayerManager.syncTracks(tracks);
      },
    );

    // Sync audio players when scrubbing the timeline (while paused)
    ref.listen<double>(
      videoEditorProvider.select((s) => s.currentPlaybackPosition),
      (prev, currentPos) {
        final state = ref.read(videoEditorProvider);
        if (!state.isPlaying) {
          _audioPlayerManager.seekAndPlaySync(
            currentPos,
            state.audioTracks,
            false,
          );
        }
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await ref.read(videoEditorProvider.notifier).saveDraft();
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background, // match dark theme
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 0. Top Bar
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: Offstage(offstage: _isFullscreen, child: _buildTopBar()),
              ),

              // 2. Video Area (Expanded)
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _videoController != null
                          ? VideoPreviewCanvas(
                              videoController: _videoController!,
                              onTogglePreview: () => ref
                                  .read(videoEditorProvider.notifier)
                                  .togglePreview(),
                              onDeadZoneTapped: () {
                                final notifier = ref.read(
                                  videoEditorProvider.notifier,
                                );
                                notifier.selectTextOverlay(null);
                                notifier.selectImageOverlay(null);
                              },
                              onShowTextEditor:
                                  (
                                    TextOverlayModel overlay,
                                    bool showKeyboard,
                                  ) => showTextEditor(
                                    context: context,
                                    overlay: overlay,
                                    ref: ref,
                                    initialTool: showKeyboard
                                        ? TextEditorTool.keyboard
                                        : TextEditorTool.color,
                                  ),
                              onCanvasSizeChanged: (size) {
                                ref
                                        .read(videoCanvasSizeProvider.notifier)
                                        .state =
                                    size;
                              },
                            )
                          : Container(
                              color: Colors.black,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white38,
                                ),
                              ),
                            ),
                    ),
                    if (_isFullscreen)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: GestureDetector(
                          onTap: _openFullscreenPreview,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              LucideIcons.minimize,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 2. Playback Controls Row
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: Offstage(
                  offstage: _isFullscreen,
                  child: _buildPlaybackControls(),
                ),
              ),

              // 3 & 4. Scrollable Timeline Area and Bottom Toolbar
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Offstage(
                  offstage: _isFullscreen,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Offstage(
                        offstage: [
                          'style',
                          'font',
                          'animation',
                        ].contains(editorState.activeToolId),
                        child: _buildScrollableTimeline(),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.background, // match dark theme
                          borderRadius: editorState.activeToolId != null
                              ? const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                )
                              : null,
                          border: editorState.activeToolId != null
                              ? const Border(
                                  top: BorderSide(
                                    color: Colors.white12,
                                    width: 1.0,
                                  ),
                                  left: BorderSide(
                                    color: Colors.white12,
                                    width: 1.0,
                                  ),
                                  right: BorderSide(
                                    color: Colors.white12,
                                    width: 1.0,
                                  ),
                                )
                              : const Border(
                                  top: BorderSide(
                                    color: Colors.white12,
                                    width: 1.0,
                                  ),
                                ),
                        ),
                        child: ClipRRect(
                          borderRadius: editorState.activeToolId != null
                              ? const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                )
                              : BorderRadius.zero,
                          child: SafeArea(
                            top: false,
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.bottomCenter,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                reverseDuration: const Duration(
                                  milliseconds: 250,
                                ),
                                layoutBuilder:
                                    (currentChild, previousChildren) {
                                      return Stack(
                                        alignment: Alignment.bottomCenter,
                                        children: <Widget>[
                                          ...previousChildren,
                                          if (currentChild != null)
                                            currentChild,
                                        ],
                                      );
                                    },
                                transitionBuilder: (child, animation) {
                                  return SlideTransition(
                                    position:
                                        Tween<Offset>(
                                          begin: const Offset(0, 0.4),
                                          end: Offset.zero,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          ),
                                        ),
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  );
                                },
                                child: editorState.activeToolId == null
                                    ? (editorState.selectedAudioId != null
                                          ? _buildAudioContextMenu()
                                          : _buildHomeToolbar())
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _buildActiveToolPanel(),
                                          if (editorState.activeToolId ==
                                              'edit')
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    20,
                                                    0,
                                                    20,
                                                    10,
                                                  ),
                                              child:
                                                  _buildSplitMarkersSummary(),
                                            ),
                                        ],
                                      ),
                              ),
                            ),
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
}
