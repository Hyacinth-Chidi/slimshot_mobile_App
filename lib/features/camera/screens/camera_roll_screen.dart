import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/media_save_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../core/widgets/discard_dialog.dart';
import '../logic/camera_files.dart';
import '../logic/camera_roll.dart';
import '../services/method_channel_camera.dart';
import '../widgets/shot_views.dart';

/// Deletes a shot from wherever it was saved; false where the phone would not.
typedef ShotDeleter = Future<bool> Function(RollShot shot);

/// Hands a file to the share sheet; true unless it was closed unused.
typedef ShotSharer = Future<bool> Function(String path);

/// Plays a video shot; tests give a stand-in.
typedef ShotVideoBuilder = Widget Function(String path, double footHeight);

/// A swipe this far past the oldest shot goes back to the camera.
const double kBackToCameraOverscroll = 48;

const kDeleteFailedMessage = "Couldn't delete it.";

/// The camera's shots, opened from the pile beside the shutter: one at a
/// time, newest first, with every shot in a strip along the foot.
///
/// Swiping left goes to older shots, and one more swipe past the oldest goes
/// back to the camera, as Back and ✕ do. Delete sits see-through at the
/// bottom left and asks first — the shot goes from the gallery too. Share
/// hands it over. **Edit is for videos only** (the owner's call): it closes the
/// viewer answering the shot, and the camera hands it to the editor.
class CameraRollScreen extends StatefulWidget {
  const CameraRollScreen({
    super.key,
    required this.roll,
    this.deleteShot,
    this.share,
    this.videoView,
    this.loadFrame,
  });

  final CameraRoll roll;
  final ShotDeleter? deleteShot;
  final ShotSharer? share;
  final ShotVideoBuilder? videoView;
  final VideoFrameLoader? loadFrame;

  @override
  State<CameraRollScreen> createState() => _CameraRollScreenState();
}

class _CameraRollScreenState extends State<CameraRollScreen> {
  final PageController _pages = PageController();
  final ScrollController _strip = ScrollController();
  int _index = 0;
  double _overscroll = 0;
  bool _leaving = false;

  static const double _tile = 54;
  static const double _tileGap = 6;

  /// The foot's controls — the actions and the strip — that a video's own bar
  /// sits above.
  static const double _footHeight = 150;

  List<RollShot> get _shots => widget.roll.shots;

  @override
  void initState() {
    super.initState();
    widget.roll.addListener(_onRollChanged);
  }

  @override
  void dispose() {
    widget.roll.removeListener(_onRollChanged);
    _pages.dispose();
    _strip.dispose();
    super.dispose();
  }

  void _onRollChanged() {
    if (!mounted) return;
    if (_shots.isEmpty) {
      _leave();
      return;
    }
    setState(() => _index = _index.clamp(0, _shots.length - 1));
  }

