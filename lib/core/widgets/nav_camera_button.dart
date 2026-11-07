import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/lucide_icons.dart';
import 'floating_nav_bar.dart';

/// The space between the bar and the camera's circle.
const double kNavCameraGap = 12;

const Key kNavCameraKey = ValueKey('nav_camera');

/// How far a press squeezes the circle: the bar's own tabs give as much.
const double _kPressedScale = 0.9;

/// The camera's door: a circle of its own on the nav's row, right of the bar,
/// the bar's height (the owner's pick of three mockups, 2026-11-07). Beside
/// the bar it covers nothing on any screen — floating above it would sit on
/// Home's last recent edit — and the bar keeps one shape on every tab. White
/// on purple, the app's chosen-state colours, and flat like the bar: a drop
/// shadow under it was taken off on the device (the owner's call).
class NavCameraButton extends StatefulWidget {
  const NavCameraButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<NavCameraButton> createState() => _NavCameraButtonState();
}

class _NavCameraButtonState extends State<NavCameraButton> {
  bool _pressed = false;

  void _press(bool down) {
    if (_pressed != down) setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: 'Camera',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapCancel: () => _press(false),
        onTapUp: (_) => _press(false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? _kPressedScale : 1,
          duration: still ? Duration.zero : const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          child: Container(
            width: kFloatingNavBarHeight,
            height: kFloatingNavBarHeight,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryStart, AppColors.primaryEnd],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(LucideIcons.camera, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
