import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/lucide_icons.dart';
import '../core/theme/sound_effect_icon.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../core/utils/file_utils.dart';
import '../core/utils/held_work.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/discard_dialog.dart';
import '../core/widgets/permission_dialog.dart';
import '../core/services/ad_service.dart';
import 'export_video_screen.dart';
import '../features/video_editor/widgets/panels/transitions_drawer.dart';
import '../features/video_editor/models/effect_bar_model.dart';
import '../features/video_editor/models/text_overlay_model.dart';
import '../features/video_editor/models/image_overlay_model.dart';
import '../features/video_editor/models/video_segment.dart';
import '../features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import '../features/video_editor/logic/effects/effect_stack.dart';
import '../features/video_editor/logic/text_overlay_geometry.dart';
import '../features/video_editor/logic/text_template_catalog.dart';
import '../features/video_editor/widgets/panels/text_templates_sheet.dart';
import '../features/video_editor/logic/tool_dismissal.dart';
import '../features/video_editor/logic/toolbar_visibility.dart';
import '../features/video_editor/logic/clip_to_overlay.dart';
import '../features/video_editor/widgets/panels/move_to_overlay_dialog.dart';
import '../features/video_editor/logic/timeline/playhead_display_clock.dart';
import '../features/video_editor/logic/timeline/timeline_geometry.dart';
import '../features/video_editor/providers/tile_preview_store_provider.dart';
import '../features/video_editor/providers/video_editor_notifier.dart';
import '../features/video_editor/services/media_import_service.dart';
import '../features/video_editor/services/effect_bars_sync.dart';
import '../features/video_editor/services/native_timeline_preview_service.dart';
import '../core/models/draft_project.dart';
import '../features/video_editor/logic/animation/clip_keyframes.dart';
import '../features/video_editor/logic/animation/overlay_keyframes.dart';
import '../features/video_editor/widgets/editor_playback_controls.dart';
import '../features/video_editor/widgets/panels/keyframe_easing_sheet.dart';
import '../features/video_editor/widgets/panels/transform_sheet.dart';
import '../features/video_editor/widgets/timeline/scrollable_timeline.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import '../features/video_editor/widgets/video_editor_top_bar.dart';
import '../features/video_editor/widgets/panels/effects_panel.dart';
import '../features/video_editor/widgets/panels/filters_drawer.dart';
import '../features/video_editor/widgets/panels/stickers_drawer.dart';
import '../features/video_editor/services/audio_player_manager.dart';
import '../features/video_editor/services/playback_guard.dart';
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
import '../features/account/providers/account_providers.dart';
import '../core/services/slimshot_api.dart';
import '../features/video_editor/logic/captions/caption_grouping.dart';
import '../features/video_editor/logic/captions/caption_preset_catalog.dart';
import '../features/video_editor/logic/captions/caption_settings.dart';
import '../features/video_editor/logic/captions/captions_mode.dart';
import '../features/video_editor/logic/new_text.dart';
import '../features/video_editor/logic/text_look.dart';
import '../features/video_editor/services/caption_access.dart';
import '../features/video_editor/services/caption_pipeline.dart';
import '../features/video_editor/services/caption_run.dart';
import '../features/video_editor/services/caption_service.dart';
import '../features/video_editor/widgets/panels/auto_caption_sheet.dart';
import '../features/video_editor/widgets/panels/caption_style_sheet.dart';
import '../features/video_editor/widgets/panels/caption_batch_sheet.dart';
import '../features/video_editor/widgets/panels/caption_progress_sheet.dart';
import '../features/video_editor/widgets/captions_mode/captions_mode_view.dart';
import '../features/video_editor/widgets/panels/replace_captions_dialog.dart';
import '../features/video_editor/widgets/editor_tool_tile.dart';
import '../features/video_editor/widgets/panels/adjust_sheet.dart';
import '../features/video_editor/widgets/panels/chroma_key_sheet.dart';
import '../features/video_editor/widgets/panels/speed_curve_sheet.dart';
import '../features/video_editor/widgets/panels/apply_to_all_button.dart';
import '../features/video_editor/widgets/panels/mask_panel.dart';
import '../features/account/services/account_service.dart';
import '../features/account/widgets/earn_credits_block.dart';
import '../features/sound_library/data/catalog_models.dart';
import '../features/sound_library/import_audio.dart';
import '../features/sound_library/providers.dart';
import '../features/sound_library/sound_library_controller.dart';
import '../features/video_editor/widgets/panels/sound_library_sheet.dart';
import '../features/video_editor/widgets/panels/extract_audio_sheet.dart';
import '../features/audio_tools/audio_tools_service.dart';
import '../features/audio_tools/extract_preview_player.dart';
import '../features/audio_tools/extract_selection.dart';
import '../features/audio_tools/pick_video.dart';
import '../features/audio_tools/record_controller.dart';
import '../features/audio_tools/voice_recorder_service.dart';
import '../features/video_editor/widgets/panels/record_panel.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../core/services/draft_files.dart';
import '../features/fonts/font_registry.dart';
import '../features/fonts/font_service.dart';
import '../features/fonts/project_fonts.dart';
import '../features/fonts/providers.dart';
import '../core/services/media_picker_service.dart';

class EditorTool {
  final String id;
  final String label;
  final IconData icon;

  /// Drawn in place of [icon] where Lucide has no fitting glyph.
  final Widget Function(double size, Color color)? glyph;
  final bool hasSubMenu;

  const EditorTool({
    required this.id,
    required this.label,
    required this.icon,
    this.glyph,
    this.hasSubMenu = false,
  });
}

class EditorMenu {
  final String id;
  final List<EditorTool> tools;
  const EditorMenu({required this.id, required this.tools});
}

/// How much of the footage before a transition plays when its tile is
/// tapped, and how much after — enough to see where it comes from and where
/// it lands, short enough to be over before the next tap.
const double _kTransitionPlayLeadSeconds = 0.6;
const double _kTransitionPlayTailSeconds = 0.4;

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
    // Also in the Text submenu, but found here: under Text alone it was hard
    // to find (device-reported). The same id, so one handler and one
    // visibility rule — no server address, no tool — serve both doors.
    EditorTool(
      id: 'auto_captions',
      label: 'Auto captions',
      icon: LucideIcons.subtitles,
    ),
    EditorTool(id: 'overlay', label: 'Overlay', icon: LucideIcons.layers),
    // Effects are bars on the timeline, dropped at the playhead with nothing
    // selected — so they open from here, not from a clip.
    EditorTool(id: 'effects', label: 'Effects', icon: LucideIcons.sparkles),
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
    // CapCut's "Overlay" on a clip: lifts it one lane down at the same time,
    // where it was drawn, and the main track closes up. Beside Replace — both
    // re-house the clip.
    EditorTool(id: 'to_overlay', label: 'Overlay', icon: LucideIcons.squareStack),
    // Same tool as the root menu, but reached with a clip selected — opening it
    // from here grades that clip rather than the whole project.
    EditorTool(id: 'filters', label: 'Filters', icon: LucideIcons.sliders),
    EditorTool(id: 'adjust', label: 'Adjust', icon: LucideIcons.slidersHorizontal),
    // Beside Filters because a clip's effect and its look are siblings: both
    // change how this one clip is drawn. **Only here, never on the root menu**
    // — an effect belongs to a clip, and the root menu has none selected.
    EditorTool(id: 'delete', label: 'Delete', icon: LucideIcons.trash2),
  ],
);

