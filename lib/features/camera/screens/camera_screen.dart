import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_fonts.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/utils/held_work.dart';
import '../../../core/utils/toast_utils.dart';
import '../logic/camera_controller.dart';
import '../logic/camera_files.dart';
import '../logic/camera_geometry.dart';
import '../logic/camera_roll.dart';
import '../services/camera_permissions.dart';
import '../services/method_channel_camera.dart';
import '../widgets/camera_controls.dart';
import '../widgets/shot_views.dart';

/// Opens the viewer on the camera's shots; answers a video to edit, or null.
typedef CameraRollOpener = Future<RollShot?> Function(BuildContext context, CameraRoll roll);

/// Hands a video to the editor.
typedef CameraEdit = void Function(BuildContext context, RollShot shot);

/// The lens the camera was last left on, so it opens there again.
const kCameraLensKey = 'camera_lens';

/// A swipe this far across the picture, and mostly across, changes mode.
const double kCameraModeSwipePx = 60;

/// The camera, opened from Home: the picture fills the screen; ✕ at the top
/// left and the flash at the right; at the foot PHOTO · VIDEO, the shutter
/// and the flip. A photo is a tap; a video is a tap to start and a tap to
/// stop, with pause to rest and carry on in the same video. Pinch zooms, a
/// tap focuses, a sideways swipe changes mode. **Every shot is saved the
/// moment it is taken** — into the gallery's SlimShotAI album — and drops onto
/// the pile left of the shutter, as a phone's own camera does; the pile opens
/// the viewer ([CameraRollScreen]), where Edit hands a video to the editor,
/// which takes the camera's place.
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
  });

  final CameraBackend? backend;
  final CameraPermissions? permissions;
  final ShotPath? newPath;
  final CameraRollOpener? openRoll;
  final CameraEdit? onEdit;
  final VideoFrameLoader? loadFrame;

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

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _roll.addListener(_onRollChanged);
    unawaited(_roll.load(exists: (path) => File(path).exists()));
    unawaited(_start());
  }

  void _onRollChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    HeldWork.instance.release(this);
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
    // kept like any other.
    final ended = controller.takeEndedShot();
    if (ended != null) unawaited(_keep(ended));
    setState(() {});
  }

  Future<void> _shutter() async {
    final controller = _controller;
    if (controller == null || _viewing) return;
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
  /// camera is let go rather than left running under an edit.
  static void _openInEditor(BuildContext context, RollShot shot) {
    context.pushReplacement('/edit/video', extra: [XFile(shot.path)]);
  }

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
    final point = focusPointFor(tap, screen, displayedPreviewSize(width, height, info.rotation));
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
    final next = swipe.dx < 0 ? CameraMode.video : CameraMode.photo;
    if (next != controller.mode) _setMode(next);
  }

  void _setMode(CameraMode mode) {
    HapticFeedback.selectionClick();
    unawaited(_controller?.setMode(mode));
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: !recording,
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
              if (showing) CameraPreviewTexture(info: info, screen: screen),
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
                            onTap: () {
                              HapticFeedback.selectionClick();
                              unawaited(controller?.pauseOrResume());
                            },
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
                    enabled: ready && !(controller?.busy ?? true),
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

  Widget _flashButton(CameraController controller) {
    final flash = controller.flash;
    return CameraRoundButton(
      key: const ValueKey('camera_flash'),
      icon: flash == CameraFlash.off ? LucideIcons.zapOff : LucideIcons.zap,
      tooltip: switch (flash) {
        CameraFlash.off => 'Flash off',
        CameraFlash.auto => 'Flash auto',
        CameraFlash.on => controller.mode == CameraMode.video ? 'Light on' : 'Flash on',
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
