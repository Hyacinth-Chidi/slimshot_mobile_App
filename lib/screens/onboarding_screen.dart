import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/gradient_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -50,
            child:
                Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF6366F1,
                    ).withValues(alpha: 0.15), // Indigo
                    shape: BoxShape.circle,
                  ),
                ).animate().blur(
                  begin: const Offset(60, 60),
                  end: const Offset(60, 60),
                ), // Heavy blur
          ),
          Positioned(
            bottom: -50,
            right: -100,
            child:
                Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFEC4899,
                    ).withValues(alpha: 0.15), // Pink
                    shape: BoxShape.circle,
                  ),
                ).animate().blur(
                  begin: const Offset(60, 60),
                  end: const Offset(60, 60),
                ), // Heavy blur
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),

                  Center(
                    child: Column(
                      children: [
                        Container(
                              width: 96,
                              height: 96, // w-24 h-24
                              decoration: BoxDecoration(
                                color: const Color(0x336366F1), // indigo-500/20
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0x4D6366F1),
                                ), // indigo-500/30
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(9.0),
                                child: Image.asset(
                                  'assets/logo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .moveY(
                              begin: -10,
                              end: 0,
                              duration: 2000.ms,
                              curve: Curves.easeInOut,
                            )
                            .scale(
                              begin: const Offset(1.0, 1.0),
                              end: const Offset(1.05, 1.05),
                              duration: 3000.ms,
                              curve: Curves.easeInOut,
                            ),

                        const SizedBox(height: 24),

                        Text.rich(
                          const TextSpan(
                            children: [
                              TextSpan(text: 'SlimShot'),
                              TextSpan(
                                text: ' AI',
                                style: TextStyle(
                                  color: Color(0xFF8B5CF6),
                                ), // Violet-500
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 36, // text-4xl
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFF8FAFC), // slate-50
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          'Your all-in-one local toolkit for\nmedia optimization & privacy',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15, // text-base
                            color: const Color(0xFF94A3B8), // slate-400
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 100.ms).slideY(begin: -0.5, end: 0),

                  const Spacer(),

                  const Column(
                    children: [
                      _FeatureItem(
                        icon: LucideIcons.layoutGrid,
                        iconColor: Color(0xFF8B5CF6), // Violet-500
                        title: 'Smart Compression',
                        description: 'Reduce media size without losing quality',
                        delay: 300,
                      ),
                      _FeatureItem(
                        icon: LucideIcons.shield,
                        iconColor: Color(0xFF6366F1), // Indigo-500
                        title: 'Privacy Strip',
                        description: 'Remove hidden GPS & device metadata',
                        delay: 400,
                      ),
                      _FeatureItem(
                        icon: LucideIcons.fileArchive,
                        iconColor: Color(0xFF3B82F6), // Blue-500
                        title: 'Format Converter',
                        description: 'Instantly transform image types',
                        delay: 500,
                      ),
                    ],
                  ),

                  const Spacer(),

                  Center(
                        child: GradientButton(
                          title: "Get Started",
                          icon: LucideIcons.arrowRight,
                          width: double.infinity,
                          borderRadius: 20,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF8B5CF6),
                              Color(0xFF3B82F6),
                            ], // Purple -> Blue
                          ),
                          onPress: () async {
                            try {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setBool('hasSeenOnboarding', true);
                            } catch (e) {
                              debugPrint('⚠️ Prefs failed: $e');
                            }
                            if (context.mounted) context.go('/home');
                          },
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 700.ms)
                      .slideY(begin: 0.5, end: 0)
                      .shimmer(delay: 1500.ms, duration: 1500.ms),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final int delay;

  const _FeatureItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF8FAFC),
                  ),
                ),
                Text(
                  description,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    color: const Color(0xFF94A3B8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: delay.ms).slideY(begin: 0.2, end: 0);
  }
}