const EditorMenu _audioMenu = EditorMenu(
  id: 'audio',
  tools: [
    // Music, beside Effects: "Sounds" read as if effects were not sounds.
    EditorTool(id: 'music', label: 'Music', icon: LucideIcons.music),
    // The sound effects library. Its own id: `effects` is the clip menu's.
    EditorTool(
      id: 'sound_effects',
      label: 'Sound effects',
      icon: LucideIcons.music,
      glyph: SoundEffectIcon.glyph,
    ),
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

/// A selected effect bar. Edit opens the effects sheet on the bar — another
/// effect, its strength — and Copy continues the effect straight after it.
const EditorMenu _effectBarMenu = EditorMenu(
  id: 'effect_bar',
  tools: [
    EditorTool(id: 'effect_edit', label: 'Edit', icon: LucideIcons.sparkles),
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
/// (`_addText`) — Add text plain, Templates wearing a look chosen first:
/// choose, then type. The other way round — type, then choose — is the
/// selected text's own Templates. Auto captions is the third way, offered only
/// in a build that carries a server address (`isToolbarToolVisible`).
const EditorMenu _textMenu = EditorMenu(
  id: 'text',
  tools: [
    EditorTool(id: 'add_text', label: 'Add text', icon: LucideIcons.type),
    EditorTool(
      id: 'add_template',
      label: 'Templates',
      icon: LucideIcons.layoutTemplate,
    ),
    EditorTool(
      id: 'auto_captions',
      label: 'Auto captions',
      icon: LucideIcons.subtitles,
    ),
  ],
);

/// What a selected text offers.
///
/// There was no such menu: selecting a text showed the root menu, the tools
/// for making a project and none for the text, and its whole editor hid
/// behind a tap on the already-selected text. **Edit, Templates, Style, Font
/// and Animation are doors into the one text sheet**, each opening it on its
/// own tab (`kTextMenuSheetTools`) — no second styling surface, so nothing can
/// drift from it. Templates sits after Edit: type, then choose a look, and
/// change it as often as you like. Their ids carry a `text_` prefix because `animation`
/// already means the photo and video overlays' drawer. Copy and Delete are the
/// handlers every overlay menu shares.
///
/// **A caption gets two more, right after Edit** — shown only for a caption
/// (`isToolbarToolVisible`): Caption style, the set's look and highlight, and
/// Captions, the list of its whole set. A caption's look is changed on the
/// caption, where it can be judged against the footage, not in the sheet that
/// generates captions.
const EditorMenu _textOverlayMenu = EditorMenu(
  id: 'text_overlay',
  tools: [
    EditorTool(id: 'text_edit', label: 'Edit', icon: LucideIcons.pencil),
    EditorTool(
      id: 'caption_style',
      label: 'Caption style',
      icon: LucideIcons.highlighter,
    ),
    EditorTool(id: 'captions', label: 'Captions', icon: LucideIcons.subtitles),
    EditorTool(
      id: 'text_templates',
      label: 'Templates',
      icon: LucideIcons.layoutTemplate,
    ),
    EditorTool(id: 'text_style', label: 'Style', icon: LucideIcons.palette),
    EditorTool(
      id: 'text_font',
      label: 'Font',
      icon: LucideIcons.caseSensitive,
    ),
    // The letters' size, for everyone who would rather not pinch — a door
    // into the text sheet's Size tab, like Font beside it.
    EditorTool(id: 'text_size', label: 'Size', icon: LucideIcons.ruler),
    EditorTool(
      id: 'text_animation',
      label: 'Animation',
      icon: LucideIcons.playCircle,
    ),
    EditorTool(id: 'opacity', label: 'Opacity', icon: LucideIcons.contrast),
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
  'effect_bar': _effectBarMenu,
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

  /// Auto captions from Home: the editor in its captions mode — the video in
  /// a card, no timeline, no draft — until ✎ opens the full editor on the
  /// same project.
  final bool captionsMode;

  const VideoEditorScreen({
    super.key,
    this.initialMedia = const [],
    this.draft,
    this.captionsMode = false,
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

  /// Pauses playback when the app leaves the screen or something else takes
  /// the phone's audio, through the same pause as the button.
  final SessionPlaybackAudio _playbackAudio = SessionPlaybackAudio();
  late final PlaybackGuard _playbackGuard;

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

  /// The playhead as drawn: carried on every frame between the engine's
  /// reports while it plays (`PlayheadDisplayClock`), the playhead state
  /// otherwise. The timeline scrolls to it and text is drawn at it. Nothing
  /// writes it back — the reports stay the playhead state's only writer.
  final ValueNotifier<double> _drawnPlayhead = ValueNotifier(0);
  final PlayheadDisplayClock _playheadClock = PlayheadDisplayClock();
  final Stopwatch _playheadWatch = Stopwatch()..start();

  /// True while the engine plays the video and its reports drive the drawn
  /// playhead — not in the tail, where the ticker walks the state itself.
  bool _followingEngine = false;

  /// Where the playhead stood when a pause ended playback the engine drove.
  /// The engine's own stopping point (on its `paused` event) is taken in its
  /// place only if nothing has moved the playhead since.
  double? _pauseFrom;

  /// Where the engine stopped, once the playhead has been put there, so the
  /// move does not seek the engine onto the frame it is already showing.
  double? _engineParkedAt;

  /// Where a transition played from the transitions sheet stops: just past
  /// its window. Null when nothing is being played that way; any pause clears
  /// it, so it never stops a playback the user started.
  double? _transitionPlaybackStop;

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

  /// Recording mode's rules while the mode is on; null otherwise.
  RecordController? _recordController;

  /// Captions mode (Auto captions from Home). Off for good once ✎ opens the
  /// full editor on the same project.
  late bool _captionsMode = widget.captionsMode;
  final CaptionsModeSession _captionsSession = CaptionsModeSession();
  CaptionRun? _captionRun;
  void Function()? _closeCaptionClient;
  bool _startingCaptions = false;
  String? _captionsLanguage;
  CaptionLength _captionsLength = CaptionLength.phrase;

  /// A line under the card on Ready: why a run came back.
  String? _captionsNotice;

  /// The canvas keeps its state across ✎: the full editor takes it over
  /// rather than building the preview again.
  final GlobalKey _previewKey = GlobalKey();

  /// Set while the mode is ending, so ✓ and an outside close arriving
  /// together end it once — not two closes and two disposes.
  bool _endingRecording = false;

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
    // Captions made from Home keep no draft — nothing in Recent Edits — until
    // ✎ makes them an editor project.
    if (widget.captionsMode) {
      ref.read(videoEditorProvider.notifier).setSavesDraft(false);
    }
    // Export's ads ahead of their moment: the consent step, the SDK, the 4K
    // unlock's rewarded ad and the interstitial after an export.
    unawaited(AdService.prepare(AdPlacement.export));
    _playbackGuard = PlaybackGuard(
      audio: _playbackAudio,
      isPlaying: () => ref.read(videoEditorProvider).isPlaying,
      pause: () => ref.read(videoEditorProvider.notifier).setPlaying(false),
    );
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

    // The Transitions and Effects tiles kept from an earlier launch are found
    // now, long before either sheet can open — a tile asked for before the
    // store knows what it holds is drawn again and shows its icon.
    unawaited(ref.read(tilePreviewStoreProvider).prepare());

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

    // The engine is the sole writer of the playhead while it has one; here
    // the ticker only draws it between the engine's reports, writing nothing.
    // Two clocks writing the playhead is entry 12 in dead-ends.
    if (_followingEngine) {
      _drawnPlayhead.value = _playheadClock.positionAt(
        _playheadWatch.elapsed,
        end: _videoTimelineDuration(editorState.segments),
      );
      return;
    }

    // Past the last video frame there is no native clock left, and the
    // ticker walks the playhead through the tail itself.
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
    // First, so nothing pauses through a screen on its way out; the audio
    // goes back to other apps.
    _playbackGuard.dispose();
    unawaited(_playbackAudio.dispose());

    // Captions mode: a run still going stops; the picked video goes with the
    // screen unless ✎ made it an editor project's.
    _endCaptionRun(disposing: true);
    HeldWork.instance.release(_captionsSession);
    if (widget.captionsMode) {
      unawaited(FileUtils.deleteTempFiles(
        _captionsSession.picksToDeleteOnLeave(
          [for (final file in widget.initialMedia) file.path],
        ),
      ));
    }

    // Save draft when leaving the editor (nothing while captions mode keeps
    // no draft)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(videoEditorProvider.notifier).saveDraft();
    });

    final recording = _recordController;
    _recordController = null;
    if (recording != null) {
      unawaited(recording.recorder.close(keep: false).catchError((_) => null));
      recording.dispose();
    }
    _ticker.dispose();
    _drawnPlayhead.dispose();
    _audioPlayerManager.dispose();
    unawaited(_nativePreviewSubscription?.cancel() ?? Future<void>.value());
    unawaited(_nativePreviewService.dispose());
    super.dispose();
  }

  Future<void> _loadDraft(DraftProject draft) async {
    final notifier = ref.read(videoEditorProvider.notifier);
    try {
      await notifier.loadDraft(draft);
      // Fonts already on the phone draw from the first frame; the rest are
      // fetched by the text listener below.
      await ref.read(fontServiceProvider).registerOnPhone(
            ref.read(videoEditorProvider).textOverlays.map((t) => t.fontFamily),
          );
      final notice = notifier.takeLoadNotice();
      if (notice != null && mounted) ToastUtils.show(context, notice);
      await _syncNativePreviewTimeline(ref.read(videoEditorProvider));
      // `ref.listen` fires only on a change, so a project that opens with
      // overlays or effect bars already on it would never push them — they
      // would show on the timeline and not on the canvas until one was edited.
      await _syncNativeOverlays(ref.read(videoEditorProvider));
      await _syncNativeEffects(ref.read(videoEditorProvider));
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
      // overlays or effect bars already on it would never push them — they
      // would show on the timeline and not on the canvas until one was edited.
      await _syncNativeOverlays(ref.read(videoEditorProvider));
      await _syncNativeEffects(ref.read(videoEditorProvider));
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
      // overlays or effect bars already on it would never push them — they
      // would show on the timeline and not on the canvas until one was edited.
      await _syncNativeOverlays(ref.read(videoEditorProvider));
      await _syncNativeEffects(ref.read(videoEditorProvider));
      if (mounted) HapticFeedback.selectionClick();
    } catch (e) {
      if (!mounted) return;
      ToastUtils.show(context, 'Could not add media: $e', isError: true);
    }
  }

  void _togglePreview() {
    final recording = _recordController;
    if (recording != null) {
      unawaited(recording.toggle());
      return;
    }
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
      _playheadClock.report(
        position,
        advancing: event.advancing,
        at: _playheadWatch.elapsed,
      );
      _audioPlayerManager.seekAndPlaySync(position, state.audioTracks, true);
    } else if (event.type == 'paused') {
      // A pause the editor asked for lands on the frame the engine stopped
      // on: the last report is up to an interval behind it, and the drawn
      // playhead a little ahead. Anything that moved the playhead meanwhile
      // — a scrub, a play — wins.
      final from = _pauseFrom;
      final at = event.positionSeconds;
      _pauseFrom = null;
      if (from == null || at == null) return;
      final state = ref.read(videoEditorProvider);
      if (state.isPlaying || state.currentPlaybackPosition != from) return;
      _engineParkedAt = at;
      ref.read(videoEditorProvider.notifier).updatePlaybackPosition(at);
    } else if (event.type == 'completed') {
      final state = ref.read(videoEditorProvider);
      if (!_canUseNativeTimelinePreview(state)) return;

      final notifier = ref.read(videoEditorProvider.notifier);
      final videoDuration = _videoTimelineDuration(state.segments);
      final totalDuration = ref.read(totalEditedDurationProvider);

      // Audio or an overlay can outlast the video. The engine's clock ends
      // with its last frame, so the ticker takes over from here and walks the
      // playhead through the tail while the canvas shows the background.
      _followingEngine = false;
      if (totalDuration > videoDuration + 0.05) {
        notifier.updatePlaybackPosition(videoDuration);
        _isDrivingTail = true;
        _lastTick = DateTime.now();
        if (!_ticker.isActive) _ticker.start();
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

  /// What the engine was last told the effect bars are.
  final EffectBarsSync _effectBarsSync = EffectBarsSync();

  /// Pushes the effect bars when they change — and only then — on their own
  /// channel, for the reason [_syncNativeOverlays] gives: a bar dragged,
  /// trimmed or retuned must show while the finger is down, and a timeline
  /// push would re-prepare the players.
  Future<void> _syncNativeEffects(VideoEditorState state) async {
    if (!_canUseNativeTimelinePreview(state) || state.sourceVideo == null) {
      _effectBarsSync.reset();
      return;
    }
    final payload =
        _effectBarsSync.payloadFor(state, _nativePreviewService.effectPayload);
    if (payload == null) return;
    try {
      await _nativePreviewService.sendEffectPayload(payload);
    } catch (_) {
      // Sent again with the next change; the engine keeps the last bars.
      _effectBarsSync.reset();
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
  /// One frame of a text, photo or video overlay gesture on the timeline: a
  /// move when [lane] is given, a trim of an edge when it is not.
  void _placeLaneItem(String id, Duration start, Duration end, int? lane) {
    final notifier = ref.read(videoEditorProvider.notifier);
    final from = start.inMicroseconds / 1e6;
    if (lane != null) {
      notifier.moveLaneItem(id, start: from, targetLane: lane);
    } else {
      notifier.trimLaneItem(id, start: from, end: end.inMicroseconds / 1e6);
    }
  }

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
      // overlays or effect bars already on it would never push them — they
      // would show on the timeline and not on the canvas until one was edited.
      await _syncNativeOverlays(ref.read(videoEditorProvider));
      await _syncNativeEffects(ref.read(videoEditorProvider));
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

  /// CapCut's "Overlay" on a clip — lifts it onto the overlay track where it
  /// was drawn. Asks first only when the move would leave something behind (a
  /// filter, a speed curve…); a clip that loses nothing just moves.
  Future<void> _moveSelectedClipToOverlay() async {
    final segment = ref.read(videoEditorProvider).selectedSegment;
    final canvas = ref.read(videoCanvasSizeProvider);
    if (segment == null || canvas == null) return;
    final losses = clipToOverlayLosses(segment);
    if (losses.isNotEmpty) {
      final move = await confirmMoveToOverlay(context, losses);
      if (!move || !mounted) return;
    }
    final moved = ref.read(videoEditorProvider.notifier).moveSelectedClipToOverlay(
          canvas: canvas,
          overlayId: DateTime.now().millisecondsSinceEpoch.toString(),
        );
    if (moved) HapticFeedback.mediumImpact();
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

    final overlay = newText(
      id: id,
      start: start,
      end: end,
      canvasSize: canvasSize,
      template: template,
    );
    // Selects it and opens its menu, which the editor closing leaves showing.
    ref.read(videoEditorProvider.notifier).addTextOverlay(overlay);
    unawaited(showTextEditor(context: context, overlay: overlay, ref: ref));
  }

  /// Fonts this session has already asked for — fetched or failed — so an
  /// edit that leaves a text's font alone asks nothing.
  final Set<String> _fontsAsked = {};
  bool _fontFailureShown = false;

  /// Fetches every font the project's texts wear that is not drawable yet.
  /// A font that cannot be had is said once a session: its texts draw in
  /// the System font, in the preview and in the file.
  void _fetchProjectFonts(Iterable<TextOverlayModel> texts) {
    if (!ref.read(fontServerConfiguredProvider)) return;
    final service = ref.read(fontServiceProvider);
    final names = fontsToFetch(
      texts.map((t) => t.fontFamily),
      _fontsAsked,
      FontRegistry.instance.isAvailable,
    );
    for (final name in names) {
      _fontsAsked.add(name);
      unawaited(service.ensureAvailable(name).then((result) {
        if (result == FontAvailability.available || _fontFailureShown || !mounted) return;
        _fontFailureShown = true;
        ToastUtils.show(context, kFontUnavailableMessage, isError: true);
      }));
    }
  }

  /// Fetches the fonts a grid of tiles draws in, so its tiles show their
  /// real faces.
  void _prefetchFonts(Set<String> names) {
    if (!ref.read(fontServerConfiguredProvider)) return;
    unawaited(ref.read(fontServiceProvider).prefetch(names));
  }

  /// The selected caption's Caption style: the set's styles and highlight.
  /// Every tap reaches the whole set at once, one undo step each.
  void _showCaptionStyle() {
    final editor = ref.read(videoEditorProvider);
    final caption = editor.textOverlays
        .where((t) => t.id == editor.selectedTextId && t.isCaption)
        .firstOrNull;
    if (caption == null) return;
    final notifier = ref.read(videoEditorProvider.notifier);
    _prefetchFonts(captionPresetFontNames(kCaptionPresets));
    unawaited(
      showEditorSheet<void>(
        context,
        builder: (_) => CaptionStyleSheet(
          look: TextLook.of(caption),
          highlight: caption.highlight,
          onPresetChosen: (preset) =>
              notifier.restyleCaptions(preset.look, preset.highlight),
          onHighlightChanged: notifier.setCaptionHighlight,
        ),
      ),
    );
  }

  /// The selected caption's list: every caption of its set, to read down and
  /// fix. A caption left with no words is removed when the list closes — the
  /// rule the text editor has for a text left empty.
  Future<void> _showCaptionList() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    notifier.setPlaying(false);
    _audioPlayerManager.pauseAll();
    unawaited(_nativePreviewService.pause());

    await showEditorSheet<void>(
      context,
      builder: (_) => CaptionBatchSheet(
        initialCaptionId: ref.read(videoEditorProvider).selectedTextId,
        onSeek: (seconds) {
          notifier.updatePlaybackPosition(seconds);
          unawaited(
            _seekNativePreviewToTimeline(ref.read(videoEditorProvider)),
          );
        },
      ),
    );
    if (!mounted) return;
    notifier.removeEmptyCaptions();
    if (_captionsMode) {
      // A row tap selects its caption; captions mode has no selection. An
      // emptied set is Ready again.
      notifier.deselectAll();
      _syncCaptionsHold();
    }
  }

  /// Text → Auto captions: sign in if needed, choose, wait for the words,
  /// place them.
  ///
  /// The audio is a snapshot of the timeline, so playback stops and the
  /// progress sheet holds the editor until the words land. The captions are
  /// placed as one undo step, replacing an existing set only after asking.
  Future<void> _startAutoCaptions() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    if (!await CaptionAccess.ensureAllowed(context, ref) || !mounted) return;
    final request = await showEditorSheet<CaptionRequest>(
      context,
      builder: (_) => AutoCaptionSheet(
        initial: ref.read(videoEditorProvider).captionSettings,
      ),
    );
    if (request == null || !mounted) return;
    if (ref.read(videoEditorProvider).hasCaptions &&
        !await confirmReplaceCaptions(context)) {
      return;
    }
    if (!mounted) return;

    notifier.setPlaying(false);
    _audioPlayerManager.pauseAll();
    unawaited(_nativePreviewService.pause());

    final client = _newCaptionPipeline();
    final drafts = await showEditorSheet<List<CaptionDraft>>(
      context,
      builder: (_) => CaptionProgressSheet(
        pipeline: client.pipeline,
        request: request,
        earnCredits: (quote, onEarned) => EarnCreditsBlock(onEarned: onEarned),
      ),
    );
    client.close();
    // The run may have spent credits, or had them refunded: the balance on
    // the home screen follows.
    unawaited(ref.read(accountProvider.notifier).refresh());
    if (drafts == null || !mounted) return;
    _placeCaptionDrafts(drafts, request);
  }

  /// A caption run's pipeline on a client of its own — the editor's Auto
  /// captions and captions mode build theirs alike. `close` lets the client
  /// go once the run is over.
  ({CaptionPipeline pipeline, void Function() close}) _newCaptionPipeline() {
    final api = SlimshotApi(
      baseUrl: SlimshotApi.configuredBaseUrl,
      session: ref.read(accountSessionProvider),
    );
    final captions = CaptionService(api);
    // On the run's own client, so Cancel stops a quote in flight too.
    final account = AccountService(api);
    final pipeline = CaptionPipeline(
      audioPath: () async {
        final dir = await getTemporaryDirectory();
        return '${dir.path}/${captionAudioFileName(DateTime.now())}';
      },
      renderAudio: (path, source, onProgress) =>
          _nativePreviewService.renderCaptionAudio(
        ref.read(videoEditorProvider),
        outputPath: path,
        source: source,
        onProgress: onProgress,
      ),
      quotePrice: (seconds) =>
          account.quote(AccountService.autoCaptionsFeature, seconds),
      onCharged: (balance) =>
          unawaited(ref.read(accountProvider.notifier).applyBalance(balance)),
      startJob: (path, language, key) => captions.start(
        audioPath: path,
        language: language,
        idempotencyKey: key,
      ),
      awaitJob: (job, isCancelled) =>
          captions.result(job, isCancelled: isCancelled),
      onCancel: () {
        unawaited(_nativePreviewService.cancelCaptionAudio());
        api.close();
      },
    );
    return (pipeline: pipeline, close: api.close);
  }

  /// Puts [drafts] on the project as one undo step, replacing any set.
  void _placeCaptionDrafts(List<CaptionDraft> drafts, CaptionRequest request) {
    // Read before the old set is replaced: a regeneration keeps the set's
    // style, and a project's first set wears the default one.
    final style = captionStyleForNewSet(
      ref.read(videoEditorProvider).textOverlays,
    );
    ref.read(videoEditorProvider.notifier).placeCaptions(
          drafts,
          CaptionSettings(
            setId: 'captions_${DateTime.now().millisecondsSinceEpoch}',
            source: request.source,
            language: request.language,
            length: request.length,
            highlight: style.highlight,
          ),
          canvasSize: ref.read(videoCanvasSizeProvider),
          look: style.look,
          fontSize: style.fontSize,
        );
  }

  // --- Captions mode: Auto captions from Home ---
  //
  // The editor with another face, the way recording mode is: the project,
  // the preview, the caption run, the styles and the export are the editor's
  // own, so the captions are the editor's. Its rules are
  // `logic/captions/captions_mode.dart`; its face is `CaptionsModeView`.

  CaptionsStep get _captionsStep => captionsStepFor(
        running: _captionRun != null,
        hasCaptions: ref.read(videoEditorProvider).hasCaptions,
      );

  /// Captions on screen that no kept export holds hold the app, so a tap on
  /// the home screen widget only brings it forward; the run holds it itself
  /// while it lasts.
  void _syncCaptionsHold() {
    if (_captionsMode && _captionsSession.holdsWorkAt(_captionsStep)) {
      HeldWork.instance.hold(_captionsSession);
    } else {
      HeldWork.instance.release(_captionsSession);
    }
  }

  /// Generate, on Ready: the editor's own door — sign-in and claim — then a
  /// run on the video's own sound, drawn on the card. The price is checked
  /// silently inside the run, as in the editor.
  Future<void> _generateCaptions() async {
    if (_captionRun != null || _startingCaptions) return;
    setState(() => _startingCaptions = true);
    try {
      if (!await CaptionAccess.ensureAllowed(context, ref) || !mounted) return;
      if (_captionRun != null) return;
      ref.read(videoEditorProvider.notifier).setPlaying(false);
      _audioPlayerManager.pauseAll();
      unawaited(_nativePreviewService.pause());

      final client = _newCaptionPipeline();
      final run = CaptionRun(
        pipeline: client.pipeline,
        request: CaptionRequest(
          language: _captionsLanguage,
          length: _captionsLength,
        ),
      )..addListener(_onCaptionRunChanged);
      setState(() {
        _captionRun = run;
        _closeCaptionClient = client.close;
        _captionsNotice = null;
      });
      run.start();
    } finally {
      if (mounted) setState(() => _startingCaptions = false);
    }
  }

  void _onCaptionRunChanged() {
    final run = _captionRun;
    if (run == null || !mounted) return;
    if (run.drafts != null || runFailureReturnsToReady(run.failure)) {
      // Settled after the run's own notification: a notifier may not be
      // disposed while it notifies.
      scheduleMicrotask(() => _settleCaptionRun(run));
      return;
    }
    setState(() {});
  }

  /// The words landed — placed, the playhead parked in the first caption,
  /// paused — or a soundless video goes back to Ready with its line.
  void _settleCaptionRun(CaptionRun run) {
    if (!mounted || run != _captionRun) return;
    final drafts = run.drafts;
    if (drafts != null) {
      _endCaptionRun();
      _placeCaptionDrafts(drafts, run.request);
      _captionsSession.newSetPlaced();
      _showFirstCaption();
      _prefetchFonts(captionPresetFontNames(kCaptionPresets));
    } else {
      final notice = run.error;
      _endCaptionRun();
      setState(() => _captionsNotice = notice);
    }
    _syncCaptionsHold();
  }

  /// Stops and lets go of the run: Cancel, Back while it runs, the words
  /// landing, the screen closing.
  void _endCaptionRun({bool disposing = false}) {
    final run = _captionRun;
    if (run == null) return;
    run
      ..removeListener(_onCaptionRunChanged)
      ..dispose();
    _closeCaptionClient?.call();
    _captionRun = null;
    _closeCaptionClient = null;
    if (disposing) return;
    // The run may have spent credits, or had them refunded: the balance on
    // the home screen follows.
    unawaited(ref.read(accountProvider.notifier).refresh());
    setState(() {});
  }

  /// Parks the playhead, paused, in the set's first caption, so the words
  /// are on the picture the moment they land; a tap plays.
  void _showFirstCaption() {
    final captions = [
      for (final t in ref.read(videoEditorProvider).textOverlays)
        if (t.isCaption) t,
    ];
    if (captions.isEmpty) return;
    final first = captions.reduce((a, b) => a.startTime <= b.startTime ? a : b);
    final middle = (first.startTime + first.endTime).inMicroseconds / 2e6;
    ref.read(videoEditorProvider.notifier).updatePlaybackPosition(middle);
    unawaited(_seekNativePreviewToTimeline(ref.read(videoEditorProvider)));
  }

  /// Back in captions mode: Ready leaves, a run stops (as Cancel), and Done
  /// asks first until an export of the captions was kept.
  Future<void> _captionsBack() async {
    switch (_captionsSession.backAt(_captionsStep)) {
      case CaptionsBack.stopRun:
        _endCaptionRun();
        _syncCaptionsHold();
        return;
      case CaptionsBack.askDiscard:
        if (!await confirmDiscardCaptions(context) || !mounted) return;
      case CaptionsBack.leave:
        break;
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Export, on Done: the editor's own export at its defaults, HD 1080 at
  /// 30 fps — captions mode offers no options.
  Future<void> _exportCaptions() async {
    final kept = await _exportVideo();
    if (!mounted) return;
    if (kept) _captionsSession.exportKept = true;
    _syncCaptionsHold();
  }

  /// ✎: the full editor on this project, in place — from now on an ordinary
  /// editor project, saved as any is, its picked video its draft's.
  void _openCaptionsInEditor() {
    ref.read(videoEditorProvider.notifier).setSavesDraft(true);
    _captionsSession.openedInEditor = true;
    _syncCaptionsHold();
    setState(() => _captionsMode = false);
  }

  Widget _buildCaptionsMode(VideoEditorState editorState) {
    final notifier = ref.read(videoEditorProvider.notifier);
    final style = captionStyleForNewSet(editorState.textOverlays);
    final busy = _startingCaptions || _captionRun != null;
    return CaptionsModeView(
      step: captionsStepFor(
        running: _captionRun != null,
        hasCaptions: editorState.hasCaptions,
      ),
      // The editor's canvas, captions drawn as the editor draws them; only a
      // tap reaches it, to play and pause — nothing here is moved by hand.
      preview: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePreview,
        child: IgnorePointer(child: _previewCanvas()),
      ),
      playing: editorState.isPlaying,
      aspectRatio: editorState.projectAspectRatio,
      onBack: () => unawaited(_captionsBack()),
      language: _captionsLanguage,
      length: _captionsLength,
      onLanguage: (code) => setState(() => _captionsLanguage = code),
      onLength: (length) => setState(() => _captionsLength = length),
      onGenerate: editorState.segments.isEmpty || busy
          ? null
          : () => unawaited(_generateCaptions()),
      notice: _captionsNotice,
      run: _captionRun,
      onCancel: () {
        _endCaptionRun();
        _syncCaptionsHold();
      },
      earnCredits: (quote, onEarned) => EarnCreditsBlock(onEarned: onEarned),
      style: (look: style.look, highlight: style.highlight),
      onPreset: (preset) =>
          notifier.restyleCaptions(preset.look, preset.highlight),
      onColor: (color) =>
          notifier.setCaptionHighlight(style.highlight.copyWith(color: color)),
      onEditWords: () => unawaited(_showCaptionList()),
      onExport: editorState.isExporting
          ? null
          : () => unawaited(_exportCaptions()),
      onOpenEditor: _openCaptionsInEditor,
    );
  }

  /// The editor's canvas — the native preview and every layer drawn over
  /// it. Captions mode lays the same one out in its card, keyed so ✎ hands
  /// it to the full editor rather than building the preview again.
  Widget _previewCanvas() => VideoPreviewCanvas(
        key: _previewKey,
        videoSurface: NativeTimelinePreviewView(
          service: _nativePreviewService,
        ),
        playhead: _drawnPlayhead,
        onTogglePreview: _togglePreview,
        // The space beside the picture is "done here",
        // one level per tap: an open panel closes
        // keeping its edits (✓'s and Back's own close)
        // with the selection left as it was; with none
        // open, the selection clears.
        onOutsidePictureTapped: () {
          switch (outsideTapActionFor(
            activeToolId: ref.read(videoEditorProvider).activeToolId,
          )) {
            case OutsideTapAction.closePanel:
              _commitAndCloseActiveTool();
            case OutsideTapAction.deselect:
              ref.read(videoEditorProvider.notifier).deselectAll();
          }
        },
        onShowTextEditor: (TextOverlayModel overlay, bool showKeyboard) =>
            showTextEditor(
          context: context,
          overlay: overlay,
          ref: ref,
          initialTool:
              showKeyboard ? TextEditorTool.keyboard : TextEditorTool.style,
        ),
        onCanvasSizeChanged: (size) {
          ref.read(videoCanvasSizeProvider.notifier).state = size;
        },
      );

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

  /// Opens the export at the editor's settings. Completes with whether its
  /// file was kept — saved or shared — which captions mode needs to know.
  Future<bool> _exportVideo() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    final previewCanvasSize = ref.read(exportCanvasSizeProvider);

    if (previewCanvasSize == null) {
      ToastUtils.show(
        context,
        "Cannot export video. Missing parameters.",
        isError: true,
      );
      return false;
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
      return false;
    }

    try {
      notifier.setExporting(true);
      if (!mounted) return false;
      // Straight to the export: its interstitial, now and then, comes after
      // it, before the finished video (`showExportAd`), never before.
      final kept = await Navigator.push<bool>(
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
      );
      if (mounted) notifier.setExporting(false);
      return kept ?? false;
    } catch (e) {
      if (mounted) {
        ToastUtils.show(context, e.toString(), isError: true);
        notifier.setExporting(false);
      }
      return false;
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
                                      placement: AdPlacement.export,
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
                                      onFailed: (failure) {
                                        if (context.mounted) {
                                          ToastUtils.show(
                                            context,
                                            unlockFailureMessage(
                                              failure,
                                              labelBuilder(val),
                                            ),
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
      // **Only while a clip or an overlay is selected**, and the icon says
      // which way it acts: a plus places a diamond at the playhead, a minus
      // removes the one the playhead is standing on.
      showsKeyframeControls: editorState.hasKeyframeTarget,
      isOnKeyframe: editorState.playheadIsOnKeyframe,
      // Dim while the playhead is off the selected item: there is no instant
      // of it to pin, and the old clamp pinned its edge instead.
      canToggleKeyframe: editorState.keyframeTargetProgress != null,
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
      builder: (context) => TransitionsDrawer(
        onTransitionChosen: _playTransitionOnCanvas,
      ),
    );
    if (!mounted) return;
    ref.read(videoEditorProvider.notifier).deselectAll();
  }

  /// Plays the transition just applied at [segmentId]'s seam on the canvas —
  /// from a moment before it to a moment after, then stops — so a tile's
  /// promise is checked against the user's own footage at once.
  ///
  /// Through `setPlaying` like the play button: pausing first is what lets
  /// the new transition reach the engine (the timeline is not pushed while
  /// playing), and the play that follows syncs, seeks and starts as always.
  void _playTransitionOnCanvas(String segmentId) {
    final notifier = ref.read(videoEditorProvider.notifier);
    final window = transitionWindowFor(
      ref.read(videoEditorProvider).segments,
      segmentId,
    );
    if (window == null) return;
    notifier.setPlaying(false);
    notifier.updatePlaybackPosition(
      math.max(0.0, window.start - _kTransitionPlayLeadSeconds),
    );
    _transitionPlaybackStop = window.end + _kTransitionPlayTailSeconds;
    notifier.setPlaying(true);
  }

  /// A sound library — effects or music, by its server [library] root. The
  /// sheet owns the controller it is given and disposes it on close; the
  /// library and the caches are app-wide, so a download started in one
  /// opening is not fetched again in the next. Music offers Import too.
  void _showSoundLibrary(String library, {bool offerImport = false}) {
    final notifier = ref.read(videoEditorProvider.notifier);
    final controller = SoundLibraryController(
      root: library,
      client: ref.read(catalogClientProvider),
      library: ref.read(soundLibraryProvider),
      cache: ref.read(catalogCacheProvider(library)),
      player: JustAudioPreviewPlayer(),
    );
    showEditorSheet<void>(
      context,
      builder: (sheetContext) => SoundLibrarySheet(
        controller: controller,
        onAdd: notifier.addLibrarySound,
        onImport: offerImport
            ? () async {
                final track = await pickAudioTrack();
                if (track == null || !sheetContext.mounted) return;
                notifier.addAudioTrack(track);
                Navigator.of(sheetContext).pop();
              }
            : null,
      ),
    );
  }

  /// Extract: a video from the gallery, its sound trimmed in a large sheet,
  /// then a track at the playhead on the first free lane. The sound is
  /// written into the draft's own folder, and one the user did not keep is
  /// deleted again, so the folder holds only what a track points at.
  Future<void> _showExtractAudio() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    final picker = MediaPickerService();
    void say(String message) {
      if (mounted) ToastUtils.show(context, message, isError: true);
    }

    final picked = await pickVideoPath(picker.pickVideo, onError: say);
    if (picked == null || !mounted) return;
    notifier.setPlaying(false);

    final tools = AudioToolsService();
    final draftId = ref.read(videoEditorProvider).draftId ?? 'unsaved';
    // Made once, outside the route builder, which runs again on every
    // rebuild of the route; disposed whichever way the sheet closes.
    final player = VideoPlayerExtractPreview();
    final choice = await showEditorSheet<ExtractChoice>(
      context,
      builder: (_) => ExtractAudioSheet(
        initialVideoPath: picked,
        pickVideo: () => pickVideoPath(picker.pickVideo, onError: say),
        extract: (videoPath) async {
          final dir = await DraftFiles.audioDir(draftId);
          final stamp = DateTime.now().millisecondsSinceEpoch;
          return tools.extract(
            videoPath: videoPath,
            outputPath: '${dir.path}/extract_$stamp.m4a',
          );
        },
        peaks: tools.peaks,
        discardSound: (path) {
          try {
            File(path).deleteSync();
          } catch (_) {}
        },
        player: player,
      ),
    );
    unawaited(player.dispose());
    if (choice == null || !mounted) return;
    notifier.placeAudioTrack(extractedTrack(
      sound: choice.sound,
      selection: choice.selection,
      playhead: ref.read(videoEditorProvider).currentPlaybackPosition,
    ));
  }

  /// Record: the editor turns into recording mode — the preview large, the
  /// timeline showing only the clips, one round button in the panel. The
  /// preview is muted while the mode is on (the speaker would play into the
  /// microphone), with a toggle; that is a monitor mute on the engine and
  /// the music players, never the project's own mute.
  Future<void> _enterRecording() async {
    final notifier = ref.read(videoEditorProvider.notifier);
    final state = ref.read(videoEditorProvider);
    if (state.currentPlaybackPosition >=
        ref.read(totalEditedDurationProvider) - 0.05) {
      ToastUtils.show(context, kRecordAtEndMessage);
      return;
    }
    notifier.setPlaying(false);
    final draftId = state.draftId ?? 'unsaved';
    final controller = RecordController(
      recorder: ChannelVoiceRecorder(),
      requestMic: _requestMicrophone,
      newTakePath: () async {
        final dir = await DraftFiles.audioDir(draftId);
        return '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      },
      play: () => notifier.setPlaying(true),
      pause: () => notifier.setPlaying(false),
      setMonitorMuted: (muted) {
        unawaited(_nativePreviewService.setVolume(muted ? 0.0 : 1.0));
        _audioPlayerManager.monitorMuted = muted;
      },
      playhead: () => ref.read(videoEditorProvider).currentPlaybackPosition,
      projectEnd: () => ref.read(totalEditedDurationProvider),
    );
    controller.addListener(_onRecordingChanged);
    setState(() => _recordController = controller);
    await controller.enter();
    notifier.setActiveTool('record');
  }

  Future<MicPermission> _requestMicrophone() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return MicPermission.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MicPermission.permanentlyDenied;
    }
    return MicPermission.denied;
  }

  void _onRecordingChanged() {
    if (!mounted) return;
    final message = _recordController?.takeMessage();
    if (message != null) ToastUtils.show(context, message);
    setState(() {});
  }

  /// The take as the timeline draws it while the mode is on: from where it
  /// began (or the playhead, before it has), for as long as it has run.
  ({double start, double length})? _recordingTake(VideoEditorState state) {
    final recording = _recordController;
    if (recording == null || state.activeToolId != 'record') return null;
    return (
      start: recording.takeStart ?? state.currentPlaybackPosition,
      length: recording.takeStart == null ? 0.0 : recording.takeLength,
    );
  }

  /// Done: the take lands where recording began, on a free lane, selected,
  /// one undo step; with nothing recorded the mode just ends.
  Future<void> _finishRecording() async {
    final recording = _recordController;
    if (recording == null || _endingRecording) return;
    _endingRecording = true;
    final FinishedTake? take;
    try {
      take = await recording.finish();
    } finally {
      _endingRecording = false;
    }
    _leaveRecording(recording);
    if (take == null || !mounted) return;
    ref.read(videoEditorProvider.notifier).placeAudioTrack(AudioTrackModel(
          id: const Uuid().v4(),
          filePath: take.path,
          sourceDuration: take.durationSeconds,
          sourceStart: 0,
          sourceEnd: take.durationSeconds,
          timelineStart: take.timelineStart,
        ));
  }

  /// ✕: the take is thrown away.
  Future<void> _discardRecording() async {
    final recording = _recordController;
    if (recording == null || _endingRecording) return;
    _endingRecording = true;
    try {
      await recording.discard();
    } finally {
      _endingRecording = false;
    }
    _leaveRecording(recording);
  }

  void _leaveRecording(RecordController recording) {
    recording.removeListener(_onRecordingChanged);
    final message = recording.takeMessage();
    recording.dispose();
    if (!mounted) return;
    if (message != null) ToastUtils.show(context, message);
    setState(() => _recordController = null);
    ref.read(videoEditorProvider.notifier).closeActiveTool();
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
                notifier.openRevertibleTool('volume');
              } else if (tool.id == 'delete') {
                if (editorState.selectedAudioId != null) {
                  notifier.deleteAudioTrack(editorState.selectedAudioId!);
                  notifier.selectAudioTrack(null);
                }
              } else if (tool.id == 'duplicate') {
                final audioId = editorState.selectedAudioId;
                if (audioId != null) notifier.duplicateAudioTrack(audioId);
              }
            },
            child: EditorToolTile(
              icon: tool.icon,
              glyph: tool.glyph,
              label: tool.label,
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
            hasCaptionServer: SlimshotApi.isConfigured,
            hasCatalogServer: SlimshotApi.isConfigured,
            hasCaptionSelected: editorState.textOverlays.any(
              (t) => t.id == editorState.selectedTextId && t.isCaption,
            ),
            hasEffectBarSelected: editorState.selectedEffectBarId != null,
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
          final toolEnabled = isToolbarToolEnabled(
            tool.id,
            clipCount: editorState.segments.length,
          );

          return Builder(
            builder: (buttonContext) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  // A dimmed tool waits for the selection to make it apply.
                  if (!toolEnabled) return;
                  HapticFeedback.selectionClick();
                  if (tool.id == 'music') {
                    // Audio is a submenu; Music and Effects are one library
                    // sheet, pointed at the server's two roots.
                    _showSoundLibrary(kMusicRoot, offerImport: true);
                  } else if (tool.id == 'sound_effects') {
                    _showSoundLibrary(kSoundEffectsRoot);
                  } else if (tool.id == 'extract') {
                    unawaited(_showExtractAudio());
                  } else if (tool.id == 'record') {
                    unawaited(_enterRecording());
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
                  } else if (tool.id == 'effects' ||
                      tool.id == 'effect_edit') {
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
                  } else if (tool.id == 'to_overlay') {
                    unawaited(_moveSelectedClipToOverlay());
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
                    if (editorState.selectedEffectBarId != null) {
                      notifier.deleteEffectBar();
                    } else if (editorState.selectedTextId != null) {
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
                    notifier.openRevertibleTool('opacity');
                  } else if (tool.id == 'animation') {
                    showEditorSheet<void>(
                      context,
                      builder: (context) => const AnimationDrawer(),
                    );
                  } else if (tool.id == 'duplicate') {
                    if (editorState.selectedEffectBarId != null) {
                      notifier.duplicateEffectBar();
                    } else if (editorState.selectedTextId != null) {
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
                  } else if (tool.id == 'add_template') {
                    _prefetchFonts(templateFontNames(kTextTemplates));
                    unawaited(
                      showEditorSheet<void>(
                        context,
                        builder: (_) => TextTemplatesSheet(
                          onTemplateSelected: (template) =>
                              _addText(template: template),
                        ),
                      ),
                    );
                  } else if (tool.id == 'captions') {
                    unawaited(_showCaptionList());
                  } else if (tool.id == 'caption_style') {
                    _showCaptionStyle();
                  } else if (tool.id == 'auto_captions') {
                    unawaited(_startAutoCaptions());
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
                    // Volume writes a video overlay live, so ✕ needs the
                    // record to put it back; every other tool here keeps a
                    // preview value of its own, or edits nothing ✕ reverts.
                    if (tool.id == 'volume') {
                      notifier.openRevertibleTool(tool.id);
                    } else {
                      notifier.setActiveTool(tool.id);
                    }
                    if (tool.id == 'zoom') {
                      notifier.setPreviewVideoTransform(
                        previewVideoScale: editorState.videoScale,
                        previewVideoPan: editorState.videoPan,
                      );
                    }
                  }
                },
                child: EditorToolTile(
                  icon: tool.icon,
                  glyph: tool.glyph,
                  label: tool.label,
                  enabled: toolEnabled,
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
      case 'record':
        final recording = _recordController;
        content = recording == null
            ? const SizedBox.shrink()
            : RecordPanel(
                controller: recording,
                onOpenSettings: () => unawaited(openAppSettings()),
              );
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
          // Mask has no bar: its changes are already applied, so ✕ and ✓
          // both only closed it (`toolPanelHasHeader`).
          if (toolPanelHasHeader(activeToolId)) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (activeToolId == 'record') {
                      unawaited(_discardRecording());
                      return;
                    }
                    // Discarding a preview needs no player call for speed, but
                    // the live volume override has to be lifted explicitly: the
                    // engine holds it until a timeline push, and a discard pushes
                    // none.
                    _liftLiveVolume();
                    // Imported music plays through its own player, which the
                    // slider set directly and nothing re-syncs on a discard.
                    final audioId = editorState.selectedAudioId;
                    if (activeToolId == 'volume' && audioId != null) {
                      final track = editorState.audioTracks
                          .where((a) => a.id == audioId)
                          .firstOrNull;
                      if (track != null) {
                        _audioPlayerManager.setVolumeSync(track.id, track.volume);
                      }
                    }
                    // Puts back whatever the slider wrote live — an overlay's
                    // volume or opacity, a clip's opacity.
                    notifier.discardActiveTool();
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
          ],
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

    // Back, the side tap and ✓ all keep what was made: for Record, Done.
    if (activeToolId == 'record') {
      unawaited(_finishRecording());
      return;
    }

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

    // Clip or overlay — a text included — opacity goes through the edit rule:
    // the base with no diamonds, the diamond under the playhead with them, and
    // the slider shows what its write will target. Every drag starts by
    // pausing: it writes at the playhead each frame, and on a keyframed item a
    // moving playhead would leave a trail of diamonds.
    if (editorState.keyframeOverlay != null) {
      return OpacityPanel(
        opacity: editorState.overlayEditValue(OverlayProperty.opacity),
        onChangeStart: notifier.beginOverlayEdit,
        onChanged: (value) {
          notifier.setOverlayOpacity(value, takeUndoSnapshot: false);
        },
      );
    }

    final segment = editorState.selectedSegment;
    return OpacityPanel(
      opacity: segment == null
          ? 1.0
          : editorState.clipEditValue(segment, ClipProperty.opacity),
      onChangeStart: notifier.beginLiveEdit,
      onChanged: (value) => notifier.setClipProperty(
        ClipProperty.opacity,
        value,
        takeUndoSnapshot: false,
      ),
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
      recordingTake: _recordingTake(editorState),
      onPausePlayback: () {
        if (ref.read(videoEditorProvider).isPlaying) {
          ref.read(videoEditorProvider.notifier).setPlaying(false);
        }
      },
      inputPath: sourceVideo.path,
      durationSeconds: editorState.durationSeconds,
      timelinePositionSeconds: editorState.currentPlaybackPosition,
      playhead: _drawnPlayhead,
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
      // A lane index means the item is being moved, none that an edge is
      // being trimmed. Both are live frames of one gesture: the undo snapshot
      // is taken once, by `onDragStart`.
      onTextTrimChanged: (id, start, end, {newLaneIndex}) =>
          _placeLaneItem(id, start, end, newLaneIndex),
      imageOverlays: editorState.imageOverlays,
      selectedImageId: editorState.selectedImageId,
      onImageTapped: notifier.selectImageOverlay,
      onImageTrimChanged: (id, start, end, {newLaneIndex}) =>
          _placeLaneItem(id, start, end, newLaneIndex),
      videoOverlays: editorState.videoOverlays,
      selectedVideoId: editorState.selectedVideoOverlayId,
      onVideoTapped: notifier.selectVideoOverlay,
      onVideoTrimChanged: (id, start, end, {newLaneIndex}) =>
          _placeLaneItem(id, start, end, newLaneIndex),
      audioTracks: editorState.audioTracks,
      effectBars: editorState.effectBars,
      selectedEffectBarId: editorState.selectedEffectBarId,
      onEffectBarTapped: notifier.selectEffectBar,
      onEffectBarChanged: (id, start, end, {newLaneIndex}) =>
          _placeLaneItem(id, start, end, newLaneIndex),
      selectedAudioId: editorState.selectedAudioId,
      onAudioTapped: (id) => notifier.selectAudioTrack(id),
      onAudioDragChanged: (id, newStart, {newLaneIndex}) {
        final lane = newLaneIndex ??
            editorState.audioTracks.firstWhere((a) => a.id == id).laneIndex;
        notifier.moveLaneItem(id, start: newStart, targetLane: lane);
      },
      onAudioTrimChanged: (id, newTimelineStart, newSourceStart, newSourceEnd) {
        notifier.trimAudioTrackLive(
          id,
          timelineStart: newTimelineStart,
          sourceStart: newSourceStart,
          sourceEnd: newSourceEnd,
        );
      },
      onTimelinePositionChanged: notifier.updatePlaybackPosition,
      // One undo entry per gesture, taken before anything moves. It used to be
      // taken at the *end*, a snapshot of the finished state — so the first
      // Undo did nothing, and a clip trim could not be undone at all.
      onDragStart: notifier.beginTimelineGesture,
      onDragEnd: notifier.endTimelineGesture,
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
      // The phone's audio is the editor's while it plays, and given back the
      // moment it stops, by whatever stopped it.
      _playbackGuard.playingChanged(isPlaying);
      if (isPlaying) {
        // Any transport change ends the tail; the engine owns the clock again.
        _isDrivingTail = false;
        _pauseFrom = null;
        _engineParkedAt = null;
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
        // The engine drives the playhead; the ticker draws it between the
        // engine's reports, and walks it through a tail past the last frame.
        _playheadClock.place(ref.read(videoEditorProvider).currentPlaybackPosition);
        _followingEngine = true;
        if (!_ticker.isActive) _ticker.start();
      } else {
        if (_followingEngine) {
          _pauseFrom = ref.read(videoEditorProvider).currentPlaybackPosition;
        }
        _followingEngine = false;
        _isDrivingTail = false;
        _transitionPlaybackStop = null;
        _ticker.stop();
        unawaited(_nativePreviewService.pause());
        _audioPlayerManager.pauseAll();
      }
    });

    // An edit that leaves a bar skipped by the pass budget says so once, by
    // name: the bar stays on the timeline and is drawn nowhere, so without a
    // word it would read as an effect that does not work. A list arriving
    // into an empty one is a draft opening (or an undo back to one) — one bar
    // added alone always fits — so it is not told again.
    ref.listen<List<EffectBarModel>>(
      videoEditorProvider.select((s) => s.effectBars),
      (prev, bars) {
        if (prev == null || prev.isEmpty) return;
        final skipped = newlySkippedEffectBar(prev, bars);
        if (skipped != null && mounted) {
          ToastUtils.show(context, effectSkippedMessage(skipped));
        }
      },
    );

    // Sync audio player instances whenever the track list changes (import, delete, etc.)
    ref.listen<List<AudioTrackModel>>(
      videoEditorProvider.select((s) => s.audioTracks),
      (prev, tracks) {
        _audioPlayerManager.syncTracks(tracks);
      },
    );

    // The texts' list keeps its identity through a position event, so this
    // runs on an edit, never thirty times a second during playback.
    ref.listen<List<TextOverlayModel>>(
      videoEditorProvider.select((s) => s.textOverlays),
      (prev, texts) => _fetchProjectFonts(texts),
    );

    ref.listen<VideoEditorState>(videoEditorProvider, (prev, state) {
      final stopAt = _transitionPlaybackStop;
      if (stopAt != null &&
          state.isPlaying &&
          state.currentPlaybackPosition >= stopAt) {
        _transitionPlaybackStop = null;
        ref.read(videoEditorProvider.notifier).setPlaying(false);
        return;
      }
      // Overlays and effect bars go on their own light channels, so unlike
      // the timeline they are pushed while playing and mid-drag too — an
      // overlay or a bar moved under the finger has to move on the canvas.
      unawaited(_syncNativeOverlays(state));
      unawaited(_syncNativeEffects(state));
      if (_canUseNativeTimelinePreview(state) && !state.isPlaying) {
        // Adding or retuning a transition costs nothing now — it is a shader
        // uniform, not a render — so there is no cache to schedule here.
        unawaited(_syncNativePreviewTimeline(state));
      }
    });

    // Recording mode follows the playhead (the take grows, the end pauses)
    // and stops its take when the video stops for any reason.
    ref.listen<double>(
      videoEditorProvider.select((s) => s.currentPlaybackPosition),
      (prev, position) => _recordController?.onPlayhead(position),
    );
    ref.listen<bool>(
      videoEditorProvider.select((s) => s.isPlaying),
      (prev, playing) {
        if (!playing) _recordController?.onPlaybackStopped();
      },
    );
    // Undo restores a whole earlier state, and several paths clear the open
    // tool: however the Record panel closes, the mode ends as Done would, or
    // the microphone stays open and the preview muted behind a closed panel.
    ref.listen<String?>(
      videoEditorProvider.select((s) => s.activeToolId),
      (prev, next) {
        if (prev == 'record' && next != 'record' && _recordController != null) {
          unawaited(_finishRecording());
        }
      },
    );

    // Sync audio players when scrubbing the timeline (while paused)
    ref.listen<double>(
      videoEditorProvider.select((s) => s.currentPlaybackPosition),
      (prev, currentPos) {
        if (!_followingEngine) _drawnPlayhead.value = currentPos;
        final state = ref.read(videoEditorProvider);
        if (!state.isPlaying) {
          // Deliberately no _syncNativePreviewTimeline here: the whole-state
          // listener above already runs on this change, and composing plus
          // encoding the timeline twice per gesture frame was a large part of
          // why dragging the playhead felt heavy.
          final parked = _engineParkedAt;
          _engineParkedAt = null;
          if (_canUseNativeTimelinePreview(state) && currentPos != parked) {
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

    // Captions mode: the same editor — its listeners above keep the engine,
    // the playhead and the overlays in step — with another face.
    if (_captionsMode) return _buildCaptionsMode(editorState);

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
                      child: _previewCanvas(),
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
