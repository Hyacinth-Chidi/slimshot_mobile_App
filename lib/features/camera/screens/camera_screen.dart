import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/draft_project.dart';
import '../../../core/services/draft_service.dart';
import '../../../core/services/media_picker_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_fonts.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/utils/held_work.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../core/widgets/dashed_frame_painter.dart';
import '../../video_editor/logic/project_draft.dart';
import '../logic/camera_controller.dart';
import '../logic/camera_files.dart';
import '../logic/camera_geometry.dart';
import '../logic/camera_roll.dart';
import '../logic/reaction.dart';
import '../logic/reaction_session.dart';
import '../services/camera_permissions.dart';
import '../services/method_channel_camera.dart';
import '../services/reaction_maker.dart';
import '../widgets/camera_controls.dart';
import '../widgets/reaction_frame.dart';
import '../widgets/shot_views.dart';

/// Opens the viewer on the camera's shots; answers a video to edit, or null.
typedef CameraRollOpener = Future<RollShot?> Function(BuildContext context, CameraRoll roll);

/// Hands a video to the editor.
typedef CameraEdit = void Function(BuildContext context, RollShot shot);

/// The lens the camera was last left on, so it opens there again.
const kCameraLensKey = 'camera_lens';

/// A swipe this far across the picture, and mostly across, changes mode.
const double kCameraModeSwipePx = 60;

/// The REACT layout last used, so the next reaction starts there.
const kReactLayoutKey = 'camera_react_layout';

const kReactionFailedMessage = 'The reaction could not be made.';
const kReactionVideoFailedMessage = "This can't be opened.";
const kReactionPickLabel = 'Select photo or video';
const kReactionAccessMessage = 'Allow access to your photos and videos';
const kReactionPickFailedMessage = 'Your photos and videos could not be opened';

/// The shape REACT's empty window takes before anything is chosen.
const double kReactionPlaceholderAspect = 9 / 16;

/// Picks the photo or video REACT reacts to: its path, or null.
typedef ReactionVideoPicker = Future<String?> Function(BuildContext context);

/// What Edit hands the editor for [shot]: a reaction opens as the two layers
/// it was made from — the draft it already has, when it was edited before,
/// so a second Edit does not throw that work away — while both its files are
/// there ([exists]); anything else, and a reaction missing one, opens as its
/// finished file, a project of one clip.
Future<Object> editorExtraFor(
  RollShot shot, {
  Future<bool> Function(String path)? exists,
  Future<DraftProject?> Function(String id)? savedDraft,
}) async {
  final take = shot.reaction;
  final there = exists ?? (path) => File(path).exists();
  if (take != null && await there(take.camera.path) && await there(take.video.path)) {
    final project = reactionProject(take);
    final draft = await (savedDraft ?? DraftService.getDraftById)(project.draftId!) ?? draftProjectFrom(project);
    if (draft != null) return draft;
  }
  return [XFile(shot.path)];
}

/// Makes the reaction from a finished take ([makeReaction]).
typedef ReactionMaking = Future<RollShot?> Function(
  ReactionRequest request, {
  void Function(double fraction)? onProgress,
  void Function(String message)? onWarning,
});

