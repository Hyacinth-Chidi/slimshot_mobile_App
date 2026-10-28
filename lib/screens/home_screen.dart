import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/lucide_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'dart:io';
import 'package:timeago/timeago.dart' as timeago;

import '../core/theme/app_colors.dart';
import '../core/services/update_service.dart';
import '../core/widgets/responsive_layout.dart';
import '../core/services/media_picker_service.dart';
import '../core/services/draft_service.dart';
import '../core/services/draft_refresh_notifier.dart';
import '../core/models/draft_project.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/frosted_glass.dart';
import '../core/widgets/permission_dialog.dart';
import '../core/widgets/colour_field_backdrop.dart';
import '../core/widgets/floating_nav_bar.dart';
import '../features/home_widget/launch_actions.dart';
import 'home_header.dart';
import 'home_layout.dart';

/// How many recent edits Home shows; Workspace has them all.
const int _kRecentDrafts = 6;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DraftProject> _recentDrafts = [];
  bool _isLoadingDrafts = true;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
    DraftRefreshNotifier.instance.addListener(_loadDrafts);
    LaunchActions.instance.addListener(_runLaunchAction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
      // A tap that arrived before Home was up (the splash, onboarding).
      _runLaunchAction();
    });
  }

  @override
  void dispose() {
    LaunchActions.instance.removeListener(_runLaunchAction);
    DraftRefreshNotifier.instance.removeListener(_loadDrafts);
    super.dispose();
  }

  /// A tap on the home screen widget or the icon's menu, run with the
  /// handler Home's own button runs, so the gallery, its permission dialog
  /// and its errors are exactly Home's.
  void _runLaunchAction() {
    if (!mounted) return;
    switch (LaunchActions.instance.take()) {
      case null:
        return;
      case NewVideo():
        unawaited(_handleEditVideo());
      case CompressVideo():
        unawaited(_handleCompressVideo());
      case ContinueEdit(:final draftId):
        unawaited(_continueEdit(draftId));
    }
  }

  Future<void> _continueEdit(String draftId) async {
    final draft = await DraftService.getDraftById(draftId);
    if (!mounted) return;
    if (draft == null) {
      ToastUtils.show(context, 'That edit was deleted.', isWarning: true);
      // The widget may still show it: send it the edit that is last now.
      DraftRefreshNotifier.instance.refresh();
      return;
    }
    await _openDraft(draft);
  }

  Future<void> _openDraft(DraftProject draft) async {
    await context.push('/edit/video', extra: draft);
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    try {
      final drafts = await DraftService.getRecentDrafts(_kRecentDrafts);
      if (mounted) {
        setState(() {
          _recentDrafts = drafts;
          _isLoadingDrafts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDrafts = false;
        });
      }
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await UpdateService.checkForUpdate();
      if (info != null && mounted) {
        context.go('/update', extra: info);
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  Future<void> _handleEditVideo() async {
    try {
      final picker = MediaPickerService();
      // A project can start from several videos and photos at once, in the
      // order they were picked.
      final media = await picker.pickMedia();
      if (media.isNotEmpty && mounted) {
        await context.push('/edit/video', extra: media);
        _loadDrafts();
      }
    } catch (e) {
      if (!mounted) return;
      if (MediaPickerService.isPermissionError(e)) {
        PermissionDialog.showGalleryAccessRequired(
          context: context,
          message:
              'Please grant storage access to pick photos and videos for editing.',
          onCancel: () {},
        );
      } else {
        ToastUtils.show(context, 'Error picking media: $e', isError: true);
      }
    }
  }

  Future<void> _handleCompressVideo() async {
    try {
      final picker = MediaPickerService();
      final video = await picker.pickVideo();
      if (video != null && mounted) {
        context.push('/compress/video', extra: video);
      }
    } catch (e) {
      if (!mounted) return;
      if (MediaPickerService.isPermissionError(e)) {
        PermissionDialog.showGalleryAccessRequired(
          context: context,
          message:
              'Please grant storage access to pick videos for compression.',
          onCancel: () {},
        );
      } else {
        ToastUtils.show(context, 'Error picking video: $e', isError: true);
      }
    }
  }

  Future<void> _handleCompressPhoto() async {
    try {
      final picker = MediaPickerService();
      final images = await picker.pickImages();
      if (images.isNotEmpty && mounted) {
        context.push('/compress/image', extra: images);
      }
    } catch (e) {
      if (!mounted) return;
      if (MediaPickerService.isPermissionError(e)) {
        PermissionDialog.showGalleryAccessRequired(
          context: context,
          message:
              'Please grant storage access to pick photos for compression.',
          onCancel: () {},
        );
      } else {
        ToastUtils.show(context, 'Error picking photo: $e', isError: true);
      }
    }
  }

  Future<void> _handlePrivacyStrip() async {
    try {
      final picker = MediaPickerService();
      final images = await picker.pickImages();
      if (images.isNotEmpty && mounted) {
        context.push('/privacy', extra: images);
      }
    } catch (e) {
      if (!mounted) return;
      if (MediaPickerService.isPermissionError(e)) {
        PermissionDialog.showGalleryAccessRequired(
          context: context,
          message:
              'Please grant storage access to pick photos for privacy stripping.',
          onCancel: () {},
        );
      } else {
        ToastUtils.show(context, 'Error picking photo: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Where the floating nav's top edge is, up from the bottom of the screen.
    final navClearance =
        kFloatingNavClearance + MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: ColourFieldBackdrop()),

          // Down to the bottom of the screen: the drafts run on under the
          // floating nav rather than stopping above it.
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              key: const ValueKey('home_page'),
              slivers: [
                // The header is measured, never assumed: its height follows
                // the phone's width and text size.
                SliverToBoxAdapter(
                  child: ResponsiveCenter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          24, kHomeTopPadding, 24, 0),
                      child: HomeHeader(
                        brand: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              'assets/logo.svg',
                              width: 44,
                              height: 44,
                            ),
                            const SizedBox(width: 8),
                            ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) =>
                                  const LinearGradient(
                                    colors: [
                                      AppColors.textPrimary,
                                      AppColors.textSecondary,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(bounds),
                              child: const Text(
                                'SlimShot AI',
                                style: TextStyle(fontFamily: kInterfaceFontFamily, 
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn().slideY(begin: -0.2, end: 0),
                    ),
                  ),
                ),
                // Everything under the header is sized from the room the
                // phone leaves ([HomeLayout]): the rest of the screen, under
                // the nav included, ending in the drafts' box. Only where that
                // will not hold one row above the nav — a phone on its side —
                // does the page itself scroll.
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final layout = HomeLayout.fit(
                      room: constraints.viewportMainAxisExtent -
                          constraints.precedingScrollExtent,
                      title: homeTitleHeight(MediaQuery.textScalerOf(context)),
                      navClearance: navClearance,
                    );
                    return SliverToBoxAdapter(
                      child: SizedBox(
                        height: layout.height,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ResponsiveCenter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: _toolsAndTitle(layout),
                              ),
                            ),
                            Expanded(
                              child: ResponsiveCenter(
                                child: _recentDraftsArea(
                                  navClearance,
                                  layout.draftRow,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // What runs on under the nav passes under a blur across the full
          // width, never a hard edge. Over the bare background it shows
          // nothing, since the glows are already soft.
          if (!_isLoadingDrafts && _recentDrafts.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: navClearance,
              child: ClipRect(
                key: const ValueKey('recent_drafts_blur'),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// New Video, the three tools and the "Recent Edits" line, each at the
  /// height the phone's room gives it ([HomeLayout]).
  Widget _toolsAndTitle(HomeLayout layout) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: layout.gapAboveHero),
          _HeroActionCard(
            height: layout.hero,
            onTap: _handleEditVideo,
            delay: 200,
          ),
          SizedBox(height: layout.gapAboveTools),
          Row(
            children: [
              Expanded(
                child: _GridActionCard(
                  key: const ValueKey('home_compress_video'),
                  title: 'Compress\nVideo',
                  icon: LucideIcons.video,
                  height: layout.tools,
                  onTap: _handleCompressVideo,
                  delay: 250,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GridActionCard(
                  key: const ValueKey('home_compress_photo'),
                  title: 'Compress\nPhoto',
                  icon: LucideIcons.image,
                  height: layout.tools,
                  onTap: _handleCompressPhoto,
                  delay: 300,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GridActionCard(
                  key: const ValueKey('home_privacy_strip'),
                  title: 'Privacy\nStrip',
                  icon: LucideIcons.shield,
                  height: layout.tools,
                  onTap: _handlePrivacyStrip,
                  delay: 350,
                ),
              ),
            ],
          ),
          SizedBox(height: layout.gapAboveTitle),
          // One line at a line height of its own, so it is exactly the
          // height the layout made room for.
          SizedBox(
            height: layout.title,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Recent Edits',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: kInterfaceFontFamily,
                    fontSize: kHomeTitleFontSize,
                    height: kHomeTitleLineHeight,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),
          ),
          SizedBox(height: layout.gapAboveDrafts),
        ],
      );

  /// The recent edits, in the room from under their title to the bottom of
  /// the screen: up to six, three to a row, scrolling inside their own box.
  /// Where two rows fit above the nav, they sit there ([HomeLayout]); where
  /// they cannot, the second row runs on under the nav, blurred, until the
  /// drafts are scrolled up out from under it — the padding under the last
  /// row is what lets it clear the nav. The empty placeholder keeps its size.
  Widget _recentDraftsArea(double navClearance, double rowHeight) {
    if (_isLoadingDrafts) {
      return const Align(
        alignment: Alignment.topCenter,
        child: CircularProgressIndicator(color: AppColors.primaryStart),
      );
    }
    if (_recentDrafts.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: FrostedGlass(
                borderRadius: BorderRadius.circular(16),
                child: const SizedBox(
                  height: kHomeDraftsPlaceholderHeight,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.inbox,
                          color: AppColors.textTertiary,
                          size: 32,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Your recent edits will appear here',
                          style: TextStyle(fontFamily: kInterfaceFontFamily,
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: 450.ms)
              .slideY(begin: 0.1, end: 0),
        ),
      );
    }
    return GridView.builder(
          key: const ValueKey('recent_drafts'),
          padding: EdgeInsets.fromLTRB(24, 0, 24, navClearance + kHomeDraftNavGap),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: rowHeight,
            mainAxisSpacing: kHomeDraftSpacing,
            crossAxisSpacing: kHomeDraftSpacing,
          ),
          itemCount: _recentDrafts.length,
          itemBuilder: (context, i) => _buildDraftCard(_recentDrafts[i]),
        )
        .animate()
        .fadeIn(delay: 450.ms)
        .slideY(begin: 0.1, end: 0);
  }

  Widget _buildDraftCard(DraftProject draft) {
    return GestureDetector(
      key: ValueKey('recent_draft_${draft.id}'),
      onTap: () async {
        HapticFeedback.selectionClick();
        await _openDraft(draft);
      },
      child: FrostedGlass(
        borderRadius: BorderRadius.circular(12),
        blurSigma: 0, // the thumbnail covers what a blur would show
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child:
                  draft.thumbnailPath != null &&
                      File(draft.thumbnailPath!).existsSync()
                  ? Image.file(File(draft.thumbnailPath!), fit: BoxFit.cover)
                  : const Center(
                      child: Icon(
                        LucideIcons.film,
                        color: AppColors.textTertiary,
                        size: 32,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                timeago.format(draft.updatedAt),
                style: const TextStyle(fontFamily: kInterfaceFontFamily, 
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridActionCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final double height;
  final VoidCallback onTap;
  final int delay;

  const _GridActionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.height,
    required this.onTap,
    required this.delay,
  });

  @override
  State<_GridActionCard> createState() => _GridActionCardState();
}

class _GridActionCardState extends State<_GridActionCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // The corner circle keeps its share of a shorter card.
    final corner = widget.height / kHomeToolsHeight.full;
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      // Solid, the owner's call: beside the New Video card's colour and
      // photos, glass read as washed out.
      child: AnimatedContainer(
        duration: 150.ms,
        // The height includes the border: a border is padding inside a
        // container, so a height given to its child would grow the card
        // past what the layout made room for.
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isPressed ? AppColors.primaryStart : AppColors.surfaceLight,
          ),
        ),
        child: SizedBox.expand(
          child: Stack(
            children: [
              Positioned(
                right: -30 * corner,
                bottom: -30 * corner,
                // Decoration only. It was an `OpenContainer` — a widget that
                // opens a page when tapped — so a tap on this corner opened
                // an empty page inside the home tab, leaving only the
                // floating nav until Back, and never reached the card.
                child: AnimatedScale(
                  scale: _isPressed ? 1.2 : 1.0,
                  duration: 150.ms,
                  child: Container(
                    width: 100 * corner,
                    height: 100 * corner,
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary.withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),

              // The icon and its words keep their size until the card is
              // too short for them, then shrink together rather than
              // overflow it.
              Padding(
                padding: const EdgeInsets.all(10),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: 150.ms,
                          transformAlignment: Alignment.center,
                          transform: _isPressed
                              ? Matrix4.diagonal3Values(0.9, 0.9, 1.0)
                              : Matrix4.identity(),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.textPrimary.withValues(
                                alpha: 0.14,
                              ),
                            ),
                          ),
                          child: Icon(
                            widget.icon,
                            color: _isPressed
                                ? AppColors.primaryStart
                                : AppColors.textPrimary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 8), // Added spacing
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: kInterfaceFontFamily, 
                            fontSize: 13,
                            height: 1.2, // Tighter line height for multiline text
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: widget.delay.ms).slideY(begin: 0.1, end: 0);
  }
}

class _HeroActionCard extends StatefulWidget {
  final double height;
  final VoidCallback onTap;
  final int delay;

  const _HeroActionCard({
    required this.height,
    required this.onTap,
    required this.delay,
  });

  @override
  State<_HeroActionCard> createState() => _HeroActionCardState();
}

class _HeroActionCardState extends State<_HeroActionCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'New Video',
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('home_new_video'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        // The owner's design. A plus that is the whole card, the sign every
        // editor uses for "start something new" — it read as a banner before,
        // a slogan and a 3D picture, nothing that looked pressable — and
        // three photos fanned on a stand: a picture of making a video from
        // your own clips. Still the one block of colour on the screen.
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1,
          duration: 120.ms,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryDeep, AppColors.primaryEnd, AppColors.primaryStart],
                stops: [0, 0.55, 1],
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: LayoutBuilder(
                builder: (context, box) => Stack(children: [
                  // The photos on their stand, right of centre.
                  Positioned(
                    right: box.maxWidth * 0.04,
                    top: 0,
                    bottom: 0,
                    width: box.maxWidth * 0.5,
                    child: const _PhotoFan(),
                  ),
                  // The plus and its words, on the left: laid out for the
                  // card's full height and scaled to the height it has, so a
                  // shorter card shows the same plus smaller, never
                  // squeezed against its edges.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: box.maxWidth * 0.42,
                    child: FittedBox(
                      child: SizedBox(
                        width: box.maxWidth *
                            0.42 *
                            kHomeHeroHeight.full /
                            box.maxHeight,
                        height: kHomeHeroHeight.full,
                        child: const _NewVideoPlus(),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: widget.delay.ms).slideY(begin: 0.1, end: 0);
  }
}

/// The white plus inside two soft rings, "New Video" under it.
class _NewVideoPlus extends StatelessWidget {
  const _NewVideoPlus();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.textPrimary.withValues(alpha: 0.08),
            ),
            child: Container(
              width: 74,
              height: 74,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.textPrimary.withValues(alpha: 0.10),
                border: Border.all(
                  color: AppColors.textPrimary.withValues(alpha: 0.18),
                ),
              ),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.textPrimary,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.plus,
                  size: 28,
                  color: AppColors.primaryEnd,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'New Video',
              maxLines: 1,
              style: TextStyle(
                fontFamily: kInterfaceFontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      );
}

/// Three photos fanned on a white stand, the middle one a video.
class _PhotoFan extends StatelessWidget {
  const _PhotoFan();

  static Widget _photo(String side, {required double width, required double height, bool video = false}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.textPrimary, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9.5),
          child: Stack(fit: StackFit.expand, children: [
            Image.asset(
              'assets/home/new_video_$side.webp',
              fit: BoxFit.cover,
              // Drawn about 100 px tall: decode small, not at 1672.
              cacheHeight: 360,
            ),
            if (video)
              const Center(
                child: SizedBox(
                  width: 15,
                  height: 18,
                  child: CustomPaint(painter: _PlayOutlinePainter()),
                ),
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final h = box.maxHeight;
        final w = box.maxWidth;
        final midW = h * 0.44;
        final midH = h * 0.66;
        final sideW = h * 0.40;
        final sideH = h * 0.56;
        final centre = w / 2;
        return Stack(clipBehavior: Clip.none, children: [
          // The stand: a soft white mound just above the card's foot, its
          // peak hidden behind the photos.
          Positioned(
            left: centre - w * 0.33,
            width: w * 0.66,
            bottom: h * 0.04,
            height: h * 0.32,
            child: const CustomPaint(painter: _StandPainter()),
          ),
          Positioned(
            left: centre - midW / 2 - sideW * 0.72,
            top: h * 0.20,
            child: Transform.rotate(
              angle: -0.24,
              child: _photo('left', width: sideW, height: sideH),
            ),
          ),
          Positioned(
            left: centre + midW / 2 - sideW * 0.28,
            top: h * 0.20,
            child: Transform.rotate(
              angle: 0.24,
              child: _photo('right', width: sideW, height: sideH),
            ),
          ),
          Positioned(
            left: centre - midW / 2,
            top: h * 0.10,
            child: _photo('middle', width: midW, height: midH, video: true),
          ),
        ]);
      });
}

/// A play mark drawn as a thick, rounded white outline, the photo showing
/// through it.
class _PlayOutlinePainter extends CustomPainter {
  const _PlayOutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    const inset = stroke / 2;
    // How far along each edge a corner's curve begins: soft corners, as
    // designed, not the pointed ones a plain join gives.
    const round = 4.0;
    final corners = [
      const Offset(inset, inset),
      Offset(size.width - inset, size.height / 2),
      Offset(inset, size.height - inset),
    ];
    Offset toward(Offset from, Offset to) {
      final d = to - from;
      return from + d / d.distance * round;
    }

    final path = Path();
    for (var i = 0; i < 3; i++) {
      final prev = corners[(i + 2) % 3];
      final at = corners[i];
      final next = corners[(i + 1) % 3];
      final start = toward(at, prev);
      final end = toward(at, next);
      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      path.quadraticBezierTo(at.dx, at.dy, end.dx, end.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.textPrimary.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PlayOutlinePainter oldDelegate) => false;
}

/// A white triangle with rounded corners: a wide base, sides rising to a
/// peak under the middle photo.
class _StandPainter extends CustomPainter {
  const _StandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // A triangle inset by the corner radius, filled and stroked with a round
    // join, is the same triangle with its corners rounded.
    const r = 10.0;
    final path = Path()
      ..moveTo(r, size.height - r)
      ..lineTo(size.width - r, size.height - r)
      ..lineTo(size.width / 2, r)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.textPrimary
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.textPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _StandPainter oldDelegate) => false;
}
