import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/lucide_icons.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../sound_library/data/catalog_models.dart';
import '../../../sound_library/data/sound_library.dart';
import '../../../sound_library/sound_library_controller.dart';

/// The sound effects library: pills from the server (Downloaded first), and
/// rows of cover, title, length and a **+**. A tap on a row listens — the
/// download is the preview — and the + puts the sound on the timeline and
/// closes the sheet.
///
/// Layout only: every rule is [SoundLibraryController]'s. The sheet owns the
/// controller and disposes it on close.
class SoundLibrarySheet extends StatefulWidget {
  const SoundLibrarySheet({
    super.key,
    required this.controller,
    required this.onAdd,
    this.onImport,
  });

  final SoundLibraryController controller;
  final void Function(LibrarySound sound) onAdd;

  /// The user's own file, beside the search. Music offers it; effects do not.
  final VoidCallback? onImport;

  @override
  State<SoundLibrarySheet> createState() => _SoundLibrarySheetState();
}

class _SoundLibrarySheetState extends State<SoundLibrarySheet> {
  static const double _kHeightFraction = 0.7;
  static const double _kEdge = 16;

  SoundLibraryController get _c => widget.controller;
  late final StreamSubscription<SoundSheetNotice> _notices;
  final TextEditingController _search = TextEditingController();

  /// One page per tab, so a sideways swipe on the list is a change of tab.
  late final PageController _pages = PageController(
    initialPage: _c.pills.indexOf(_c.selected).clamp(0, _c.pills.length - 1),
  );

  /// The tab a tap is sliding the list to. While it is set, the pages the
  /// slide passes are not opened — passing a tab is not choosing it.
  String? _sliding;

