import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:animations/animations.dart';
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
import '../core/widgets/permission_dialog.dart';

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
      final video = await picker.pickVideo();
      if (video != null && mounted) {
        await context.push('/edit/video', extra: video);
        _loadDrafts();
      }
    } catch (e) {
      if (!mounted) return;
      if (MediaPickerService.isPermissionError(e)) {
        PermissionDialog.showGalleryAccessRequired(
          context: context,
          message: 'Please grant storage access to pick videos for editing.',
          onCancel: () {},
        );
      } else {
        ToastUtils.show(context, 'Error picking video: $e', isError: true);
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
          // Subtle purple radial gradient orb (matches settings screen)
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryStart.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

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
                          Row(
                            mainAxisAlignment: MainAxisAlignment
                                .start, // Left align logo since settings icon is gone
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
                                child: Text(
                                  'SlimShot AI',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                            ],
                          ).animate().fadeIn().slideY(
                            begin: -0.2,
                            end: 0,
                          ), // Settings header animation

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
                          Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'Recent Drafts',
                                      style: GoogleFonts.plusJakartaSans(
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
                            Container(
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceLight.withValues(
                                      alpha: 0.3,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppColors.border.withValues(
                                        alpha: 0.3,
                                      ),
                                      style: BorderStyle.solid,
                                    ),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          LucideIcons.inbox,
                                          color: AppColors.textTertiary,
                                          size: 32,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Your recent video drafts will appear here',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
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
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.5),
            style: BorderStyle.solid,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child:
                  draft.thumbnailPath != null &&
                      File(draft.thumbnailPath!).existsSync()
                  ? Image.file(File(draft.thumbnailPath!), fit: BoxFit.cover)
                  : Container(
                      color: AppColors.surface,
                      child: const Center(
                        child: Icon(
                          LucideIcons.film,
                          color: AppColors.textTertiary,
                          size: 32,
                        ),
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: AppColors.surface.withValues(alpha: 0.8),
              child: Text(
                timeago.format(draft.updatedAt),
                style: GoogleFonts.plusJakartaSans(
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AnimatedContainer(
            duration: 120.ms,
            height: 120, // Square proportion
            decoration: BoxDecoration(
              color: _isPressed
                  ? AppColors.primaryStart.withValues(alpha: 0.1)
                  : AppColors.surfaceLight.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isPressed
                    ? AppColors.primaryStart.withValues(alpha: 0.6)
                    : AppColors.border.withValues(alpha: 0.5),
                width: _isPressed ? 1.5 : 1,
              ),
              boxShadow: _isPressed
                  ? [
                      BoxShadow(
                        color: AppColors.primaryStart.withValues(alpha: 0.15),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -30,
                  bottom: -30,
                  child: AnimatedScale(
                    scale: _isPressed ? 1.2 : 1.0,
                    duration: 150.ms,
                    child: OpenContainer(
                      closedElevation: 0,
                      openElevation: 0,
                      closedColor: Colors.transparent,
                      openColor: Colors.transparent,
                      middleColor: Colors.transparent,
                      transitionType: ContainerTransitionType.fadeThrough,
                      openBuilder: (context, _) => const SizedBox(),
                      closedBuilder: (context, openContainer) => Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppColors.primaryStart.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
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
                            color: AppColors.surface.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.border.withValues(alpha: 0.5),
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
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            height:
                                1.2, // Tighter line height for multiline text
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
  final Color _primaryColor = AppColors.primaryStart;

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child:
              AnimatedContainer(
                    duration: 120.ms,
                    height:
                        160, // Taller rectangular proportion for the new design
                    decoration: BoxDecoration(
                      color: _isPressed
                          ? _primaryColor.withValues(alpha: 0.1)
                          : AppColors.surfaceLight.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isPressed
                            ? _primaryColor.withValues(alpha: 0.6)
                            : AppColors.border.withValues(alpha: 0.4),
                        width: _isPressed ? 1.5 : 1,
                      ),
                      boxShadow: _isPressed
                          ? [
                              BoxShadow(
                                color: _primaryColor.withValues(alpha: 0.15),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ]
                          : [],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Subtle background glow on the right
                        Positioned(
                          right: -20,
                          bottom: -20,
                          child: AnimatedScale(
                            scale: _isPressed ? 1.1 : 1.0,
                            duration: 150.ms,
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                color: _primaryColor.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),

                        // The 3D Image on the right
                        Positioned(
                          right: -10,
                          top: -10,
                          bottom: -10,
                          child: AnimatedScale(
                            scale: _isPressed ? 0.95 : 1.0,
                            duration: 150.ms,
                            child: Image.asset(
                              'assets/video.png',
                              width:
                                  200, // Size it so it bleeds nicely out of bounds
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        // The Text on the left
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 24,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width:
                                  150, // Constrain text width so it doesn't overlap image
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Edit New',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 26,
                                      height: 1.1,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  ShaderMask(
                                    blendMode: BlendMode.srcIn,
                                    shaderCallback: (bounds) => AppColors
                                        .primaryGradient
                                        .createShader(bounds),
                                    child: Text(
                                      'Video',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 26,
                                        height: 1.1,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Create, edit and share amazing videos',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .animate(onPlay: (controller) => controller.repeat())
                  .shimmer(
                    delay: 5.seconds,
                    duration: 1500.ms,
                    color: Colors.white.withValues(alpha: 0.25),
                    angle: 1.2,
                  ),
        ),
      ),
    ).animate().fadeIn(delay: widget.delay.ms).slideY(begin: 0.1, end: 0);
  }
}
