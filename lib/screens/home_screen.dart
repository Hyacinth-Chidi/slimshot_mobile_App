import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:animations/animations.dart';

import 'dart:io';
import 'package:timeago/timeago.dart' as timeago;

import '../core/services/update_service.dart';
import '../core/widgets/responsive_layout.dart';
import '../core/services/media_picker_service.dart';
import '../core/services/draft_service.dart';
import '../core/models/draft_project.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/permission_dialog.dart';
import 'workspace_screen.dart';
import 'settings_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
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
          message: 'Please grant storage access to pick videos for compression.',
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
          message: 'Please grant storage access to pick photos for compression.',
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
          message: 'Please grant storage access to pick photos for privacy stripping.',
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
      backgroundColor: const Color(0xFF020617), // slate-950
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.15), // Violet
                shape: BoxShape.circle,
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).move(
              begin: const Offset(0, 0),
              end: const Offset(50, 50),
              duration: 4000.ms,
              curve: Curves.easeInOutSine,
            ).blur(begin: const Offset(60, 60), end: const Offset(60, 60)),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.15), // Blue
                shape: BoxShape.circle,
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).move(
              begin: const Offset(0, 0),
              end: const Offset(-40, -40),
              duration: 5000.ms,
              curve: Curves.easeInOutSine,
            ).blur(begin: const Offset(60, 60), end: const Offset(60, 60)),
          ),
          Positioned(
            top: 200,
            right: -100,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFFEC4899).withValues(alpha: 0.1), // Pink
                shape: BoxShape.circle,
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).move(
              begin: const Offset(0, 0),
              end: const Offset(-20, 60),
              duration: 6000.ms,
              curve: Curves.easeInOutSine,
            ).blur(begin: const Offset(60, 60), end: const Offset(60, 60)),
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
                            mainAxisAlignment: MainAxisAlignment.start, // Left align logo since settings icon is gone
                            children: [
                              Image.asset('assets/logo.png', width: 44, height: 44),
                              const SizedBox(width: 8),
                              ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (bounds) => const LinearGradient(
                                  colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ).createShader(bounds),
                                child: Text(
                                  'SlimShotAI',
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
                          _HeroActionCard(
                            onTap: _handleEditVideo,
                            delay: 200,
                          ),

                          const SizedBox(height: 16),

                          // 3 Square Tool Buttons
                          Row(
                            children: [
                              Expanded(
                                child: _GridActionCard(
                                  title: 'Compress\nVideo',
                                  icon: LucideIcons.video,
                                  color: const Color(0xFF8B5CF6), // Violet
                                  onTap: _handleCompressVideo,
                                  delay: 250,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _GridActionCard(
                                  title: 'Compress\nPhoto',
                                  icon: LucideIcons.image,
                                  color: const Color(0xFF3B82F6), // Blue
                                  onTap: _handleCompressPhoto,
                                  delay: 300,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _GridActionCard(
                                  title: 'Privacy\nStrip',
                                  icon: LucideIcons.shield,
                                  color: const Color(0xFFEC4899), // Pink
                                  onTap: _handlePrivacyStrip,
                                  delay: 350,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),

                          // Recent Drafts Placeholder Section
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              children: [
                                Text(
                                  'Recent Drafts',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFF8FAFC),
                                  ),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),

                          const SizedBox(height: 12),

                          if (_isLoadingDrafts)
                            const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
                          else if (_recentDrafts.isEmpty)
                            Container(
                              height: 120,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B).withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFF334155).withValues(alpha: 0.3),
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      LucideIcons.inbox,
                                      color: Color(0xFF475569),
                                      size: 32,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Your recent video drafts will appear here',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ).animate().fadeIn(delay: 450.ms).slideY(begin: 0.1, end: 0)
                          else
                            SizedBox(
                              height: 140,
                              child: Row(
                                children: [
                                  for (int i = 0; i < 3; i++) ...[
                                    Expanded(
                                      child: i < _recentDrafts.length
                                          ? _buildDraftCard(_recentDrafts[i])
                                          : const SizedBox(),
                                    ),
                                    if (i < 2) const SizedBox(width: 12),
                                  ]
                                ],
                              ),
                            ).animate().fadeIn(delay: 450.ms).slideY(begin: 0.1, end: 0),

                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _FloatingNavBar(onReload: _loadDrafts).animate().slideY(
                        begin: 1.0,
                        end: 0,
                        curve: Curves.easeOutBack,
                        duration: 600.ms,
                      ).fadeIn(duration: 600.ms),
                ),
              ),
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
          color: const Color(0xFF1E293B).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF334155).withValues(alpha: 0.5),
            style: BorderStyle.solid,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: draft.thumbnailPath != null && File(draft.thumbnailPath!).existsSync()
                  ? Image.file(
                      File(draft.thumbnailPath!),
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: const Color(0xFF0F172A),
                      child: const Center(
                        child: Icon(LucideIcons.film, color: Color(0xFF475569), size: 32),
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF0F172A).withValues(alpha: 0.8),
              child: Text(
                timeago.format(draft.updatedAt),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
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
  final Color color;
  final VoidCallback onTap;
  final int delay;

  const _GridActionCard({
    required this.title,
    required this.icon,
    required this.color,
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
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: 120.ms,
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AnimatedContainer(
              duration: 120.ms,
              height: 120, // Square proportion
              decoration: BoxDecoration(
                color: _isPressed
                    ? widget.color.withValues(alpha: 0.15)
                    : const Color(0xFF1E293B).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _isPressed
                      ? widget.color.withValues(alpha: 0.8)
                      : const Color(0xFF334155).withValues(alpha: 0.5),
                  width: _isPressed ? 1.5 : 1,
                ),
                boxShadow: _isPressed
                    ? [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
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
                            color: widget.color.withValues(alpha: 0.1),
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
                        mainAxisAlignment: MainAxisAlignment.center, // Center items to keep them together
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
                              color: widget.color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(widget.icon, color: widget.color, size: 20),
                          ),
                          const SizedBox(height: 8), // Added spacing
                          Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              height: 1.2, // Tighter line height for multiline text
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFF8FAFC),
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
      ),
    ).animate().fadeIn(delay: widget.delay.ms).slideY(begin: 0.1, end: 0);
  }
}

class _HeroActionCard extends StatefulWidget {
  final VoidCallback onTap;
  final int delay;

  const _HeroActionCard({
    required this.onTap,
    required this.delay,
  });

  @override
  State<_HeroActionCard> createState() => _HeroActionCardState();
}

class _HeroActionCardState extends State<_HeroActionCard> {
  bool _isPressed = false;
  final Color _primaryColor = const Color(0xFF6366F1); // Indigo

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
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: 120.ms,
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AnimatedContainer(
              duration: 120.ms,
              height: 160, // Taller rectangular proportion for the new design
              decoration: BoxDecoration(
                color: _isPressed
                    ? _primaryColor.withValues(alpha: 0.15)
                    : const Color(0xFF1E293B).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _isPressed
                      ? _primaryColor.withValues(alpha: 0.8)
                      : const Color(0xFF334155).withValues(alpha: 0.5),
                  width: _isPressed ? 1.5 : 1,
                ),
                boxShadow: _isPressed
                    ? [
                        BoxShadow(
                          color: _primaryColor.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
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
                        width: 200, // Size it so it bleeds nicely out of bounds
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  // The Text on the left
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 150, // Constrain text width so it doesn't overlap image
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
                                color: const Color(0xFFF8FAFC),
                              ),
                            ),
                            ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)], // Violet to Indigo
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
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
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate(onPlay: (controller) => controller.repeat())
             .shimmer(delay: 5.seconds, duration: 1500.ms, color: Colors.white.withValues(alpha: 0.25), angle: 1.2),
          ),
        ),
      ),
    ).animate().fadeIn(delay: widget.delay.ms).slideY(begin: 0.1, end: 0);
  }
}