  /// Keys on the tabs, so the chosen one can be scrolled into view.
  final Map<String, GlobalKey> _tabKeys = {};
  String? _shownTab;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _notices = _c.notices.listen(_tell);
    unawaited(_c.open());
    WidgetsBinding.instance.addPostFrameCallback((_) => _followSelection());
  }

  @override
  void dispose() {
    _search.dispose();
    _pages.dispose();
    _notices.cancel();
    _c.removeListener(_changed);
    _c.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    // The tab can change without a swipe — the sheet opening on the first
    // category, a category vanishing back to Downloaded — and the pages and
    // the tab row follow it after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _followSelection());
  }

  void _followSelection() {
    if (!mounted) return;
    final selected = _c.selected;
    final index = _c.pills.indexOf(selected);
    if (index >= 0 &&
        _sliding == null &&
        _pages.hasClients &&
        !_pages.position.isScrollingNotifier.value &&
        (_pages.page ?? 0).round() != index) {
      _pages.jumpToPage(index);
    }
    if (selected != _shownTab) {
      _shownTab = selected;
      final tab = _tabKeys[selected]?.currentContext;
      if (tab != null) {
        unawaited(Scrollable.ensureVisible(
          tab,
          alignment: 0.5,
          duration: AppMotion.enter,
          curve: AppMotion.enterCurve,
        ));
      }
    }
  }

  /// A swipe settled on another tab.
  void _pageChanged(int index) {
    if (_sliding != null) return;
    final pills = _c.pills;
    if (index < 0 || index >= pills.length) return;
    final pill = pills[index];
    if (pill != _c.selected) unawaited(_c.select(pill));
  }

  /// A tap on a tab: choose it at once, then slide the list there.
  Future<void> _goTo(String pill) async {
    final index = _c.pills.indexOf(pill);
    if (index < 0) return;
    _sliding = pill;
    unawaited(_c.select(pill));
    try {
      if (_pages.hasClients) {
        await _pages.animateToPage(
          index,
          duration: AppMotion.enter,
          curve: AppMotion.enterCurve,
        );
      }
    } finally {
      if (_sliding == pill) _sliding = null;
    }
  }

  void _tell(SoundSheetNotice notice) {
    if (!mounted) return;
    ToastUtils.show(
      context,
      switch (notice.kind) {
        SoundSheetNoticeKind.downloadFailed => "Couldn't download ${notice.title}",
        SoundSheetNoticeKind.unavailable => "${notice.title} isn't available",
        SoundSheetNoticeKind.offline => 'No internet connection',
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
              _searchField(),
              const SizedBox(height: 12),
              _tabs(),
              const Divider(height: 1, color: Colors.white10),
              const SizedBox(height: 4),
              if (_c.offline) _offlineLine(),
              Expanded(child: _pager()),
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

  /// The search field, and Import beside it where the sheet offers one —
  /// the field takes the width that is left.
  Widget _searchField() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(LucideIcons.search, color: AppColors.textSecondary, size: 18),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: _c.setQuery,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Search',
                          hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.onImport != null) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: widget.onImport,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.music, color: AppColors.textPrimary, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Import',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  /// The categories as the audio library's tabs: words, the current one
  /// underlined. The dashboard decides how many there are, so they scroll.
  Widget _tabs() {
    final pills = _c.pills;
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        itemCount: pills.length,
        itemBuilder: (context, i) {
          final pill = pills[i];
          final active = pill == _c.selected;
          return GestureDetector(
            key: _tabKeys.putIfAbsent(pill, GlobalKey.new),
            behavior: HitTestBehavior.opaque,
            onTap: active ? null : () => unawaited(_goTo(pill)),
            child: Container(
              margin: const EdgeInsets.only(right: 20),
              padding: const EdgeInsets.only(bottom: 8),
              alignment: Alignment.bottomCenter,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? AppColors.textPrimary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                _c.pillName(pill),
                maxLines: 1,
                style: TextStyle(
                  color: active ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 15,
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

  /// The tabs' lists side by side: a swipe moves to the neighbouring tab,
  /// which slides in already showing what it last loaded.
  Widget _pager() {
    final pills = _c.pills;
    return PageView.builder(
      controller: _pages,
      itemCount: pills.length,
      onPageChanged: _pageChanged,
      itemBuilder: (context, i) => _list(pills[i]),
    );
  }

  Widget _list(String pill) {
    final live = pill == _c.selected;
    final sounds = _c.soundsFor(pill);
    final Widget body;
    if (live && _c.loading && sounds.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [for (var i = 0; i < 3; i++) const _SkeletonRow()],
      );
    } else if (sounds.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(
              child: Text(
                _c.searching ? 'No matching sounds.' : 'No sounds here yet.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
          ),
        ],
      );
    } else {
      final more = live && _c.hasMore;
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (live &&
              n.metrics.axis == Axis.vertical &&
              n.metrics.extentAfter < n.metrics.viewportDimension) {
            _askForMore();
          }
          return false;
        },
        child: ListView.builder(
          key: PageStorageKey<String>('sound_list_$pill'),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: sounds.length + (more ? 1 : 0),
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
    final listening = progress != null && _c.listeningId == sound.id;
    final duration = formatSoundDuration(sound.durationMs);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => unawaited(_c.tapRow(sound)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_kEdge, 8, 4, 8),
          child: Row(
            children: [
              _SoundCover(
                coverPath: kept?.coverPath,
                coverUrl: sound.coverUrl,
                listening: listening,
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
                // Download first, then +: a sound goes on the timeline only
                // once it is on the phone.
                child: progress != null && !listening
                    ? Center(child: _Ring(progress: progress))
                    : kept != null
                        ? IconButton(
                            key: ValueKey('sfx_add_${sound.id}'),
                            onPressed: () => unawaited(_add(sound)),
                            icon: const Icon(LucideIcons.plus, size: 20),
                            color: AppColors.textPrimary,
                          )
                        : IconButton(
                            key: ValueKey('sfx_download_${sound.id}'),
                            onPressed: progress != null
                                ? null
                                : () => unawaited(_c.download(sound)),
                            icon: const Icon(LucideIcons.download, size: 20),
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