  void _leave([RollShot? edit]) {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).pop(edit);
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _keepInStrip(index);
  }

  void _keepInStrip(int index) {
    if (!_strip.hasClients) return;
    final position = _strip.position;
    final centre = 16 + index * (_tile + _tileGap) + _tile / 2 - position.viewportDimension / 2;
    unawaited(_strip.animateTo(
      centre.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    ));
  }

  void _show(int index) {
    HapticFeedback.selectionClick();
    _pages.jumpToPage(index);
  }

  /// Past the oldest shot, a further swipe left goes back to the camera.
  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is OverscrollNotification &&
        notification.overscroll > 0 &&
        _index == _shots.length - 1) {
      _overscroll += notification.overscroll;
      if (_overscroll > kBackToCameraOverscroll) _leave();
    } else if (notification is ScrollEndNotification || notification is ScrollStartNotification) {
      _overscroll = 0;
    }
    return false;
  }

  Future<void> _delete() async {
    if (_shots.isEmpty) return;
    final shot = _shots[_index];
    if (!await confirmDelete(context, isVideo: shot.isVideo)) return;
    final deleted = await (widget.deleteShot ?? _deleteFromPhone)(shot);
    if (!mounted) return;
    if (!deleted) {
      ToastUtils.show(context, kDeleteFailedMessage, isError: true);
      return;
    }
    await widget.roll.remove(shot);
  }

  static Future<bool> _deleteFromPhone(RollShot shot) async {
    final uri = shot.uri;
    if (uri != null && !await MethodChannelCamera().deleteShot(uri)) return false;
    await (await CameraFiles.open()).delete(cameraFilesOf(shot));
    return uri != null || !await File(shot.path).exists();
  }

  Future<void> _share() async {
    if (_shots.isEmpty) return;
    await (widget.share ?? _shareFile)(_shots[_index].path);
  }

  static Future<bool> _shareFile(String path) => MediaSaveService.shareFiles([path]);

  @override
  Widget build(BuildContext context) {
    final shots = _shots;
    final current = shots.isEmpty ? null : shots[_index.clamp(0, shots.length - 1)];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: PageView.builder(
                key: const ValueKey('camera_roll_pages'),
                controller: _pages,
                itemCount: shots.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _page(shots[index], active: index == _index),
              ),
            ),
            const _FootShade(),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
                  child: _RoundAction(
                    key: const ValueKey('camera_roll_close'),
                    icon: LucideIcons.x,
                    label: 'Back to camera',
                    onTap: () => _leave(),
                  ),
                ),
              ),
            ),
            if (current != null)
              SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _RoundAction(
                              key: const ValueKey('camera_roll_delete'),
                              icon: LucideIcons.trash2,
                              label: 'Delete',
                              onTap: _delete,
                            ),
                            const Spacer(),
                            _RoundAction(
                              key: const ValueKey('camera_roll_share'),
                              icon: LucideIcons.share2,
                              label: 'Share',
                              onTap: _share,
                            ),
                            if (current.isVideo) ...[
                              const SizedBox(width: 12),
                              _RoundAction(
                                key: const ValueKey('camera_roll_edit'),
                                icon: LucideIcons.scissors,
                                label: 'Edit',
                                primary: true,
                                onTap: () => _leave(current),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: _tile,
                        child: ListView.separated(
                          key: const ValueKey('camera_roll_strip'),
                          controller: _strip,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: shots.length,
                          separatorBuilder: (context, index) => const SizedBox(width: _tileGap),
                          itemBuilder: (context, index) => _StripTile(
                            key: ValueKey('camera_roll_tile_$index'),
                            shot: shots[index],
                            size: _tile,
                            chosen: index == _index,
                            loadFrame: widget.loadFrame,
                            onTap: () => _show(index),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _page(RollShot shot, {required bool active}) {
    if (shot.isVideo) {
      // Only the shot on screen holds a player: a decoder per page would be
      // one per shot swiped past.
      if (!active) {
        return const Center(child: Icon(LucideIcons.play, size: 40, color: AppColors.textSecondary));
      }
      return KeyedSubtree(
        key: ValueKey('camera_roll_video_${shot.path}'),
        child: (widget.videoView ?? (path, foot) => ShotVideo(path: path, footHeight: foot))(shot.path, _footHeight),
      );
    }
    return Image.file(
      File(shot.path),
      key: ValueKey('camera_roll_photo_${shot.path}'),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) =>
          const Center(child: Icon(LucideIcons.imageOff, size: 40, color: AppColors.textSecondary)),
    );
  }
}

class _FootShade extends StatelessWidget {
  const _FootShade();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, AppColors.background.withValues(alpha: 0.75)],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round control over the picture: see-through dark, or the purple of the
/// step most shots go on to.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final FutureOr<void> Function() onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary ? AppColors.primaryStart : AppColors.background.withValues(alpha: 0.45),
            ),
            child: Icon(icon, size: 21, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _StripTile extends StatelessWidget {
  const _StripTile({
    super.key,
    required this.shot,
    required this.size,
    required this.chosen,
    required this.onTap,
    this.loadFrame,
  });

  final RollShot shot;
  final double size;
  final bool chosen;
  final VoidCallback onTap;
  final VideoFrameLoader? loadFrame;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: chosen ? AppColors.primaryStart : AppColors.border,
            width: chosen ? 2.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ShotThumbnail(shot: shot, size: size, loadFrame: loadFrame),
        ),
      ),
    );
  }
}
