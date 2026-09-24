import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/lucide_icons.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/permission_dialog.dart';
import '../core/services/ad_service.dart';
import 'export_video_screen.dart';
import '../features/video_editor/widgets/panels/transitions_drawer.dart';
import '../features/video_editor/models/text_overlay_model.dart';
import '../features/video_editor/models/image_overlay_model.dart';
import '../features/video_editor/models/video_segment.dart';
import '../features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import '../features/video_editor/logic/text_overlay_geometry.dart';
import '../features/video_editor/logic/text_template_catalog.dart';
import '../features/video_editor/widgets/panels/text_templates_sheet.dart';
import '../features/video_editor/logic/tool_dismissal.dart';
import '../features/video_editor/logic/toolbar_visibility.dart';
import '../features/video_editor/logic/timeline/timeline_geometry.dart';
import '../features/video_editor/providers/video_editor_notifier.dart';
import '../features/video_editor/services/media_import_service.dart';
import '../features/video_editor/services/native_timeline_preview_service.dart';
import '../core/models/draft_project.dart';
import '../features/video_editor/logic/animation/clip_keyframes.dart';
import '../features/video_editor/widgets/editor_playback_controls.dart';
import '../features/video_editor/widgets/panels/keyframe_easing_sheet.dart';
import '../features/video_editor/widgets/panels/transform_sheet.dart';
import '../features/video_editor/widgets/timeline/scrollable_timeline.dart';
import 'package:flutter/scheduler.dart';
import '../features/video_editor/widgets/video_editor_top_bar.dart';
import '../features/video_editor/widgets/panels/audio_drawer.dart';
import '../features/video_editor/widgets/panels/effects_panel.dart';
import '../features/video_editor/widgets/panels/filters_drawer.dart';
import '../features/video_editor/widgets/panels/stickers_drawer.dart';
import '../features/video_editor/services/audio_player_manager.dart';
import '../features/video_editor/models/audio_track_model.dart';
import '../features/video_editor/widgets/text_overlay/text_editor_dialog.dart';
import '../features/video_editor/widgets/canvas/native_timeline_preview_view.dart';
import '../features/video_editor/widgets/canvas/video_preview_canvas.dart';
import '../features/video_editor/widgets/panels/audio_panel.dart';
import '../features/video_editor/widgets/panels/crop_panel.dart';
import '../features/video_editor/widgets/panels/placeholder_panel.dart';
import '../features/video_editor/widgets/panels/speed_panel.dart';
import '../features/video_editor/widgets/panels/trim_panel.dart';
import '../features/video_editor/widgets/panels/volume_panel.dart';
import '../features/video_editor/widgets/panels/zoom_panel.dart';
import '../features/video_editor/widgets/panels/opacity_panel.dart';
import '../features/video_editor/widgets/panels/animation_drawer.dart';
import '../features/video_editor/widgets/panels/editor_panel_switcher.dart';
import '../features/video_editor/widgets/panels/background_sheet.dart';
import '../features/video_editor/widgets/panels/editor_sheet.dart';
import '../features/video_editor/widgets/editor_tool_tile.dart';
import '../features/video_editor/widgets/panels/adjust_sheet.dart';
import '../features/video_editor/widgets/panels/chroma_key_sheet.dart';
import '../features/video_editor/widgets/panels/speed_curve_sheet.dart';
import '../features/video_editor/widgets/panels/apply_to_all_button.dart';
import '../features/video_editor/widgets/panels/mask_panel.dart';

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
    // Appends more photos or videos to the project already open.
    EditorTool(id: 'add', label: 'Add', icon: LucideIcons.plusCircle),
    EditorTool(
      id: 'audio',
      label: 'Audio',
      icon: LucideIcons.music,
      hasSubMenu: true,
    ),
    // A submenu now that it has a second real entry — Add text and
    // Templates. It went straight to typing while Add text was all there was,
    // because a one-item submenu is a tap tax on the most common action.
    EditorTool(
      id: 'text',
      label: 'Text',
      icon: LucideIcons.type,
      hasSubMenu: true,
    ),
    EditorTool(id: 'overlay', label: 'Overlay', icon: LucideIcons.layers),
    // **Transform's children are root tools now, and Transform is a tool of its
    // own.** The submenu was a tap tax on four things a user reaches for
    // directly — Crop especially, which is one of the most common edits and was
    // two taps deep. Transform keeps the name because it is still what it does:
    // scale, rotate and position the clip on the canvas, in one sheet.
    EditorTool(id: 'crop', label: 'Crop', icon: LucideIcons.crop),
    EditorTool(
      id: 'transform',
      label: 'Transform',
      icon: LucideIcons.move,
    ),
    EditorTool(id: 'zoom', label: 'Zoom', icon: LucideIcons.zoomIn),
    EditorTool(id: 'background', label: 'Background', icon: LucideIcons.image),
    EditorTool(id: 'filters', label: 'Filters', icon: LucideIcons.sliders),
    // Brightness, contrast, saturation and temperature — the corrections a
    // filter preset is not. Project-level from here; per clip from the clip
    // menu, the same way Filters works.
    EditorTool(id: 'adjust', label: 'Adjust', icon: LucideIcons.slidersHorizontal),
    // **No Animate here.** An animation belongs to the thing being animated:
    // `animation` opens `AnimationDrawer` from the image- and video-overlay
    // menus, and text has the Animation tab in its editor sheet. The root
    // menu has nothing selected, so there was no target — and the id
    // `animate` was handled by nothing at all, falling through to a "coming
    // soon" placeholder for a feature that ships one tap away. Same wrong
    // signpost as Effects below, same removal.
    // **No Effects here.** An effect belongs to a clip, so the real sheet is
    // gated on the clip menu — and this entry fell through to a "coming soon"
    // placeholder for a feature that ships one tap away, on the clip's own
    // menu. A wrong signpost rather than an unfinished tool, which is why it
    // goes where the audio menu's genuinely-unbuilt entry stays.
    // **Labelled for what it opens.** The picker offers emoji; GIFs and
    // stickers need a content provider that does not exist yet, and a tool
    // saying "Stickers" that shows emoji is the same wrong signpost the root
    // menu's Effects entry was. The id stays `stickers` because it is
    // persisted and matched elsewhere — only the label is the user's.
    EditorTool(id: 'stickers', label: 'Emoji', icon: LucideIcons.smile),
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
    // Hold the frame under the playhead as a 3s still, cut in where it is.
    EditorTool(id: 'freeze', label: 'Freeze', icon: LucideIcons.snowflake),
    EditorTool(id: 'speed', label: 'Speed', icon: LucideIcons.gauge),
    // A ramp, which the Speed slider structurally cannot express — and which
    // keyframes cannot hold either, because speed decides what progress means.
    // Its own tool beside Speed, so the common case stays one drag.
    EditorTool(
      id: 'speed_curve',
      label: 'Curve',
      icon: LucideIcons.trendingUp,
    ),
    EditorTool(id: 'volume', label: 'Volume', icon: LucideIcons.volume2),
    // The clip's own presence, beside Volume — a fade of the picture next to
    // a fade of the sound. Keyframable like every clip property.
    EditorTool(id: 'opacity', label: 'Opacity', icon: LucideIcons.contrast),
    // Also on the root menu. Here because the root menu is hidden while a
    // clip is selected, and a tool reachable only by deselecting the clip you
    // want to transform is not reachable.
    EditorTool(id: 'transform', label: 'Transform', icon: LucideIcons.move),
    // **This clip's** crop — freehand, no ratio — as distinct from the root
    // menu's Crop, which is the project's. A different id so the two panels
    // and the two rects cannot be confused; the same label because to the
    // user it is the same verb applied to a smaller thing.
    EditorTool(id: 'clip_crop', label: 'Crop', icon: LucideIcons.crop),
    // A window over the picture, placed on the canvas — an in-place panel like
    // Crop, for the same reason.
    EditorTool(id: 'mask', label: 'Mask', icon: LucideIcons.scan),
    // Drop a colour so the project background shows through — the mask's
    // sibling, and next to it for that reason: both decide which of the clip's
    // pixels survive, one by place and one by colour.
    EditorTool(id: 'chroma', label: 'Chroma', icon: LucideIcons.pipette),
    EditorTool(
      id: 'transition',
      label: 'Transition',
      icon: LucideIcons.arrowLeftRight,
    ),
    EditorTool(id: 'reverse', label: 'Reverse', icon: LucideIcons.rewind),
    // Swap the media under this clip, keeping the edit.
    EditorTool(id: 'replace', label: 'Replace', icon: LucideIcons.replace),
    // Same tool as the root menu, but reached with a clip selected — opening it
    // from here grades that clip rather than the whole project.
    EditorTool(id: 'filters', label: 'Filters', icon: LucideIcons.sliders),
    EditorTool(id: 'adjust', label: 'Adjust', icon: LucideIcons.slidersHorizontal),
    // Beside Filters because a clip's effect and its look are siblings: both
    // change how this one clip is drawn. **Only here, never on the root menu**
    // — an effect belongs to a clip, and the root menu has none selected.
    EditorTool(id: 'effects', label: 'Effects', icon: LucideIcons.sparkles),
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