class _FloatingNavBar extends StatelessWidget {
  final VoidCallback onReload;
  const _FloatingNavBar({required this.onReload});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: const Color(0xFF334155).withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Home button — stays as a simple tap (already on home)
              _NavBarItem(
                icon: LucideIcons.home,
                label: 'Home',
                isActive: true,
                onTap: () {},
              ),

              // Workspace — uses OpenContainer for morph transition
              _OpenContainerNavItem(
                icon: LucideIcons.layoutGrid,
                label: 'Workspace',
                openBuilder: (context, closeContainer) => const WorkspaceScreen(),
                onClosed: (_) => onReload(),
              ),

              // Settings — uses OpenContainer for morph transition
              _OpenContainerNavItem(
                icon: LucideIcons.settings,
                label: 'Settings',
                openBuilder: (context, closeContainer) => const SettingsScreen(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A nav bar item that uses [OpenContainer] from the animations package
/// to create a container transform — the button morphs into the target screen.
class _OpenContainerNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final OpenContainerBuilder<Object?> openBuilder;
  final void Function(Object?)? onClosed;

  const _OpenContainerNavItem({
    required this.icon,
    required this.label,
    required this.openBuilder,
    this.onClosed,
  });

  @override
  Widget build(BuildContext context) {
    return OpenContainer(
      transitionDuration: const Duration(milliseconds: 500),
      closedElevation: 0,
      openElevation: 0,
      closedColor: Colors.transparent,
      openColor: const Color(0xFF020617), // Match app background
      middleColor: const Color(0xFF0F172A),
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      openBuilder: openBuilder,
      onClosed: onClosed,
      closedBuilder: (context, openContainer) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            openContainer();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: const Color(0xFF94A3B8), size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF8B5CF6) : const Color(0xFF94A3B8);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
