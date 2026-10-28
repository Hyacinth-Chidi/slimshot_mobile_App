import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/floating_nav_bar.dart';

const List<FloatingNavItem> _kTabs = [
  FloatingNavItem(icon: Icons.home_rounded, label: 'Home'),
  FloatingNavItem(icon: Icons.space_dashboard_rounded, label: 'Workspace'),
  FloatingNavItem(icon: Icons.settings_rounded, label: 'Settings'),
];

class MainShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShellScreen({super.key, required this.navigationShell});

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          navigationShell,

          // Floating Nav Bar Overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: kFloatingNavBottomMargin,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FloatingNavBar(
                      items: _kTabs,
                      currentIndex: navigationShell.currentIndex,
                      onTap: _goBranch,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