const EditorMenu _imageOverlayMenu = EditorMenu(
  id: 'image_overlay',
  tools: [
    EditorTool(
      id: 'animation',
      label: 'Animation',
      icon: LucideIcons.playCircle,
    ),
    // The same Mask tool a clip has, cutting the overlay to a shape. One
    // model, one coverage function, so a circle is the same circle on a clip
    // and on an overlay.
    EditorTool(id: 'mask', label: 'Mask', icon: LucideIcons.scan),
    // The same Chroma tool a clip has. It could not exist on an overlay while
    // the preview drew them as widgets: a key is a per-pixel colour decision,
    // so the export would have dropped the green while the canvas showed it.
    EditorTool(id: 'chroma', label: 'Chroma', icon: LucideIcons.pipette),
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
    // The same Mask tool a clip has, cutting the overlay to a shape. One
    // model, one coverage function, so a circle is the same circle on a clip
    // and on an overlay.
    EditorTool(id: 'mask', label: 'Mask', icon: LucideIcons.scan),
    // The same Chroma tool a clip has. It could not exist on an overlay while
    // the preview drew them as widgets: a key is a per-pixel colour decision,
    // so the export would have dropped the green while the canvas showed it.
    EditorTool(id: 'chroma', label: 'Chroma', icon: LucideIcons.pipette),
    EditorTool(id: 'opacity', label: 'Opacity', icon: LucideIcons.contrast),
    EditorTool(id: 'duplicate', label: 'Copy', icon: LucideIcons.copy),
    EditorTool(id: 'delete', label: 'Delete', icon: LucideIcons.trash2),
  ],
);

/// Ways to make text: the root Text tool's submenu.
///
/// Both make a new, **empty** text at the playhead and open the editor on it
/// (`_addText`) — Add text plain, a template wearing its look. Auto captions
/// joins them when its server exists; it is not offered before it works.
const EditorMenu _textMenu = EditorMenu(
  id: 'text',
  tools: [
    EditorTool(id: 'add_text', label: 'Add text', icon: LucideIcons.type),
    EditorTool(
      id: 'text_templates',
      label: 'Templates',
      icon: LucideIcons.layoutTemplate,
    ),
  ],
);

/// What a selected text offers.
///
/// There was no such menu: selecting a text showed the root menu, the tools
/// for making a project and none for the text, and its whole editor hid
/// behind a tap on the already-selected text. **Edit, Style, Font and
/// Animation are doors into the one text sheet**, each opening it on its own
/// tab (`kTextMenuSheetTools`) — no second styling surface, so nothing can
/// drift from it. Their ids carry a `text_` prefix because `animation`
/// already means the photo and video overlays' drawer. Copy and Delete are the
/// handlers every overlay menu shares.
const EditorMenu _textOverlayMenu = EditorMenu(
  id: 'text_overlay',
  tools: [
    EditorTool(id: 'text_edit', label: 'Edit', icon: LucideIcons.pencil),
    EditorTool(id: 'text_style', label: 'Style', icon: LucideIcons.palette),
    EditorTool(
      id: 'text_font',
      label: 'Font',
      icon: LucideIcons.caseSensitive,
    ),
    EditorTool(
      id: 'text_animation',
      label: 'Animation',
      icon: LucideIcons.playCircle,
    ),
    EditorTool(id: 'duplicate', label: 'Copy', icon: LucideIcons.copy),
    EditorTool(id: 'delete', label: 'Delete', icon: LucideIcons.trash2),
  ],
);

final Map<String, EditorMenu> _menus = {
  'root': _rootMenu,
  'edit': _editMenu,

  'audio': _audioMenu,
  'image_overlay': _imageOverlayMenu,
  'video_overlay': _videoOverlayMenu,
  'text': _textMenu,
  'text_overlay': _textOverlayMenu,
  'transition': const EditorMenu(
    id: 'transition',
    tools: [],
  ), // Transitions drawer replaces the tools list
};

// Supported transitions come from EditorTransition â€” see
// features/video_editor/logic/transitions/transition_catalog.dart.

class VideoEditorScreen extends ConsumerStatefulWidget {
  /// Files the project starts from, in the order they were picked.
  final List<XFile> initialMedia;
  final DraftProject? draft;

  const VideoEditorScreen({
    super.key,
    this.initialMedia = const [],
    this.draft,
  });

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen>
    with SingleTickerProviderStateMixin {
  /// Height of the bottom toolbar, and the floor of the tool panel that
  /// replaces it — one number, so opening a tool can never make the bottom
  /// area shorter and drop the timeline.
  static const double _kToolbarHeight = 60.0;

  final AudioPlayerManager _audioPlayerManager = AudioPlayerManager();
  final NativeTimelinePreviewService _nativePreviewService =
      NativeTimelinePreviewService();
  final MediaImportService _mediaImportService = MediaImportService();

  late final Ticker _ticker;
  DateTime? _lastTick;
  StreamSubscription<NativeTimelinePreviewEvent>? _nativePreviewSubscription;
  String? _nativePreviewTimelineSignature;

  bool _isFullscreen = false;

  /// True while a trim handle is held. Gates work that must not run per frame.
  bool _isTrimming = false;
  bool _isScrubbing = false;

  /// True while the ticker is walking the playhead through an audio/overlay
  /// tail past the video's end. Engine position events are ignored for its
  /// duration: the engine is parked on its last frame and any event it emits
  /// would drag the playhead back to the video end.
  bool _isDrivingTail = false;

  /// Guards the one-shot export capability probe. Temporary.
  bool _hasProbedExport = false;

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
    return videoTimelineDuration(segments);
  }


