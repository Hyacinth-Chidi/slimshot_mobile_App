import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/theme/app_colors.dart';

class _OnboardPage {
  final String title;
  final String subtitle;
  final String description;
  final IconData? icon;
  final String? imageAsset;
  final Color primaryColor;
  final Color secondaryColor;

  const _OnboardPage({
    required this.title,
    required this.subtitle,
    required this.description,
    this.icon,
    this.imageAsset,
    required this.primaryColor,
    required this.secondaryColor,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardPage> _pages = const [
    _OnboardPage(
      title: 'Pro Video',
      subtitle: ' Editing',
      description: 'Trim, merge, and add text overlays right on your device. No cloud needed.',
      imageAsset: 'assets/video_onboard.png',
      primaryColor: AppColors.primaryStart,
      secondaryColor: AppColors.primaryEnd,
    ),
    _OnboardPage(
      title: 'Smart',
      subtitle: ' Compression',
      description: 'Shrink video and photo file sizes dramatically without losing visual quality.',
      imageAsset: 'assets/smart_compresion.png',
      primaryColor: AppColors.primaryEnd,
      secondaryColor: AppColors.primaryStart,
    ),

    _OnboardPage(
      title: 'Endless',
      subtitle: ' Possibilities',
      description: 'Unlock your creativity with AI-powered tools for all your media needs.',
      imageAsset: 'assets/endless_possibility.png',
      primaryColor: AppColors.primaryEnd,
      secondaryColor: AppColors.primaryStart,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenOnboarding', true);
    } catch (e) {
      debugPrint('⚠️ Prefs failed: $e');
    }
    if (mounted) context.go('/home');
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPageData = _pages[_currentPage];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Animated Background Orbs
          AnimatedPositioned(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOutCubic,
            top: _currentPage % 2 == 1 ? -150 : -100,
            left: _currentPage > 1 ? -150 : -50,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                color: currentPageData.primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
            ).animate().blur(
              begin: const Offset(80, 80),
              end: const Offset(80, 80),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOutCubic,
            bottom: _currentPage % 2 == 0 ? -150 : -50,
            right: _currentPage > 1 ? -150 : -100,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                color: currentPageData.secondaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
            ).animate().blur(
              begin: const Offset(80, 80),
              end: const Offset(80, 80),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Logo
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/logo.svg',
                          width: 24,
                          height: 24,
                          colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'SlimShot AI',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: -0.2, end: 0),
                ),

                // PageView Content
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Spacer(flex: 1),
                            // Graphic / Icon
                            Expanded(
                              flex: 10, // Give maximum flex to the image so it spans deeply
                              child: page.imageAsset != null
                                ? Image.asset(
                                    page.imageAsset!,
                                    fit: BoxFit.contain,
                                    width: double.infinity, // allow it to be as wide as possible
                                  )
                                : Container(
                                    width: 160,
                                    height: 160,
                                    decoration: BoxDecoration(
                                      color: page.primaryColor.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: page.primaryColor.withValues(alpha: 0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        page.icon,
                                        size: 64,
                                        color: page.primaryColor,
                                      ),
                                    ),
                                  )
                                  .animate(key: ValueKey('icon_$index'))
                                  .scale(
                                    duration: 600.ms,
                                    curve: Curves.easeOutBack,
                                    begin: const Offset(0.5, 0.5),
                                  )
                                  .fadeIn(duration: 400.ms),
                            ),

                            const SizedBox(height: 24),

                            // Title
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: page.title),
                                  TextSpan(
                                    text: page.subtitle,
                                    style: TextStyle(color: page.primaryColor),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 28, // Reduced from 36
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                height: 1.2,
                              ),
                            )
                            .animate(key: ValueKey('title_$index'))
                            .slideY(begin: 0.2, end: 0, duration: 500.ms, curve: Curves.easeOutCubic)
                            .fadeIn(duration: 500.ms),

                            const SizedBox(height: 12),

                            // Description
                            Text(
                              page.description,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14, // Reduced from 16
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            )
                            .animate(key: ValueKey('desc_$index'))
                            .slideY(begin: 0.2, end: 0, duration: 600.ms, curve: Curves.easeOutCubic)
                            .fadeIn(duration: 600.ms),

                            const Spacer(flex: 1),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Bottom Navigation
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Skip Button
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _currentPage == _pages.length - 1 ? 0.0 : 1.0,
                        child: TextButton(
                          onPressed: _currentPage == _pages.length - 1 ? null : _finishOnboarding,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                          ),
                          child: Text(
                            'Skip',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      // Dot Indicators
                      Row(
                        children: List.generate(
                          _pages.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentPage == index ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index
                                  ? currentPageData.primaryColor
                                  : AppColors.textTertiary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),

                      // Next / Get Started Button
                      GestureDetector(
                        onTap: _nextPage,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            horizontal: _currentPage == _pages.length - 1 ? 24 : 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                currentPageData.primaryColor,
                                currentPageData.secondaryColor,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: currentPageData.primaryColor.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentPage == _pages.length - 1 ? 'Get Started' : 'Next',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (_currentPage < _pages.length - 1) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  LucideIcons.arrowRight,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.5, end: 0),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
