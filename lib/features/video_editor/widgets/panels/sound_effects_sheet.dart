import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/lucide_icons.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../sound_library/data/catalog_models.dart';
import '../../../sound_library/data/sound_library.dart';
import '../../../sound_library/sound_effects_controller.dart';

/// The sound effects library: pills from the server (Downloaded first), and
/// rows of cover, title, length and a **+**. A tap on a row listens — the
/// download is the preview — and the + puts the sound on the timeline and
/// closes the sheet.
///
/// Layout only: every rule is [SoundEffectsController]'s. The sheet owns the
/// controller and disposes it on close.
class SoundEffectsSheet extends StatefulWidget {
  const SoundEffectsSheet({
    super.key,
    required this.controller,
    required this.onAdd,
  });

  final SoundEffectsController controller;
  final void Function(LibrarySound sound) onAdd;

  @override
  State<SoundEffectsSheet> createState() => _SoundEffectsSheetState();
}

class _SoundEffectsSheetState extends State<SoundEffectsSheet> {
  static const double _kHeightFraction = 0.7;
  static const double _kEdge = 16;

  SoundEffectsController get _c => widget.controller;
  late final StreamSubscription<SoundSheetNotice> _notices;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _notices = _c.notices.listen(_tell);
    unawaited(_c.open());
  }

  @override
  void dispose() {
    _notices.cancel();
    _c.removeListener(_changed);
    _c.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _tell(SoundSheetNotice notice) {
    if (!mounted) return;
    ToastUtils.show(
      context,
      switch (notice.kind) {
        SoundSheetNoticeKind.downloadFailed => "Couldn't download ${notice.title}",
        SoundSheetNoticeKind.unavailable => "${notice.title} isn't available",
      },
      isError: true,
    );
  }

  Future<void> _add(CatalogSound sound) async {
    final entry = await _c.add(sound);
    if (entry == null || !mounted) return;
    widget.onAdd(entry);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * _kHeightFraction,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _handle(),
              _pills(),
              const SizedBox(height: 8),
              if (_c.offline) _offlineLine(),
              Expanded(child: _list()),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _handle() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 12, bottom: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  /// The dashboard decides how many pills there are, so they scroll.
  Widget _pills() {
    final pills = _c.pills;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        itemCount: pills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final pill = pills[i];
          final active = pill == _c.selected;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: active ? null : () => unawaited(_c.select(pill)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.highlight : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _c.pillName(pill),
                maxLines: 1,
                style: TextStyle(
                  color: active ? AppColors.textPrimary : AppColors.textSecondary,
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

  Widget _offlineLine() => Padding(
        padding: const EdgeInsets.fromLTRB(_kEdge, 0, 8, 4),
        child: Row(
          children: [
            const Icon(LucideIcons.wifiOff, color: AppColors.textSecondary, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "You're offline",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_c.retry()),
              child: const Text(
                'Retry',
                style: TextStyle(color: AppColors.primaryStart, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _list() {
    final sounds = _c.sounds;
    final Widget body;
    if (_c.loading && sounds.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [for (var i = 0; i < 3; i++) const _SkeletonRow()],
      );
    } else if (sounds.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(
              child: Text(
                'No sounds here yet.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
          ),
        ],
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < n.metrics.viewportDimension) _askForMore();
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: sounds.length + (_c.hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= sounds.length) {
              // The end of what has loaded: ask for more as it comes in.
              _askForMore();
              return const _SkeletonRow();
            }
            return _row(sounds[i]);
          },
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primaryStart,
      backgroundColor: AppColors.surface,
      onRefresh: _c.refresh,
      child: body,
    );
  }

  /// The next page, after this frame: asking marks the list as loading,
  /// which rebuilds it, and a rebuild cannot be asked for from inside a
  /// build or a layout.
  void _askForMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_c.loadMore());
    });
  }

  Widget _row(CatalogSound sound) {
    final kept = _c.librarySound(sound.id);
    final progress = _c.progressOf(sound.id);
    final adding = _c.addingId == sound.id;
    final duration = formatSoundDuration(sound.durationMs);
    final unreachable = _c.offline && kept == null;
    return Opacity(
      opacity: unreachable ? 0.4 : 1,
      child: InkWell(
        onTap: () => unawaited(_c.tapRow(sound)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_kEdge, 8, 4, 8),
          child: Row(
            children: [
              _SoundCover(
                coverPath: kept?.coverPath,
                coverUrl: sound.coverUrl,
                listening: progress != null && !adding,
                progress: progress,
                playing: _c.playingId == sound.id,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sound.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (duration != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        duration,
                        maxLines: 1,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: adding && progress != null
                    ? Center(child: _Ring(progress: progress))
                    : IconButton(
                        key: ValueKey('sfx_add_${sound.id}'),
                        onPressed: unreachable ? null : () => unawaited(_add(sound)),
                        icon: const Icon(LucideIcons.plus, size: 20),
                        color: AppColors.textPrimary,
                        disabledColor: AppColors.textSecondary,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sound's cover — the downloaded one, the server's, or the app's own —
/// with a ring while a listen downloads and a pause sign while it plays.
class _SoundCover extends StatelessWidget {
  const _SoundCover({
    required this.coverPath,
    required this.coverUrl,
    required this.listening,
    required this.progress,
    required this.playing,
  });

  final String? coverPath;
  final String? coverUrl;
  final bool listening;
  final double? progress;
  final bool playing;

  static const double _kSize = 48;

  @override
  Widget build(BuildContext context) {
    final Widget picture;
    if (coverPath != null) {
      picture = Image.file(
        File(coverPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _DefaultCover(),
      );
    } else if (coverUrl != null) {
      picture = Image.network(
        coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _DefaultCover(),
        loadingBuilder: (_, child, loading) =>
            loading == null ? child : const _DefaultCover(),
      );
    } else {
      picture = const _DefaultCover();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _kSize,
        height: _kSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            picture,
            if (listening || playing)
              Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: listening
                    ? _Ring(progress: progress ?? 0)
                    : const Icon(LucideIcons.pause, color: AppColors.textPrimary, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

/// A sound with no cover of its own.
class _DefaultCover extends StatelessWidget {
  const _DefaultCover();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: AppColors.previewStage,
        child: Center(
          child: Icon(LucideIcons.music, color: AppColors.textPrimary, size: 20),
        ),
      );
}

class _Ring extends StatelessWidget {
  const _Ring({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          // A determinate ring from the first byte; before it, a spinner.
          value: progress > 0 ? progress : null,
          strokeWidth: 2.5,
          color: AppColors.primaryStart,
          backgroundColor: Colors.white24,
        ),
      );
}

/// A row still on its way.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.6,
                    child: Container(height: 12, color: AppColors.surface),
                  ),
                  const SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: 0.2,
                    child: Container(height: 10, color: AppColors.surface),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