/// The camera, opened from Home: the picture fills the screen; ✕ at the top
/// left and the flash at the right; at the foot PHOTO · VIDEO · REACT, the
/// shutter and the flip. A photo is a tap; a video is a tap to start and a
/// tap to stop, with pause to rest and carry on in the same video. Pinch
/// zooms, a tap focuses, a sideways swipe changes mode. **Every shot is saved
/// the moment it is taken** — into the gallery's SlimShotAI album — and drops
/// onto the pile left of the shutter, as a phone's own camera does; the pile
/// opens the viewer ([CameraRollScreen]), where Edit hands a video to the
/// editor, which takes the camera's place.
///
/// REACT records you beside a video playing — split, or the video in a
/// window over you — and the reaction is made from the take afterwards
/// ([makeReaction]): one video for the gallery, two layers for the editor.
///
/// The screen stays upright — photos and videos are turned to the way the
/// phone is held natively — and the camera is the phone's for as long as the
/// screen is open (CameraX closes it while the app is away).
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.backend,
    this.permissions,
    this.newPath,
    this.openRoll,
    this.onEdit,
    this.loadFrame,
    this.pickReactionVideo,
    this.openReactionVideo,
    this.makeReaction,
  });

  final CameraBackend? backend;
  final CameraPermissions? permissions;
  final ShotPath? newPath;
  final CameraRollOpener? openRoll;
  final CameraEdit? onEdit;
  final VideoFrameLoader? loadFrame;
  final ReactionVideoPicker? pickReactionVideo;
  final ReactionVideoOpener? openReactionVideo;
  final ReactionMaking? makeReaction;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final CameraBackend _backend = widget.backend ?? MethodChannelCamera();
  late final CameraPermissions _permissions = widget.permissions ?? PluginCameraPermissions();
  late final AppLifecycleListener _lifecycle;

  CameraController? _controller;

  /// The camera's shots, newest first: the pile and the viewer.
  final CameraRoll _roll = CameraRoll();

  /// Null while the camera is being asked for.
  CameraAccess? _access;
  bool _viewing = false;

  double _pinchStartZoom = 1;
  bool _pinching = false;
  Offset _swipe = Offset.zero;

  Offset? _focusAt;
  int _focusTick = 0;
  int _blinkTick = 0;

  // REACT: the video reacted to, where it goes, and the take under way.
  String? _reactPath;
  ReactionVideo? _reactVideo;
  ReactionLayout _layout = ReactionLayout.topBottom;
  ReactionWindow _window = ReactionWindow.initial;
  bool _videoSoundOn = true;
  ReactionTakeSession? _take;
  bool _headphones = false;
  bool _stoppingTake = false;

  /// How far the reaction is made, while it is; null otherwise.
  double? _making;

  /// What holds the app while a reaction is made — the recording holds it
  /// through `this`.
  final Object _makingHold = Object();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _roll.addListener(_onRollChanged);
    unawaited(_roll.load(exists: (path) => File(path).exists()));
    unawaited(_rememberedLayout());
    unawaited(_start());
  }

  Future<void> _rememberedLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(kReactLayoutKey);
      final layout = ReactionLayout.values.where((l) => l.name == name).firstOrNull;
      if (layout != null && mounted) setState(() => _layout = layout);
    } catch (_) {
      // Not remembered: top and bottom.
    }
  }

  void _onRollChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    HeldWork.instance.release(this);
    HeldWork.instance.release(_makingHold);
    _take?.dispose();
    unawaited(_reactVideo?.dispose());
    final controller = _controller;
    controller?.removeListener(_onControllerChanged);
    controller?.dispose();
    _roll.removeListener(_onRollChanged);
    _roll.dispose();
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  Future<void> _start() async {
    final access = await _permissions.requestCamera();
    if (!mounted) return;
    setState(() => _access = access);
    if (access == CameraAccess.granted) await _openCamera();
  }

  Future<void> _openCamera() async {
    if (_controller == null) {
      final lens = await _rememberedLens();
      if (!mounted) return;
      final controller = CameraController(
        backend: _backend,
        newPath: widget.newPath ?? _newShotPath,
        allowMicrophone: _permissions.allowMicrophone,
        allowStorage: _permissions.allowStorage,
        initialLens: lens,
      );
      controller.addListener(_onControllerChanged);
      setState(() => _controller = controller);
    }
    await _controller!.open();
  }

  static Future<String> _newShotPath(String extension) async =>
      (await CameraFiles.open()).newShotPath(extension);

  Future<CameraLens> _rememberedLens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(kCameraLensKey) == CameraLens.front.name ? CameraLens.front : CameraLens.back;
    } catch (_) {
      return CameraLens.back;
    }
  }

  /// Back from the phone's settings with the camera allowed there.
  Future<void> _onResume() async {
    if (_access == null || _access == CameraAccess.granted) return;
    final access = await _permissions.cameraStatus();
    if (!mounted || access == _access) return;
    setState(() => _access = access);
    if (access == CameraAccess.granted) await _openCamera();
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    // A recording is work a tap on the home screen widget must not end.
    if (controller.isRecording) {
      HeldWork.instance.hold(this);
    } else {
      HeldWork.instance.release(this);
    }
    if (controller.status != CameraStatus.failed) {
      final message = controller.takeMessage();
      if (message != null) ToastUtils.show(context, message);
    }
    // A recording the camera ended by itself (the app left mid-take) is
    // kept like any other; a REACT take becomes its reaction.
    final ended = controller.takeEndedShot();
    if (ended != null) {
      final take = _take;
      if (take != null) {
        unawaited(_reactionEnded(take, ended));
      } else {
        unawaited(_keep(ended));
      }
    }
    setState(() {});
  }

  Future<void> _shutter() async {
    final controller = _controller;
    if (controller == null || _viewing || _making != null) return;
    if (controller.mode == CameraMode.react) return _reactShutter(controller);
    HapticFeedback.lightImpact();
    if (controller.mode == CameraMode.photo && !controller.busy) setState(() => _blinkTick++);
    final shot = await controller.shutter();
    if (shot != null && mounted) await _keep(shot);
  }

  /// Already saved by the camera; the roll remembers it, and it lands on the pile.
  Future<void> _keep(CameraShot shot) => _roll.add(RollShot(
        path: shot.path,
        uri: shot.uri,
        isVideo: shot is VideoShot,
        durationMs: shot is VideoShot ? shot.durationMs : 0,
        takenAt: DateTime.now(),
      ));

  Future<void> _openRoll() async {
    if (_viewing || _roll.shots.isEmpty) return;
    _viewing = true;
    HapticFeedback.selectionClick();
    final edit = await (widget.openRoll ?? _pushRoll)(context, _roll);
    _viewing = false;
    if (edit != null && mounted) (widget.onEdit ?? _openInEditor)(context, edit);
  }

  static Future<RollShot?> _pushRoll(BuildContext context, CameraRoll roll) =>
      context.push<RollShot>('/camera/roll', extra: roll);

  /// The editor takes the camera's place: Back from it is Home, and the
  /// camera is let go rather than left running under an edit. A reaction
  /// opens as the two layers it was made from — the draft it already has,
  /// when it was edited before — while both its files are there; otherwise
  /// the finished file is the project.
  static Future<void> _openInEditor(BuildContext context, RollShot shot) async {
    final extra = await editorExtraFor(shot);
    if (context.mounted) context.pushReplacement('/edit/video', extra: extra);
  }

  // ---- REACT ----

  /// Into REACT, at once, on the front camera, always empty: what to react
  /// to is chosen from the frame (or the shutter).
  Future<void> _enterReact() async {
    final controller = _controller;
    if (controller == null || !controller.canChangeMode) return;
    await controller.setMode(CameraMode.react, lens: CameraLens.front);
  }

  /// Out of REACT: what was chosen is let go — the next REACT starts empty
  /// (the owner's call).
  void _leaveReact() => _clearReactVideo();

  /// Back to the empty frame; the player goes once the frame without it is
  /// drawn.
  void _clearReactVideo() {
    final video = _reactVideo;
    setState(() {
      _reactVideo = null;
      _reactPath = null;
    });
    if (video != null) _disposeAfterFrame(video);
  }

  /// A video's player goes once the frame without it is drawn: the picture
  /// still on screen holds it until then.
  void _disposeAfterFrame(ReactionVideo video) {
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(video.dispose()));
  }

  Future<bool> _pickReactVideo() async {
    final path = await (widget.pickReactionVideo ?? _pickFromGallery)(context);
    if (path == null || !mounted) return false;
    return _openReactVideo(path);
  }

  /// One photo or video from the gallery; a refusal or a failure is one line.
  static Future<String?> _pickFromGallery(BuildContext context) async {
    try {
      return (await MediaPickerService().pickOneMedia())?.path;
    } catch (error) {
      if (context.mounted) {
        ToastUtils.show(
          context,
          MediaPickerService.isPermissionError(error) ? kReactionAccessMessage : kReactionPickFailedMessage,
          isError: true,
        );
      }
      return null;
    }
  }

  Future<bool> _openReactVideo(String path) async {
    final video = await (widget.openReactionVideo ?? openReactionSource)(path);
    if (!mounted) {
      unawaited(video?.dispose());
      return false;
    }
    if (video == null) {
      ToastUtils.show(context, kReactionVideoFailedMessage, isError: true);
      return false;
    }
    await video.setVolume(_videoSoundOn ? 1 : 0);
    final old = _reactVideo;
    setState(() {
      _reactVideo = video;
      _reactPath = path;
      _window = _window.fittedFor(video.aspectRatio);
    });
    if (old != null) _disposeAfterFrame(old);
    return true;
  }

  Future<void> _changeReactVideo() async {
    if (_take != null) return;
    HapticFeedback.selectionClick();
    await _pickReactVideo();
  }

  Future<void> _cycleLayout() async {
    if (_take != null) return;
    HapticFeedback.selectionClick();
    final next = ReactionLayout.values[(_layout.index + 1) % ReactionLayout.values.length];
    setState(() => _layout = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kReactLayoutKey, next.name);
    } catch (_) {
      // Not remembered: the next REACT starts on top and bottom.
    }
  }

  Future<void> _toggleVideoSound() async {
    if (_take != null) return;
    HapticFeedback.selectionClick();
    setState(() => _videoSoundOn = !_videoSoundOn);
    await _reactVideo?.setVolume(_videoSoundOn ? 1 : 0);
  }

  /// Starts a take, or ends the one under way; with nothing chosen yet, asks.
  Future<void> _reactShutter(CameraController controller) async {
    if (_take != null) {
      debugPrint('REACT: the take stops: the shutter or Back');
      return _stopReaction();
    }
    final video = _reactVideo;
    if (controller.busy) return;
    if (video == null) {
      await _pickReactVideo();
      return;
    }
    HapticFeedback.lightImpact();
    // Decided when the take starts: whether the microphone will hear the video.
    _headphones = await _backend.headphonesConnected();
    if (!mounted) return;
    final take = ReactionTakeSession(
      camera: controller,
      player: video,
      onVideoEnded: () {
        debugPrint('REACT: the take stops: the video ended');
        unawaited(_stopReaction());
      },
    );
    setState(() => _take = take);
    if (!await take.start() && mounted) setState(() => _take = null);
  }

  Future<void> _pauseOrResume() async {
    HapticFeedback.selectionClick();
    final take = _take;
    if (take != null) {
      await take.pauseOrResume();
    } else {
      await _controller?.pauseOrResume();
    }
  }

  Future<void> _stopReaction() async {
    final take = _take;
    if (take == null || _stoppingTake) return;
    _stoppingTake = true;
    final recording = await take.stop();
    _stoppingTake = false;
    if (!mounted) return;
    setState(() => _take = null);
    if (recording != null) await _makeReaction(recording);
  }

  /// The app left mid-take: what was recorded becomes the reaction.
  Future<void> _reactionEnded(ReactionTakeSession take, CameraShot shot) async {
    debugPrint('REACT: the take stops: the camera ended the recording');
    final recording = await take.endedBy(shot);
    if (!mounted) return;
    setState(() => _take = null);
    if (recording != null) await _makeReaction(recording);
  }

  /// The take becomes the reaction: the camera is let go while the editor's
  /// engine renders it, and the reaction lands on the pile. A reaction that
  /// cannot be made says so, and the take itself is kept.
  Future<void> _makeReaction(ReactionRecording recording) async {
    final controller = _controller;
    final path = _reactPath;
    if (controller == null || path == null) return;
    final toGallery = await controller.galleryAllowed();
    if (!mounted) return;
    HeldWork.instance.hold(_makingHold);
    setState(() => _making = 0);
    await controller.close();
    RollShot? shot;
    try {
      shot = await (widget.makeReaction ?? _engineMake)(
        ReactionRequest(
          recording: recording,
          videoPath: path,
          layout: _layout,
          window: _window,
          micHearsVideo: videoSoundReachesMicrophone(
            headphones: _headphones,
            videoSoundOn: _videoSoundOn && !(_reactVideo?.isPhoto ?? false),
          ),
          toGallery: toGallery,
        ),
        onProgress: (fraction) {
          if (mounted) setState(() => _making = fraction);
        },
        onWarning: (message) {
          if (mounted) ToastUtils.show(context, message, isWarning: true);
        },
      );
    } catch (error) {
      debugPrint('REACT: the reaction could not be made: $error');
    }
    HeldWork.instance.release(_makingHold);
    if (!mounted) return;
    setState(() => _making = null);
    if (shot != null) {
      await _roll.add(shot);
    } else {
      ToastUtils.show(context, kReactionFailedMessage, isError: true);
      await _roll.add(RollShot(
        path: recording.cameraPath,
        isVideo: true,
        durationMs: recording.durationMs,
        takenAt: DateTime.now(),
      ));
    }
    unawaited(_reactVideo?.seekTo(0));
    if (mounted) await controller.open();
  }

  Future<RollShot?> _engineMake(
    ReactionRequest request, {
    void Function(double fraction)? onProgress,
    void Function(String message)? onWarning,
  }) =>
      makeReaction(
        request,
        EngineReactionRenderer(camera: _backend),
        onProgress: onProgress,
        onWarning: onWarning,
      );

  Future<void> _flip() async {
    final controller = _controller;
    if (controller == null) return;
    HapticFeedback.selectionClick();
    await controller.flip();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kCameraLensKey, controller.lens.name);
    } catch (_) {
      // Not remembered: the camera opens on the back lens next time.
    }
  }

  void _focus(Offset tap, Size screen) {
    final controller = _controller;
    final info = controller?.info;
    if (controller == null || info == null || controller.status != CameraStatus.ready) return;
    final width = info.previewWidth;
    final height = info.previewHeight;
    if (width == null || height == null) return;
    // In REACT the camera fills its place in the frame, not the screen.
    var area = Offset.zero & screen;
    if (controller.mode == CameraMode.react) {
      final frame = reactionFrameOn(screen);
      area = ReactionFrame.cameraPlace(
        layout: _layout,
        window: _window,
        videoAspect: _reactAspect,
        frame: frame.size,
      ).shift(frame.topLeft);
      if (!area.contains(tap)) return;
    }
    final point = focusPointFor(tap - area.topLeft, area.size, displayedPreviewSize(width, height, info.rotation));
    if (point == null) return;
    setState(() {
      _focusAt = tap;
      _focusTick++;
    });
    unawaited(controller.focusAt(point));
  }

  void _onScaleStart(ScaleStartDetails details) {
    _pinching = details.pointerCount >= 2;
    _pinchStartZoom = _controller?.zoom ?? 1;
    _swipe = Offset.zero;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final controller = _controller;
    final info = controller?.info;
    if (controller == null || info == null) return;
    if (details.pointerCount >= 2) {
      if (!_pinching) {
        // A second finger joined: the pinch measures from here.
        _pinching = true;
        _pinchStartZoom = controller.zoom;
      }
      unawaited(controller.zoomTo(zoomAfterPinch(
        start: _pinchStartZoom,
        scale: details.scale,
        min: info.minZoom,
        max: info.maxZoom,
      )));
      setState(() {});
    } else if (!_pinching) {
      _swipe += details.focalPointDelta;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final controller = _controller;
    final swipe = _swipe;
    final pinched = _pinching;
    _pinching = false;
    _swipe = Offset.zero;
    if (pinched) {
      setState(() {});
      return;
    }
    if (controller == null || !controller.canChangeMode) return;
    if (swipe.dx.abs() < kCameraModeSwipePx || swipe.dx.abs() < swipe.dy.abs() * 1.5) return;
    // Left brings the mode to the right of the chosen one, as a list scrolls.
    const modes = CameraMode.values;
    final index = (modes.indexOf(controller.mode) + (swipe.dx < 0 ? 1 : -1)).clamp(0, modes.length - 1);
    final next = modes[index];
    if (next != controller.mode) _setMode(next);
  }

  void _setMode(CameraMode mode) {
    final controller = _controller;
    if (controller == null || mode == controller.mode || !controller.canChangeMode) return;
    HapticFeedback.selectionClick();
    if (mode == CameraMode.react) {
      unawaited(_enterReact());
      return;
    }
    if (controller.mode == CameraMode.react) _leaveReact();
    unawaited(controller.setMode(mode));
  }

  /// Back while recording stops it, and the review takes what was kept;
  /// otherwise Back leaves.
  void _onBack() {
    if (_controller?.isRecording ?? false) unawaited(_shutter());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final recording = controller?.isRecording ?? false;
    final making = _making;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: !recording && making == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _picture(controller),
              const _Shades(),
              SafeArea(child: _controls(controller)),
              if (making != null) _MakingReaction(progress: making),
            ],
          ),
        ),
      ),
    );
  }

  Widget _picture(CameraController? controller) {
    final info = controller?.info;
    final showing = controller != null &&
        info != null &&
        (controller.status == CameraStatus.ready || controller.status == CameraStatus.opening);
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        return GestureDetector(
          key: const ValueKey('camera_picture'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _focus(details.localPosition, screen),
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (controller?.mode == CameraMode.react)
                _reactPicture(screen, showing ? info : null)
              else if (showing)
                CameraPreviewTexture(info: info, screen: screen),
              if (_focusAt != null) CameraFocusRing(key: ValueKey(_focusTick), at: _focusAt!),
              // A photo's blink, so a tap is seen to have taken one.
              IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_blinkTick),
                  tween: Tween(begin: _blinkTick == 0 ? 0 : 0.6, end: 0),
                  duration: const Duration(milliseconds: 180),
                  builder: (context, value, _) => ColoredBox(
                    color: AppColors.background.withValues(alpha: value),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// REACT's frame, as the file will be: 9:16 on the screen, you and the
  /// video where the layout puts you.
  /// The shape of what is reacted to, or of the empty window before it.
  double get _reactAspect => _reactVideo?.aspectRatio ?? kReactionPlaceholderAspect;

  Widget _reactPicture(Size screen, CameraInfo? info) {
    final video = _reactVideo;
    final frame = reactionFrameOn(screen);
    return Positioned.fromRect(
      rect: frame,
      child: ReactionFrame(
        key: const ValueKey('reaction_frame'),
        layout: _layout,
        window: _window,
        videoAspect: _reactAspect,
        video: video?.picture() ?? const SizedBox.shrink(),
        placeholder: video == null ? _ReactPlaceholder(onTap: () => unawaited(_pickReactVideo())) : null,
        camera: (place) => info == null
            ? const SizedBox.expand()
            : CameraPreviewTexture(info: info, screen: place),
        windowMovable: _take == null,
        onWindowChanged: (window) => setState(() => _window = window),
      ),
    );
  }

  Widget _controls(CameraController? controller) {
    final recording = controller?.recording ?? RecordingState.idle;
    final isRecording = recording != RecordingState.idle;
    final ready = controller?.status == CameraStatus.ready;
    final info = controller?.info;
    final zoom = controller?.zoom ?? 1;
    final showZoom = ready && (_pinching || (zoom - 1).abs() > 0.05);
    final notice = _notice(controller);
    return Stack(
      children: [
        if (!isRecording)
          Positioned(
            top: 4,
            left: 8,
            child: CameraRoundButton(
              key: const ValueKey('camera_close'),
              icon: LucideIcons.x,
              tooltip: 'Close',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        if (isRecording)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: CameraRecordingPill(
                milliseconds: controller!.recordedMs,
                paused: recording == RecordingState.paused,
              ),
            ),
          ),
        if (ready && info != null && info.hasFlash)
          Positioned(
            top: 4,
            right: 8,
            child: _flashButton(controller!),
          ),
        if (controller?.mode == CameraMode.react && !isRecording)
          Positioned(
            top: 60,
            right: 8,
            child: _reactTools(),
          ),
        if (notice != null) Center(child: notice),
        Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 30,
                child: showZoom
                    ? CameraPill(
                        key: const ValueKey('camera_zoom'),
                        onTap: () => unawaited(controller?.zoomTo(1)),
                        child: Text('${zoom.toStringAsFixed(1)}×'),
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              // Kept laid out while recording so the shutter does not move.
              IgnorePointer(
                ignoring: isRecording,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: isRecording || controller == null ? 0 : 1,
                  child: CameraModeSwitch(
                    mode: controller?.mode ?? CameraMode.photo,
                    enabled: controller?.canChangeMode ?? false,
                    onSelect: _setMode,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SizedBox(
                    width: 64,
                    child: isRecording
                        ? CameraRoundButton(
                            key: const ValueKey('camera_pause'),
                            icon: LucideIcons.pause,
                            recordDot: recording == RecordingState.paused,
                            tooltip: recording == RecordingState.paused ? 'Resume' : 'Pause',
                            size: 48,
                            onTap: () => unawaited(_pauseOrResume()),
                          )
                        : Center(
                            child: CameraRollPile(
                              shots: _roll.shots,
                              onTap: _openRoll,
                              loadFrame: widget.loadFrame,
                            ),
                          ),
                  ),
                  CameraShutter(
                    mode: controller?.mode ?? CameraMode.photo,
                    recording: recording,
                    enabled: ready && !(controller?.busy ?? true) && _making == null,
                    onTap: _shutter,
                  ),
                  SizedBox(
                    width: 64,
                    child: !isRecording && (controller?.canFlip ?? false)
                        ? CameraRoundButton(
                            key: const ValueKey('camera_flip'),
                            icon: LucideIcons.switchCamera,
                            tooltip: 'Flip camera',
                            size: 48,
                            onTap: _flip,
                          )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// REACT's own tools, down the right: the layout (a tap moves to the
  /// next), the video's sound, and something else to react to.
  Widget _reactTools() {
    final video = _reactVideo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CameraRoundButton(
          key: const ValueKey('react_layout'),
          icon: switch (_layout) {
            ReactionLayout.topBottom => LucideIcons.rows,
            ReactionLayout.sideBySide => LucideIcons.columns,
            ReactionLayout.float => LucideIcons.pictureInPicture2,
          },
          tooltip: switch (_layout) {
            ReactionLayout.topBottom => 'Top and bottom',
            ReactionLayout.sideBySide => 'Side by side',
            ReactionLayout.float => 'Window',
          },
          onTap: () => unawaited(_cycleLayout()),
        ),
        if (video != null && !video.isPhoto) ...[
          const SizedBox(height: 6),
          CameraRoundButton(
            key: const ValueKey('react_sound'),
            icon: _videoSoundOn ? LucideIcons.volume2 : LucideIcons.volumeX,
            tooltip: _videoSoundOn ? 'Video sound on' : 'Video sound off',
            onTap: () => unawaited(_toggleVideoSound()),
          ),
        ],
        if (video != null) ...[
          const SizedBox(height: 6),
          CameraRoundButton(
            key: const ValueKey('react_change_video'),
            icon: LucideIcons.replace,
            tooltip: 'Change',
            onTap: () => unawaited(_changeReactVideo()),
          ),
          const SizedBox(height: 6),
          CameraRoundButton(
            key: const ValueKey('react_remove'),
            icon: LucideIcons.x,
            tooltip: 'Remove',
            onTap: () {
              if (_take != null) return;
              HapticFeedback.selectionClick();
              _clearReactVideo();
            },
          ),
        ],
      ],
    );
  }

  Widget _flashButton(CameraController controller) {
    final flash = controller.flash;
    return CameraRoundButton(
      key: const ValueKey('camera_flash'),
      icon: flash == CameraFlash.off ? LucideIcons.zapOff : LucideIcons.zap,
      tooltip: switch (flash) {
        CameraFlash.off => 'Flash off',
        CameraFlash.auto => 'Flash auto',
        CameraFlash.on => controller.mode == CameraMode.photo ? 'Flash on' : 'Light on',
      },
      chosen: flash == CameraFlash.on,
      badge: flash == CameraFlash.auto ? 'A' : null,
      onTap: () {
        HapticFeedback.selectionClick();
        unawaited(controller.cycleFlash());
      },
    );
  }

  /// The camera not in use: refused, refused for good, or failed — the
  /// reason and the one thing that can be done about it.
  Widget? _notice(CameraController? controller) {
    final access = _access;
    if (access == CameraAccess.denied || access == CameraAccess.blocked) {
      final blocked = access == CameraAccess.blocked;
      return _Notice(
        key: const ValueKey('camera_notice'),
        message: 'Camera access is off.',
        action: blocked ? 'Open settings' : 'Allow camera',
        onAction: blocked ? _permissions.openSettings : _start,
      );
    }
    if (controller != null && controller.status == CameraStatus.failed) {
      return _Notice(
        key: const ValueKey('camera_notice'),
        message: controller.message ?? kCameraUnavailableMessage,
        action: 'Try again',
        onAction: controller.open,
      );
    }
    return null;
  }
}

/// The take becoming its reaction: the frame dimmed, a ring filling.
class _MakingReaction extends StatelessWidget {
  const _MakingReaction({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        key: const ValueKey('react_making'),
        color: AppColors.background.withValues(alpha: 0.72),
        child: Center(
          child: SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress <= 0 ? null : progress,
                    strokeWidth: 4,
                    color: AppColors.primaryStart,
                    backgroundColor: AppColors.textPrimary.withValues(alpha: 0.15),
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    fontFamily: kInterfaceFontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Darkens the picture under the controls, top and foot, so white glyphs
/// read over a bright sky.
class _Shades extends StatelessWidget {
  const _Shades();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.background.withValues(alpha: 0.45), Colors.transparent],
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: 240,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, AppColors.background.withValues(alpha: 0.6)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.message, required this.action, required this.onAction});

  final String message;
  final String action;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.cameraOff, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: kInterfaceFontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => unawaited(onAction()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryStart,
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              action,
              style: const TextStyle(fontFamily: kInterfaceFontFamily, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// The video's place before anything is chosen: a dashed frame that opens
/// the picker.
class _ReactPlaceholder extends StatelessWidget {
  const _ReactPlaceholder({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('react_pick'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: CustomPaint(
          foregroundPainter: DashedFramePainter(
            colour: AppColors.lilac.withValues(alpha: 0.45),
            radius: 14,
            strokeWidth: 1.5,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.imagePlus, color: AppColors.textPrimary, size: 28),
                      SizedBox(height: 8),
                      Text(
                        kReactionPickLabel,
                        style: TextStyle(
                          fontFamily: kInterfaceFontFamily,
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
