import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/services/update_service.dart';
import '../core/widgets/responsive_layout.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
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
                              ),
                              GestureDetector(
                                onTap: () => context.push('/settings'),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B), // slate-800
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF334155),
                                    ), // slate-700
                                  ),
                                  child: const Icon(
                                    LucideIcons.settings,
                                    color: Color(0xFF94A3B8),
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ).animate().fadeIn().slideY(
                            begin: -0.2,
                            end: 0,
                          ), // Settings header animation

                          const Spacer(),

                          Row(
                            children: [
                              Expanded(
                                child: _GridActionCard(
                                  title: 'Compress Video',
                                  icon: LucideIcons.video,
                                  color: const Color(0xFF6366F1), // Indigo
                                  onTap: () => context.push('/compress/video'),
                                  delay: 200,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _GridActionCard(
                                  title: 'Compress Photo',
                                  icon: LucideIcons.image,
                                  color: const Color(0xFF6366F1), // Indigo
                                  onTap: () => context.push('/compress/image'),
                                  delay: 250,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _GridActionCard(
                                  title: 'Privacy Strip',
                                  icon: LucideIcons.shield,
                                  color: const Color(0xFF6366F1), // Indigo
                                  onTap: () => context.push('/privacy'),
                                  delay: 300,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _GridActionCard(
                                  title: 'Format Convert',
                                  icon: LucideIcons.fileArchive,
                                  color: const Color(0xFF6366F1), // Indigo
                                  onTap: () => context.push('/convert'),
                                  delay: 350,
                                ),
                              ),
                            ],
                          ),

                          const Spacer(),

                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _FooterItem(icon: LucideIcons.zap, label: 'Fast'),
                              SizedBox(width: 24),
                              _FooterItem(
                                icon: LucideIcons.shieldCheck,
                                label: 'Secure',
                              ),
                            ],
                          ).animate().fadeIn(delay: 500.ms),

                          const SizedBox(height: 16),
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
              height: 140, // Square proportion
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
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AnimatedContainer(
                          duration: 150.ms,
                          transformAlignment: Alignment.center,
                          transform: _isPressed 
                              ? Matrix4.diagonal3Values(0.9, 0.9, 1.0) 
                              : Matrix4.identity(),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: widget.color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(widget.icon, color: widget.color, size: 24),
                        ),
                        Text(
                          widget.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFF8FAFC),
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
      ),
    ).animate().fadeIn(delay: widget.delay.ms).slideY(begin: 0.1, end: 0);
  }
}

class _FooterItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FooterItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
      ],
    );
  }
}