  /// Whether the engine can play this project as it stands.
  ///
  /// The one thing it cannot: a reversed clip whose proxy has not been
  /// rendered yet — no decoder plays backwards. There is no second engine to
  /// fall back to any more, so callers wait for the proxy rather than
  /// substituting a different picture.
  bool _canUseNativeTimelinePreview(VideoEditorState state) {
    return !state.segments.any(
      (segment) =>
          segment.isReversed &&
          (segment.overrideVideoPath == null ||
              segment.overrideVideoPath!.isEmpty),
    );
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

      if (draft != null) {
        _loadDraft(draft);
      } else if (widget.initialMedia.isNotEmpty) {
        _loadMedia(widget.initialMedia);
      } else {
        // Fallback if navigated without a video or draft
        if (mounted) context.pop();
      }
    });

    _nativePreviewSubscription = _nativePreviewService.events.listen(
      _handleNativePreviewEvent,
    );

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

    // The engine is the sole writer of the playhead while it has one; the
    // ticker exists only for the tail past the last video frame, where there
    // is no native clock left. Two clocks writing the playhead is entry 12 in
    // dead-ends.
    _driveNativeAudioTail(
      editorState: editorState,
      notifier: ref.read(videoEditorProvider.notifier),
      delta: delta,
      videoDuration: _videoTimelineDuration(editorState.segments),
      totalDuration: ref.read(totalEditedDurationProvider),
    );
  }

  /// Keeps imported audio in step during native playback.
  ///
  /// The native engine is the **only** writer of the playhead while it has
  /// video to decode — a second clock here would let the playhead run on while
  /// a decoder stalls. The ticker takes over solely for an audio-only tail,
  /// where the video has genuinely ended and there is no native clock left.
  void _driveNativeAudioTail({
    required VideoEditorState editorState,
    required VideoEditorNotifier notifier,
    required double delta,
    required double videoDuration,
    required double totalDuration,
  }) {
    final position = editorState.currentPlaybackPosition;

    if (position < videoDuration - 0.001) {
      _audioPlayerManager.seekAndPlaySync(position, editorState.audioTracks, true);
      return;
    }

    // Past the last video frame the engine's clock has parked, so an overlay
    // that outlives the video would freeze on it. The engine honours this only
    // beyond its own duration, so it can never fight the real clock.
    unawaited(_nativePreviewService.setOverlayClock(position));

    if (totalDuration <= videoDuration + 0.001) {
      // No audio past the end of the video; native reports completion itself.
      return;
    }

    final newPosition = position + delta;
    if (newPosition >= totalDuration) {
      // Park at the end rather than rewinding — going back is the user's move.
      notifier.updatePlaybackPosition(totalDuration);
      notifier.setPlaying(false);
      _audioPlayerManager.pauseAll();
      unawaited(_nativePreviewService.pause());
      return;
    }

    notifier.updatePlaybackPosition(newPosition);
    _audioPlayerManager.seekAndPlaySync(
      newPosition,
      editorState.audioTracks,
      true,
    );
  }

  @override
  void dispose() {
    // Save draft when leaving the editor
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(videoEditorProvider.notifier).saveDraft();
    });

    _ticker.dispose();
    _audioPlayerManager.dispose();
    unawaited(_nativePreviewSubscription?.cancel() ?? Future<void>.value());
    unawaited(_nativePreviewService.dispose());
    super.dispose();
  }

  Future<void> _loadDraft(DraftProject draft) async {
    final notifier = ref.read(videoEditorProvider.notifier);
    try {
      await notifier.loadDraft(draft);
      final notice = notifier.takeLoadNotice();
      if (notice != null && mounted) ToastUtils.show(context, notice);
      await _syncNativePreviewTimeline(ref.read(videoEditorProvider));
      // `ref.listen` fires only on a change, so a project that opens with
      // overlays already on it would never push them — they would show their
      // handles and no picture until one of them was edited.
      await _syncNativeOverlays(ref.read(videoEditorProvider));
    } catch (e) {
      if (!mounted) return;
      ToastUtils.show(context, 'Error loading draft: $e', isError: true);
    }
  }

  /// Builds a project from one or more picked files.
  ///
  /// Durations and dimensions come from the native probe: a project can hold
  /// photos and several videos, so there is no single file to interrogate.
  Future<void> _loadMedia(List<XFile> files) async {
    if (files.isEmpty) return;
    final notifier = ref.read(videoEditorProvider.notifier);

    try {
      final assets = await _mediaImportService.assetsFor(files);
      if (assets.isEmpty) {
        if (!mounted) return;
        ToastUtils.show(context, 'Could not read the selected media.',
            isError: true);
        return;
      }

      await notifier.loadProject(assets: assets);
      await _syncNativePreviewTimeline(ref.read(videoEditorProvider));
      // `ref.listen` fires only on a change, so a project that opens with
      // overlays already on it would never push them — they would show their
      // handles and no picture until one of them was edited.
      await _syncNativeOverlays(ref.read(videoEditorProvider));
    } catch (e) {
      if (!mounted) return;
      ToastUtils.show(context, 'Error loading media: $e', isError: true);
    }
  }

  /// Adds more files to the project already open in the editor.
  Future<void> _addMedia() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    try {
      final assets = await _mediaImportService.pickMedia();
      if (assets.isEmpty) return;

      notifier.addAssets(assets);
      await _syncNativePreviewTimeline(ref.read(videoEditorProvider));
      // `ref.listen` fires only on a change, so a project that opens with
      // overlays already on it would never push them — they would show their
      // handles and no picture until one of them was edited.
      await _syncNativeOverlays(ref.read(videoEditorProvider));
      if (mounted) HapticFeedback.selectionClick();
    } catch (e) {
      if (!mounted) return;
      ToastUtils.show(context, 'Could not add media: $e', isError: true);
    }
  }

  void _togglePreview() {
    ref.read(videoEditorProvider.notifier).togglePreview();
  }

  void _handleNativePreviewEvent(NativeTimelinePreviewEvent event) {
    if (!mounted) return;
    if (event.type == 'error') {
      ToastUtils.show(
        context,
        event.message ?? 'Native preview error',
        isError: true,
      );
    } else if (event.type == 'warning') {
      // A compromise the engine made, not a failure: the second decoder a
      // transition wanted, or the buffers an effect needed. The picture is
      // still playing, so this is not `isError` — but it must be *said*, or
      // the preview quietly differs from what the project describes and
      // nothing explains why. The export screen has always surfaced its own
      // `exportWarning`; the preview dropped these on the floor until now.
      ToastUtils.show(context, event.message ?? 'Preview compromise');
    } else if (event.type == 'position' && event.positionSeconds != null) {
      final state = ref.read(videoEditorProvider);
      if (!_canUseNativeTimelinePreview(state) || !state.isPlaying) return;
      if (_isDrivingTail) return;

      final position = event.positionSeconds!;
      ref.read(videoEditorProvider.notifier).updatePlaybackPosition(position);
      _audioPlayerManager.seekAndPlaySync(position, state.audioTracks, true);
    } else if (event.type == 'completed') {
      final state = ref.read(videoEditorProvider);
      if (!_canUseNativeTimelinePreview(state)) return;

      final notifier = ref.read(videoEditorProvider.notifier);
      final videoDuration = _videoTimelineDuration(state.segments);
      final totalDuration = ref.read(totalEditedDurationProvider);

      // Audio or an overlay can outlast the video. The engine's clock ends
      // with its last frame, so the ticker takes over from here and walks the
      // playhead through the tail while the canvas shows the background.
      if (totalDuration > videoDuration + 0.05) {
        notifier.updatePlaybackPosition(videoDuration);
        _isDrivingTail = true;
        _lastTick = DateTime.now();
        _ticker.start();
        return;
      }

      // The playhead parks at the end. Snapping back to zero threw away where
      // the user was — reviewing an edit means scrubbing around the ending,
      // and the jump made that a two-step chore every single time.
      notifier.updatePlaybackPosition(videoDuration);
      notifier.setPlaying(false);
      _audioPlayerManager.pauseAll();
    }
  }

  /// What the engine was last told the overlays are. See [_syncNativeOverlays].
  String? _nativeOverlaySignature;
  List<ImageOverlayModel>? _syncedImageOverlays;
  List<VideoOverlayModel>? _syncedVideoOverlays;
  Size? _syncedOverlayCanvasSize;

  /// Pushes the overlay list when it changes — and **only** then.
  ///
  /// Overlays are deliberately absent from the playback signature: sending a
  /// whole timeline for an overlay edit re-prepares every lane's player, which
  /// is a decoder rebuild and a visible flash. This is the light channel
  /// instead, and it runs during a drag where [_syncNativePreviewTimeline]
  /// bails out, because moving an overlay must show while the finger is down.
  Future<void> _syncNativeOverlays(VideoEditorState state) async {
    if (!_canUseNativeTimelinePreview(state) || state.sourceVideo == null) {
      _nativeOverlaySignature = null;
      return;
    }
    final canvasSize = ref.read(videoCanvasSizeProvider);
    if (canvasSize == null) return;

    // This runs on **every** state change, and during playback that is a
    // position event ~30 times a second. The payload depends only on the two
    // overlay lists and the canvas size, and the state is immutable — an
    // untouched list keeps its identity through `copyWith` — so three
    // identity checks answer "nothing changed" without composing anything.
    if (_nativeOverlaySignature != null &&
        identical(state.imageOverlays, _syncedImageOverlays) &&
        identical(state.videoOverlays, _syncedVideoOverlays) &&
        canvasSize == _syncedOverlayCanvasSize) {
      return;
    }
    _syncedImageOverlays = state.imageOverlays;
    _syncedVideoOverlays = state.videoOverlays;
    _syncedOverlayCanvasSize = canvasSize;

    final payload = _nativePreviewService.overlayPayload(
      state,
      previewCanvasSize: canvasSize,
    );
    final signature = jsonEncode(payload);
    if (_nativeOverlaySignature == signature) return;
    _nativeOverlaySignature = signature;

    try {
      await _nativePreviewService.sendOverlayPayload(payload);
    } catch (_) {
      // An overlay that cannot be pushed is not worth interrupting an edit
      // for; the engine warns for itself when it cannot draw one.
      _nativeOverlaySignature = null;
    }
  }

  Future<void> _syncNativePreviewTimeline(VideoEditorState state) async {
    if (!_canUseNativeTimelinePreview(state) || state.sourceVideo == null) {
      _nativePreviewTimelineSignature = null;
      return;
    }

    // Pushing a timeline replaces each lane's media items and re-prepares the
    // player, which rebuilds a decoder. Doing that per frame of a trim drag is
    // what made the handles feel heavy, so the drag runs on the Flutter side
    // only and the engine is caught up once on release.
    //
    // A scrub is skipped for a different reason: it does not change the
    // timeline at all, only the playhead. Composing and JSON-encoding the
    // whole timeline every gesture frame just to find the signature unchanged
    // was pure cost on the frame that had to stay smooth.
    // A canvas pinch/drag is the same shape: the engine is fed through its own
    // override channel during the gesture and caught up once on release.
    if (_isTrimming || _isScrubbing || state.isClipTransformActive) return;

    // Overlay geometry is stored in preview-canvas pixels, so the engine needs
    // the canvas size to normalise it.
    final canvasSize = ref.read(videoCanvasSizeProvider);
    final signature = _nativeTimelineSignature(state, canvasSize);
    if (_nativePreviewTimelineSignature == signature) return;
    _nativePreviewTimelineSignature = signature;

    try {
      await _nativePreviewService.setTimeline(
        state,
        previewCanvasSize: canvasSize,
      );
      await _seekNativePreviewToTimeline(state);
      unawaited(_probeExportCapabilitiesOnce(state));
    } catch (e) {
      if (!mounted) return;
      ToastUtils.show(context, 'Native preview unavailable: $e', isError: true);
    }
  }

  /// Logs what this device's codecs will do for an export, once per session.
  ///
  /// Deliberately run with the preview already loaded: export holds two
  /// decoders and an encoder at the same time, and whether the encoder will
  /// start *while playback owns its decoders* is the question that decides
  /// whether export can render straight through or has to bring the second
  /// decoder up only across a transition. Filter logcat on `SlimshotExport`.
  ///
  /// Temporary — it comes out once the export pipeline reads the capabilities
  /// itself.
  Future<void> _probeExportCapabilitiesOnce(VideoEditorState state) async {
    if (_hasProbedExport) return;
    _hasProbedExport = true;
    try {
      await _nativePreviewService.probeExportCapabilities(
        state.projectCanvasSize,
      );
    } catch (e) {
      debugPrint('[SlimshotExport] capability probe failed: $e');
    }
  }

  Future<void> _seekNativePreviewToTimeline(VideoEditorState state) {
    return _nativePreviewService.seek(state.currentPlaybackPosition);
  }

  String _nativeTimelineSignature(
    VideoEditorState state,
    Size? previewCanvasSize,
  ) {
    return _nativePreviewService.playbackSignature(
      state,
      previewCanvasSize: previewCanvasSize,
    );
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

  /// Applies a trim while the handle is being dragged.
  ///
  /// Deliberately does **not** seek: the timeline widget already previews the
  /// frame under the handle at its own rate, and seeking here as well meant two
  /// decoder flushes per drag frame.
  void _setTrimRange(RangeValues value) {
    ref.read(videoEditorProvider.notifier).setTrimRange(value);
  }

  void _beginTrimDrag() {
    _isTrimming = true;
  }

  /// Puts the engine into scrubbing mode for the duration of a playhead drag.
  ///
  /// A scrub asks for a new position every gesture frame. Served as ordinary
  /// seeks that is a decoder flush each, which is what made the preview flash
  /// while the timeline moved. In scrubbing mode ExoPlayer coalesces them:
  /// a newer target replaces an unstarted one, and the next seek waits until a
  /// frame from the previous one has actually been rendered.
  void _beginScrub() {
    if (_isScrubbing) return;
    _isScrubbing = true;
    if (!_canUseNativeTimelinePreview(ref.read(videoEditorProvider))) return;
    unawaited(_nativePreviewService.setScrubbing(true));
  }

  /// Leaves scrubbing mode and lands on the exact position.
  ///
  /// The final seek matters: the coalesced ones are keyframe-cheap and the
  /// last target of a gesture may never have been served.
  void _endScrub() {
    if (!_isScrubbing) return;
    _isScrubbing = false;
    final state = ref.read(videoEditorProvider);
    if (!_canUseNativeTimelinePreview(state)) return;
    unawaited(() async {
      await _nativePreviewService.setScrubbing(false);
      await _seekNativePreviewToTimeline(ref.read(videoEditorProvider));
    }());
  }

  /// Catches the editor up once the handle is released.
  ///
  /// Pushing the timeline is now the only thing the release has to do. It used
  /// to also render the whole edit to an MP4 through Transformer, or failing
  /// that a per-clip FFmpeg proxy, so that a single decoder could play across a
  /// non-contiguous trim. The dual-lane engine plays a trim directly as a
  /// clipping configuration, so a trim is a property change on a media item and
  /// never a reason to re-encode. See `docs/dead-ends.md` entry 17.
  void _endTrimDrag() {
    if (!_isTrimming) return;
    _isTrimming = false;

    unawaited(_syncNativePreviewTimeline(ref.read(videoEditorProvider)));
  }

  /// Replace: pick one file and put it under the selected clip, keeping the
  /// edit. The same picker Add uses; only the first pick is taken, since one
  /// clip has one file.
  Future<void> _replaceSelectedClip() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    if (ref.read(videoEditorProvider).selectedSegment == null) return;
    try {
      final assets = await _mediaImportService.pickMedia();
      if (assets.isEmpty || !mounted) return;
      notifier.replaceClipAsset(assets.first);
      await _syncNativePreviewTimeline(ref.read(videoEditorProvider));
      // `ref.listen` fires only on a change, so a project that opens with
      // overlays already on it would never push them — they would show their
      // handles and no picture until one of them was edited.
      await _syncNativeOverlays(ref.read(videoEditorProvider));
      if (mounted) HapticFeedback.selectionClick();
    } catch (e) {
      if (!mounted) return;
      ToastUtils.show(context, 'Could not replace the clip: $e', isError: true);
    }
  }

  /// Freeze: the frame under the playhead becomes a still clip. Async because
  /// the frame is decoded; the toast is how the blade's refusals already read.
  Future<void> _freezeFrameAtPlayhead() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    try {
      await notifier.freezeFrameAtPlayhead();
      if (!mounted) return;
      HapticFeedback.selectionClick();
    } catch (e) {
      if (!mounted) return;
      ToastUtils.show(context, e.toString(), isError: true);
    }
  }

  /// Drops the engine's live volume override for the clip being edited, so
  /// the committed (or unchanged) value takes over. Harmless when none is held.
  void _liftLiveVolume() {
    final segment = ref.read(videoEditorProvider.notifier).getActiveSegment();
    if (segment == null) return;
    unawaited(_nativePreviewService.clearClipVolume(clipId: segment.id));
  }

  void _splitAtPlayhead() {
    final notifier = ref.read(videoEditorProvider.notifier);
    final state = ref.read(videoEditorProvider);
    final position = state.currentPlaybackPosition;
    try {
      notifier.splitAtPlayhead(position);
      HapticFeedback.selectionClick();
    } catch (e) {
      ToastUtils.show(context, e.toString(), isError: true);
    }
  }

  /// Opens the one text sheet on [tab] for the selected text.
  ///
  /// The text menu's Edit, Style, Font and Animation all come here — they are
  /// doors into the existing sheet, not surfaces of their own.
  void _openSelectedTextEditor(TextEditorTool tab) {
    final state = ref.read(videoEditorProvider);
    final id = state.selectedTextId;
    if (id == null) return;
    final overlay = state.textOverlays.where((t) => t.id == id).firstOrNull;
    if (overlay == null) return;
    unawaited(
      showTextEditor(
        context: context,
        overlay: overlay,
        ref: ref,
        initialTool: tab,
      ),
    );
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

  /// Makes a new text at the playhead — plain, or wearing [template] — and
  /// opens the editor on it with the keyboard up.
  ///
  /// **Always empty**, template or not: the editor deletes a text still empty
  /// when it closes, so nothing the user did not type can reach an export. A
  /// template's sample words were only ever its tile's. Add text and every
  /// template come through here, so a new text is made one way.
  void _addText({TextTemplate? template}) {
    final editorState = ref.read(videoEditorProvider);
    final start = Duration(
      milliseconds: (editorState.currentPlaybackPosition * 1000).toInt(),
    );
    // Not clamped to the video's end — an overlay may outlast the video,
    // matching audio.
    final end = start + const Duration(seconds: 3);
    final canvasSize = ref.read(videoCanvasSizeProvider);
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final overlay = template?.apply(
          id: id,
          startTime: start,
          endTime: end,
          canvasSize: canvasSize,
        ) ??
        TextOverlayModel(
          id: id,
          text: '',
          startTime: start,
          endTime: end,
          referenceCanvasSize: canvasSize,
        );
    // Selects it and opens its menu, which the editor closing leaves showing.
    ref.read(videoEditorProvider.notifier).addTextOverlay(overlay);
    unawaited(showTextEditor(context: context, overlay: overlay, ref: ref));
  }

  /// Drops [emoji] on the canvas as a text overlay.
  ///
  /// **An emoji is text, not a new overlay kind.** It renders through the
  /// platform's own colour emoji face, so going this way it inherits the whole
  /// text pipeline — the glyph atlas, per-character animation, mask, chroma
  /// key, keyframes and export parity — all of it already device-verified. A
  /// dedicated emoji overlay would be a second implementation of that.
  ///
  /// Unlike "Add text" this does **not** open the editor: the user has already
  /// chosen what they want, and a keyboard over the canvas would be a second
  /// decision nobody asked for. Tapping the overlay opens the editor as usual,
  /// so styling and animation are one tap away.
  void _addEmojiOverlay(String emoji) {
    final editorState = ref.read(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    final proposedStart = Duration(
      milliseconds: (editorState.currentPlaybackPosition * 1000).toInt(),
    );
    // Not clamped to the video's end — an overlay may outlast the video, the
    // same rule text and audio already follow.
    final proposedEnd = proposedStart + const Duration(seconds: 3);

    final overlay = TextOverlayModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: emoji,
      startTime: proposedStart,
      endTime: proposedEnd,
      referenceCanvasSize: ref.read(videoCanvasSizeProvider),
      // An emoji at caption size reads as punctuation rather than as a
      // sticker, so it lands at `kEmojiOverlayScale`. Still one scale value
      // the pinch gesture edits from — nothing here is a special case for the
      // renderer, only a different starting size.
      scale: kEmojiOverlayScale,
    );
    notifier.addTextOverlay(overlay);
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
      // Deliberately not clamped to the video's end: an overlay may outlast
      // the video, and playback then continues over the background — the same
      // rule audio already follows. The old clamp went further wrong by using
      // `durationSeconds`, the *first asset's* length.
      final proposedEnd = proposedStart + const Duration(seconds: 5);

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

      // Duration from the native probe — the same one import uses. It reads
      // the container directly instead of opening a whole player to ask.
      final probed = await _mediaImportService.assetsFor([picked]);
      final videoDuration = probed.isEmpty
          ? const Duration(seconds: 5)
          : Duration(
              milliseconds: (probed.first.durationSeconds * 1000).round(),
            );

      var proposedStart = Duration(
        milliseconds: (editorState.currentPlaybackPosition * 1000).toInt(),
      );
      // Not clamped to the video's end — see the image-overlay add above.
      final proposedEnd = proposedStart + videoDuration;

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
    final previewCanvasSize = ref.read(exportCanvasSizeProvider);

    if (previewCanvasSize == null) {
      ToastUtils.show(
        context,
        "Cannot export video. Missing parameters.",
        isError: true,
      );
      return;
    }

    final targetHeight = _exportHeight;
    final targetFps = _exportFps;
    final exportState = ref.read(videoEditorProvider);

    // The one thing native export cannot render: a reversed clip whose proxy
    // has not been prepared, because no decoder plays backwards. There is no
    // legacy path to fall back to any more, so this says so rather than
    // exporting the clip forwards.
    if (!_canUseNativeTimelinePreview(exportState)) {
      ToastUtils.show(
        context,
        'A reversed clip is still preparing. Try again in a moment.',
        isError: true,
      );
      return;
    }

    try {
      notifier.setExporting(true);

      void navigateToExport() {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            // Native export renders through the preview engine, so the file
            // matches what was previewed — correct per-clip filters, all
            // eleven transitions, and the right source file for every clip.
            builder: (context) => ExportVideoScreen(
              exportState: exportState,
              previewCanvasSize: previewCanvasSize,
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
      // **Only while a clip is selected**, and the icon says which way it acts:
      // a plus places a diamond at the playhead, a minus removes the one the
      // playhead is standing on.
      showsKeyframeControls: editorState.keyframeClipId != null,
      isOnKeyframe: editorState.playheadIsOnKeyframe,
      // Dim while the playhead is on another clip: there is no instant of the
      // selected clip to pin, and the old clamp pinned its edge instead.
      canToggleKeyframe: editorState.selectedClipProgress != null,
      onToggleKeyframe: () {
        HapticFeedback.selectionClick();
        final notifier = ref.read(videoEditorProvider.notifier);
        if (editorState.playheadIsOnKeyframe) {
          notifier.removeKeyframeAtPlayhead();
        } else {
          notifier.addKeyframeAtPlayhead();
        }
      },
      // Inert where there is nothing to ease — fewer than two diamonds, or the
      // playhead outside them. The icon dims rather than disappearing.
      canEditCurve: editorState.canEditKeyframeCurve,
      onOpenEasing: () => showKeyframeEasingSheet(
        context,
        current: editorState.keyframeCurve,
        onSelected: (curve) =>
            ref.read(videoEditorProvider.notifier).setKeyframeCurve(curve),
      ),
    );
  }

  /// Opens the transitions sheet, and **leaves the transition menu when it
  /// closes**.
  ///
  /// Selecting a seam sets `currentMenuId: 'transition'`, whose tool list is
  /// deliberately empty because this drawer replaces it. Nothing put that back,
  /// so dismissing the sheet left the user staring at an empty submenu — the
  /// device report. `deselectAll` is the existing exit: it clears the seam
  /// selection and returns to the root menu.
  ///
  /// **The `await` is what makes this correct for every way a sheet can close**
  /// — the ✓, a tap on the scrim, or the system Back gesture all complete the
  /// future, where an `onTap` handler on the sheet's own button would only
  /// catch the first. The edit itself is already committed to state and is
  /// untouched by this; only the selection and the menu are transient.
  Future<void> _showTransitionsDrawer() async {
    await showEditorSheet<void>(
      context,
      builder: (context) => const TransitionsDrawer(),
    );
    if (!mounted) return;
    ref.read(videoEditorProvider.notifier).deselectAll();
  }

  /// Opens the transform sheet on the selected clip — or, from the root menu,
  /// on the clip under the playhead — and **puts back what it borrowed**.
  ///
  /// From the root menu nothing is selected, so the sheet selects the clip
  /// under the playhead itself. That selection is the sheet's, not the user's:
  /// the toolbar is chosen by `currentMenuId`, which stays on root, so leaving
  /// the clip selected showed root tools beside a selected clip and its
  /// keyframe controls — a half state the user never entered. Awaiting the
  /// sheet covers every way it closes, the same reason
  /// [_showTransitionsDrawer] awaits. A selection the user made stays.
  Future<void> _showTransformSheet() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    final borrowed = ref.read(videoEditorProvider).selectedSegmentId == null &&
        notifier.selectSegmentAtPlayhead();
    await showEditorSheet<void>(
      context,
      builder: (context) => const TransformSheet(),
    );
    if (!mounted || !borrowed) return;
    notifier.deselectAll();
  }

  /// The chroma key sheet, on the clip under the playhead. Borrows and hands
  /// back a selection exactly as the transform and curve sheets do.
  Future<void> _showChromaKeySheet() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    final state = ref.read(videoEditorProvider);
    // **Only borrow a clip when nothing at all is selected.** An overlay is a
    // target in its own right now, and borrowing over it would key the clip
    // under the playhead instead of the overlay the user opened the tool on.
    final hasTarget = state.selectedSegmentId != null ||
        state.selectedImageId != null ||
        state.selectedVideoOverlayId != null;
    final borrowed = !hasTarget && notifier.selectSegmentAtPlayhead();
    await showEditorSheet<void>(
      context,
      builder: (context) => const ChromaKeySheet(),
    );
    if (!mounted || !borrowed) return;
    notifier.deselectAll();
  }

  /// The speed curve sheet, on the clip under the playhead.
  ///
  /// Borrows a selection the way [_showTransformSheet] does, and hands it back
  /// when the sheet closes: the toolbar is chosen by `currentMenuId`, so a
  /// selection left behind would show root tools beside a selected clip.
  Future<void> _showSpeedCurveSheet() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    final borrowed = ref.read(videoEditorProvider).selectedSegmentId == null &&
        notifier.selectSegmentAtPlayhead();
    await showEditorSheet<void>(
      context,
      builder: (context) => const SpeedCurveSheet(),
    );
    if (!mounted || !borrowed) return;
    notifier.deselectAll();
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
      height: _kToolbarHeight,
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
            child: EditorToolTile(icon: tool.icon, label: tool.label),
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
    final visibleTools = menu.tools
        .where(
          (tool) => isToolbarToolVisible(
            tool.id,
            isSplitEnabled: isSplitEnabled,
            canDeleteSegment: canDelete,
            isClipSelected: editorState.isClipSelected,
            clipCount: editorState.segments.length,
            hasTextSelected: editorState.selectedTextId != null,
            hasImageSelected: editorState.selectedImageId != null,
            hasVideoOverlaySelected:
                editorState.selectedVideoOverlayId != null,
          ),
        )
        .toList();

    return SizedBox(
      height: _kToolbarHeight,
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
                onTap: () async {
                  HapticFeedback.selectionClick();
                  if (tool.id == 'audio') {
                    showEditorSheet<void>(
                      context,
                      builder: (context) => const AudioDrawer(),
                    );
                  } else if (tool.id == 'filters') {
                    // Reached from the clip menu, the tool means "filter this
                    // clip", so the sheet opens in per-clip mode. The switch
                    // moves the project look down onto every clip rather than
                    // dropping it, so the picture is unchanged — and the
                    // toggle at the top of the sheet shows the mode and
                    // reverses it.
                    if (editorState.currentMenuId == 'edit' &&
                        editorState.selectedSegmentId != null) {
                      notifier.setFilterAppliesToAll(false);
                    }
                    showEditorSheet<void>(
                      context,
                      builder: (context) => const FiltersDrawer(),
                    );
                  } else if (tool.id == 'adjust') {
                    // Which level it writes is the sheet's toggle; it opens on
                    // the selected clip when there is one.
                    showEditorSheet<void>(
                      context,
                      builder: (_) => const AdjustSheet(),
                    );
                  } else if (tool.id == 'transform') {
                    _showTransformSheet();
                  } else if (tool.id == 'speed_curve') {
                    _showSpeedCurveSheet();
                  } else if (tool.id == 'chroma') {
                    _showChromaKeySheet();
                  } else if (tool.id == 'effects' &&
                      editorState.currentMenuId == 'edit') {
                    // Gated on the clip menu: the audio menu carries an
                    // `effects` tool of its own (unbuilt, and deliberately
                    // left visible), and an effect without a clip has no
                    // target.
                    showEditorSheet<void>(
                      context,
                      builder: (context) => const EffectsPanel(),
                    );
                  } else if (tool.id == 'stickers') {
                    showEditorSheet<void>(
                      context,
                      builder: (context) => StickersDrawer(
                        onEmojiSelected: _addEmojiOverlay,
                      ),
                    );
                  } else if (tool.hasSubMenu) {
                    notifier.setCurrentMenu(tool.id);
                    if (tool.id == 'edit' &&
                        editorState.selectedSegmentId == null &&
                        editorState.segments.isNotEmpty) {
                      notifier.selectSegment(editorState.segments.first.id);
                    }
                  } else if (tool.id == 'add') {
                    unawaited(_addMedia());
                  } else if (tool.id == 'freeze') {
                    unawaited(_freezeFrameAtPlayhead());
                  } else if (tool.id == 'replace') {
                    unawaited(_replaceSelectedClip());
                  } else if (kTextMenuSheetTools[tool.id] case final tab?) {
                    _openSelectedTextEditor(tab);
                  } else if (tool.id == 'split') {
                    if (editorState.selectedVideoOverlayId != null) {
                      try {
                        notifier.splitVideoOverlay(
                          editorState.currentPlaybackPosition,
                        );
                        HapticFeedback.selectionClick();
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
                    _showTransitionsDrawer();
                  } else if (tool.id == 'reverse') {
                    if (editorState.selectedSegmentId != null) {
                      final segment = editorState.segments.firstWhere(
                        (segment) =>
                            segment.id == editorState.selectedSegmentId,
                      );
                      if (segment.isReversed) {
                        await notifier.toggleReverse(
                          editorState.selectedSegmentId!,
                        );
                        if (!context.mounted) return;
                        ToastUtils.show(
                          context,
                          'Restored normal clip',
                          isError: false,
                        );
                      } else {
                        ToastUtils.show(context, 'Preparing reverse...');
                        try {
                          await notifier.toggleReverse(
                            editorState.selectedSegmentId!,
                          );
                          if (!context.mounted) return;
                            ToastUtils.show(
                            context,
                            'Reversed clip is ready',
                            isError: false,
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ToastUtils.show(context, e.toString(), isError: true);
                        }
                      }
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
                    showEditorSheet<void>(
                      context,
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
                    _addText();
                  } else if (tool.id == 'text_templates') {
                    unawaited(
                      showEditorSheet<void>(
                        context,
                        builder: (_) => TextTemplatesSheet(
                          onTemplateSelected: (template) =>
                              _addText(template: template),
                        ),
                      ),
                    );
                  } else if (tool.id == 'overlay') {
                    _showOverlaySelectionMenu(buttonContext);
                  } else if (tool.id == 'background') {
                    // A choice about the picture with no canvas or timeline
                    // gesture attached: a sheet, like filters and the curve.
                    showEditorSheet<void>(
                      context,
                      builder: (_) => const BackgroundSheet(),
                    );
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
                child: EditorToolTile(icon: tool.icon, label: tool.label),
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
      case 'clip_crop':
        content = _buildClipCropPanel();
        break;
      case 'mask':
        content = const MaskPanel();
        break;
      case 'zoom':
        content = _buildZoomPanel();
        break;
      case 'templates':
        content = const Center(
          child: Text(
            'Templates coming soon!',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        );
        break;
      case 'opacity':
        content = _buildOpacityPanel();
        break;
      default:
        content = _buildPlaceholderPanel(_getToolLabel(activeToolId));
        break;
    }

    // **The panel takes the height its content needs**, floored at the
    // toolbar it replaces so the timeline never drops when a tool opens. It
    // used to be a fixed 160 (200 for Background) with the body stretched to
    // fill: the crop panel was a box holding one row of chips, and the empty
    // rest read as a gap between the panel and the timeline. Every body
    // therefore lays out under an unbounded height — see
    // `tool_panel_sizing_test.dart` for the two that needed a bound of their
    // own. The timeline gives up its idle slack at the same moment
    // (`ScrollableTimeline.compact`), so what the panel adds over the toolbar
    // comes out of empty track area before it comes out of the picture.
    return Container(
      key: ValueKey(activeToolId),
      constraints: const BoxConstraints(minHeight: _kToolbarHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  // Discarding a preview needs no player call for speed, but
                  // the live volume override has to be lifted explicitly: the
                  // engine holds it until a timeline push, and a discard pushes
                  // none.
                  _liftLiveVolume();
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
                  _commitAndCloseActiveTool();
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
          content,
        ],
      ),
    );
  }

  /// Closes the open tool **keeping** what the user set.
  ///
  /// The ✓, and every dismissal that is not the explicit ✕: the system Back
  /// button and a tap on the canvas's empty space (`tool_dismissal.dart`). A
  /// panel is modal in spirit, and a sheet's dismissal keeps its live edits,
  /// so a panel's does too — preview values (volume, speed, zoom) are
  /// committed here, and ✕ (`closeActiveTool` alone) stays the one way to
  /// discard them. Reads state fresh: it is called from gestures that outlive
  /// the build that wired them.
  void _commitAndCloseActiveTool() {
    final editorState = ref.read(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final activeToolId = editorState.activeToolId;
    if (activeToolId == null) return;

    if (activeToolId == 'volume' && editorState.previewVolume != null) {
      if (editorState.selectedAudioId != null) {
        final track = editorState.audioTracks.firstWhere(
          (a) => a.id == editorState.selectedAudioId!,
        );
        notifier.updateAudioTrack(
          track.copyWith(volume: editorState.previewVolume!),
        );
        notifier.setPreviewVolume(null); // just clears the preview state
      } else if (editorState.selectedVideoOverlayId != null) {
        notifier.setPreviewVolume(null); // already updated in the panel
      } else {
        notifier.commitPreviewVolume();
      }
    }
    if (activeToolId == 'volume') _liftLiveVolume();
    if (activeToolId == 'speed' && editorState.previewSpeed != null) {
      notifier.commitPreviewSpeed();
    }
    if (activeToolId == 'zoom' && editorState.previewVideoScale != null) {
      notifier.commitPreviewVideoTransform();
    }
    notifier.closeActiveTool();
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
        // One snapshot for the drag; the frames between write live. Going
        // through `updateVideoOverlay` per frame pushed an undo entry each
        // time, so Undo walked the drag back a pixel at a time — the same
        // fault the overlay *move* gesture had, and the reason
        // `updateVideoOverlayLive` exists.
        onChangeStart: notifier.saveStateForUndo,
        onChanged: (value) {
          // Written to the model immediately so the engine hears it.
          notifier.setPreviewVolume(value);
          notifier.updateVideoOverlayLive(
            videoOverlay.id,
            (v) => v.copyWith(volume: value),
          );
        },
      );
    }

    final activeSegment = ref.watch(activeSegmentProvider);
    return VolumePanel(
      // **What the write will target**, which on a keyframed clip is the value
      // at the playhead, not the base. A slider showing the base while the
      // keyframes had taken the volume down offered no way to drag *up* — the
      // thumb sat at the top while the audio was quiet. See
      // [VideoEditorState.clipEditValue].
      displayVolume: editorState.previewVolume ??
          (activeSegment == null
              ? 0
              : editorState.clipEditValue(activeSegment, ClipProperty.volume)),
      emptyMessage: activeSegment == null
          ? 'Select a clip to adjust volume'
          : null,
      // State for the ✓ to commit through the edit rule; the override channel
      // so the engine plays the level being dragged. Device-reported: the
      // slider set a level the user could not hear until they confirmed it.
      onChanged: (value) {
        notifier.setPreviewVolume(value);
        if (activeSegment != null) {
          unawaited(_nativePreviewService.setClipVolume(
            clipId: activeSegment.id,
            volume: value,
          ));
        }
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
      onChanged: notifier.setPreviewSpeed,
    );
  }

  Widget _buildOpacityPanel() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    // A clip's opacity goes through the edit rule like every clip property:
    // base on an unkeyframed clip, the diamond under the playhead otherwise,
    // and the slider shows what its write will target. Overlays keep their
    // own path below.
    final segment = editorState.selectedSegment;
    if (segment != null &&
        editorState.selectedImageId == null &&
        editorState.selectedVideoOverlayId == null) {
      return OpacityPanel(
        opacity: editorState.clipEditValue(segment, ClipProperty.opacity),
        onChangeStart: notifier.saveStateForUndo,
        onChanged: (value) => notifier.setClipProperty(
          ClipProperty.opacity,
          value,
          takeUndoSnapshot: false,
        ),
      );
    }

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

  /// The clip-crop tool's panel. The editing happens on the canvas — the
  /// handles are drawn there — so this holds only what the canvas cannot: the
  /// instruction, and a way back to the whole frame.
  Widget _buildClipCropPanel() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final segment = editorState.selectedSegment;
    if (segment == null) {
      return const Center(
        child: Text(
          'Select a clip to crop it.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Drag the corners on the canvas. This crop applies to this clip only.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          ApplyToAllButton(
            key: const Key('clip_crop_apply_all'),
            enabled: editorState.segments.length > 1,
            onPressed: () {
              final count = notifier.applyCropToAllClips();
              ToastUtils.show(
                context,
                'Crop applied to $count other clip${count == 1 ? '' : 's'}.',
              );
            },
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: segment.isCropped
                ? () {
                    HapticFeedback.selectionClick();
                    notifier.resetClipCropRect();
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(
                  color: segment.isCropped
                      ? AppColors.border
                      : AppColors.border.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Reset',
                style: TextStyle(
                  color: segment.isCropped
                      ? AppColors.textPrimary
                      : AppColors.textTertiary.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildPlaceholderPanel(String toolName) {
    return PlaceholderPanel(toolName: toolName);
  }

  Widget _buildScrollableTimeline() {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final sourceVideo = editorState.sourceVideo;
    if (sourceVideo == null) {
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
      // While a tool panel is open the track area releases its idle slack,
      // so the panel's extra height comes out of empty rows, not the canvas.
      compact: editorState.activeToolId != null,
      onPausePlayback: () {
        if (ref.read(videoEditorProvider).isPlaying) {
          ref.read(videoEditorProvider.notifier).setPlaying(false);
        }
      },
      inputPath: sourceVideo.path,
      durationSeconds: editorState.durationSeconds,
      timelinePositionSeconds: editorState.currentPlaybackPosition,
      trimRange: editorState.trimRange,
      segments: displaySegments,
      selectedSegmentId: editorState.selectedSegmentId,
      onSegmentTapped: _selectSegment,
      // **Tapping the seam opens the transitions sheet.** The timeline selects
      // the seam and calls this; the screen owns the modal. Without it the tap
      // only set `currentMenuId: 'transition'`, whose tool list is empty by
      // design — the drawer replaces it — so the user got an empty submenu and
      // no way to choose anything.
      onTransitionTapped: (_) => _showTransitionsDrawer(),
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
      onTrimDragStart: _beginTrimDrag,
      onTrimDragEnd: _endTrimDrag,
      onScrubStart: _beginScrub,
      onScrubEnd: _endScrub,
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
        // Any transport change ends the tail; the engine owns the clock again.
        _isDrivingTail = false;
        _lastTick = DateTime.now();
        // Ensure audio players are loaded before playing
        final state = ref.read(videoEditorProvider);
        _audioPlayerManager.syncTracks(state.audioTracks);

        // The playhead parks at the end when playback finishes. Pressing play
        // there means "again", so it restarts from the top — anywhere else it
        // resumes in place.
        final totalDuration = ref.read(totalEditedDurationProvider);
        if (state.currentPlaybackPosition >= totalDuration - 0.05) {
          ref.read(videoEditorProvider.notifier).updatePlaybackPosition(0.0);
        }

        unawaited(() async {
          await _syncNativePreviewTimeline(state);
          await _seekNativePreviewToTimeline(ref.read(videoEditorProvider));
          await _nativePreviewService.play();
        }());
        // The engine drives the playhead; the ticker only takes over for a
        // tail past the last video frame.
        _ticker.stop();
      } else {
        _isDrivingTail = false;
        _ticker.stop();
        unawaited(_nativePreviewService.pause());
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

    ref.listen<VideoEditorState>(videoEditorProvider, (prev, state) {
      // Overlays go on their own light channel, so unlike the timeline they
      // are pushed while playing and mid-drag too — an overlay moved under the
      // finger has to move on the canvas.
      unawaited(_syncNativeOverlays(state));
      if (_canUseNativeTimelinePreview(state) && !state.isPlaying) {
        // Adding or retuning a transition costs nothing now — it is a shader
        // uniform, not a render — so there is no cache to schedule here.
        unawaited(_syncNativePreviewTimeline(state));
      }
    });

    // Sync audio players when scrubbing the timeline (while paused)
    ref.listen<double>(
      videoEditorProvider.select((s) => s.currentPlaybackPosition),
      (prev, currentPos) {
        final state = ref.read(videoEditorProvider);
        if (!state.isPlaying) {
          // Deliberately no _syncNativePreviewTimeline here: the whole-state
          // listener above already runs on this change, and composing plus
          // encoding the timeline twice per gesture frame was a large part of
          // why dragging the playhead felt heavy.
          if (_canUseNativeTimelinePreview(state)) {
            unawaited(_seekNativePreviewToTimeline(state));
          }
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
        // Back closes an open tool the way it closes a sheet, and only with
        // none open leaves the editor. Device-reported: it left.
        switch (backActionFor(
          activeToolId: ref.read(videoEditorProvider).activeToolId,
        )) {
          case BackAction.closeTool:
            _commitAndCloseActiveTool();
            return;
          case BackAction.leaveEditor:
            break;
        }
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
                      child: VideoPreviewCanvas(
                              videoSurface: NativeTimelinePreviewView(
                                service: _nativePreviewService,
                              ),
                              onTogglePreview: () => ref
                                  .read(videoEditorProvider.notifier)
                                  .togglePreview(),
                              onDeadZoneTapped: () {
                                final notifier = ref.read(
                                  videoEditorProvider.notifier,
                                );
                                notifier.selectTextOverlay(null);
                                notifier.selectImageOverlay(null);
                                // Empty space dismisses an open panel the way
                                // it dismisses a sheet — unless the tool edits
                                // on the canvas, where a tap is part of using
                                // it (`toolClosesOnCanvasTap`).
                                final tool =
                                    ref.read(videoEditorProvider).activeToolId;
                                if (tool != null && toolClosesOnCanvasTap(tool)) {
                                  _commitAndCloseActiveTool();
                                }
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
                                        : TextEditorTool.style,
                                  ),
                              onCanvasSizeChanged: (size) {
                                ref
                                        .read(videoCanvasSizeProvider.notifier)
                                        .state =
                                    size;
                              },
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
                // On the editor's motion, like the panel switcher and the
                // timeline inside it: this wraps both, so its height is their
                // sum, and a different clock here lags or leads them.
                duration: AppMotion.enter,
                curve: AppMotion.enterCurve,
                alignment: Alignment.topCenter,
                child: Offstage(
                  offstage: _isFullscreen,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Offstage(
                        // The panels that used to replace the timeline
                        // (text style/font/animation) collapsed into the
                        // text editor sheet; the timeline stays visible.
                        offstage: false,
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
                            // Toolbar, panel and context menu swap with the
                            // motion a sheet has — see EditorPanelSwitcher.
                            child: EditorPanelSwitcher(
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
