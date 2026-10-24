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
import 'home_header.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  @override
  void dispose() {
    DraftRefreshNotifier.instance.removeListener(_loadDrafts);
    super.dispose();
  }

  Future<void> _loadDrafts() async {
    try {
      final drafts = await DraftService.getRecentDrafts(3);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: ColourFieldBackdrop()),

          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ResponsiveCenter(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 24,
                        right: 24,
                        top: 32,
                        bottom: 100, // Extra padding for the floating nav bar
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          HomeHeader(
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

                          const SizedBox(height: 24),

                          // Edit Video Hero Card
                          _HeroActionCard(onTap: _handleEditVideo, delay: 200),

                          const SizedBox(height: 16),

                          // 3 Square Tool Buttons
                          Row(
                            children: [
                              Expanded(
                                child: _GridActionCard(
                                  title: 'Compress\nVideo',
                                  icon: LucideIcons.video,
                                  onTap: _handleCompressVideo,
                                  delay: 250,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _GridActionCard(
                                  title: 'Compress\nPhoto',
                                  icon: LucideIcons.image,
                                  onTap: _handleCompressPhoto,
                                  delay: 300,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _GridActionCard(
                                  title: 'Privacy\nStrip',
                                  icon: LucideIcons.shield,
                                  onTap: _handlePrivacyStrip,
                                  delay: 350,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),

                          // Recent Drafts Placeholder Section
                          const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'Recent Drafts',
                                      style: TextStyle(fontFamily: kInterfaceFontFamily, 
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .animate()
                              .fadeIn(delay: 400.ms)
                              .slideY(begin: 0.1, end: 0),

                          const SizedBox(height: 12),

                          if (_isLoadingDrafts)
                            const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primaryStart,
                              ),
                            )
                          else if (_recentDrafts.isEmpty)
                            FrostedGlass(
                                  borderRadius: BorderRadius.circular(16),
                                  child: const SizedBox(
                                    height: 120,
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            LucideIcons.inbox,
                                            color: AppColors.textTertiary,
                                            size: 32,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Your recent video drafts will appear here',
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
                                .slideY(begin: 0.1, end: 0)
                          else
                            SizedBox(
                                  height: 140,
                                  child: Row(
                                    children: [
                                      for (int i = 0; i < 3; i++) ...[
                                        Expanded(
                                          child: i < _recentDrafts.length
                                              ? _buildDraftCard(
                                                  _recentDrafts[i],
                                                )
                                              : const SizedBox(),
                                        ),
                                        if (i < 2) const SizedBox(width: 12),
                                      ],
                                    ],
                                  ),
                                )
                                .animate()
                                .fadeIn(delay: 450.ms)
                                .slideY(begin: 0.1, end: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftCard(DraftProject draft) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        await context.push('/edit/video', extra: draft);
        _loadDrafts();
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
  final VoidCallback onTap;
  final int delay;

  const _GridActionCard({
    required this.title,
    required this.icon,
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
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: FrostedGlass(
        borderRadius: BorderRadius.circular(16),
        tint: _isPressed
            ? AppColors.primaryStart.withValues(alpha: 0.16)
            : null,
        child: SizedBox(
          height: 120, // Square proportion
          child: Stack(
            children: [
              Positioned(
                right: -30,
                bottom: -30,
                // Decoration only. It was an `OpenContainer` — a widget that
                // opens a page when tapped — so a tap on this corner opened
                // an empty page inside the home tab, leaving only the
                // floating nav until Back, and never reached the card.
                child: AnimatedScale(
                  scale: _isPressed ? 1.2 : 1.0,
                  duration: 150.ms,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.primaryStart.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment
                        .center, // Center items to keep them together
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
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: widget.delay.ms).slideY(begin: 0.1, end: 0);
  }
}

class _HeroActionCard extends StatefulWidget {
  final VoidCallback onTap;
  final int delay;

  const _HeroActionCard({required this.onTap, required this.delay});

  @override
  State<_HeroActionCard> createState() => _HeroActionCardState();
}

class _HeroActionCardState extends State<_HeroActionCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'New video',
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
        // A plus that is the whole card, the sign every editor uses for "start
        // something new". It read as a banner before — a slogan and a 3D
        // picture, nothing that looked pressable. Still the one block of
        // colour on the screen, kept deep: a bright purple read as too much.
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1,
          duration: 120.ms,
          child: Container(
            height: 156,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryDeep,
                  AppColors.primaryEnd,
                  AppColors.primaryStart,
                ],
                stops: [0, 0.6, 1],
              ),
              border: Border.all(
                color: AppColors.textPrimary.withValues(alpha: 0.14),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryEnd.withValues(alpha: 0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(children: [
                // A sheen from the top left, the light the home screen has.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: const Alignment(0.2, 0.2),
                        colors: [
                          AppColors.textPrimary.withValues(alpha: 0.14),
                          AppColors.textPrimary.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Your media, fanned: what the plus opens.
                const Positioned(right: 18, top: 34, child: _MediaFan()),
                Padding(
                  padding: const EdgeInsets.only(left: 26),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.textPrimary,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.textPrimary.withValues(alpha: 0.12),
                              spreadRadius: 7,
                            ),
                            BoxShadow(
                              color: AppColors.textPrimary.withValues(alpha: 0.05),
                              spreadRadius: 15,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          LucideIcons.plus,
                          size: 30,
                          color: AppColors.primaryEnd,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'New video',
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: kInterfaceFontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: widget.delay.ms).slideY(begin: 0.1, end: 0);
  }
}

/// Three clips fanned out, the middle one a video: a picture of picking from
/// the gallery, where the card used to carry a 3D play button.
class _MediaFan extends StatelessWidget {
  const _MediaFan();

  static Widget _clip(List<Color> colors, {bool video = false}) => Container(
        width: 52,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.textPrimary.withValues(alpha: 0.85),
            width: 2,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: video
            ? const Icon(LucideIcons.play, size: 16, color: AppColors.textPrimary)
            : null,
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 96,
        height: 92,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            top: 12,
            child: Transform.rotate(
              angle: -0.21,
              child: _clip(const [AppColors.lilac, AppColors.primaryStart]),
            ),
          ),
          Positioned(
            left: 40,
            top: 12,
            child: Transform.rotate(
              angle: 0.21,
              child: _clip(const [AppColors.credit, AppColors.soundEffect]),
            ),
          ),
          Positioned(
            left: 20,
            top: 4,
            child: _clip(
              const [AppColors.effectTrack, AppColors.primaryStart],
              video: true,
            ),
          ),
        ]),
      );
}
