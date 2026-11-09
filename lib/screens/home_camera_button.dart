import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/lucide_icons.dart';
import '../core/widgets/floating_nav_bar.dart';

/// The space between the circle and the bar under it.
const double kHomeCameraGap = 12;

/// The circle's size: the bar's height, the size it was judged at on the
/// device beside the bar.
const double kHomeCameraSize = kFloatingNavBarHeight;

const Key kHomeCameraKey = ValueKey('home_camera_float');

/// How far a press squeezes the circle: the bar's own tabs give as much.
const double _kPressedScale = 0.9;

/// The camera's door: a circle floating on Home, bottom right above the nav
/// (the owner's call, 2026-11-09, after a first build put it beside the bar
/// on every tab). It sits on the last recent edit's corner, so Home draws it
/// over the drafts. White on purple, the app's chosen-state colours, and
/// flat: a drop shadow under it was taken off on the device (the owner's
/// call).
class HomeCameraButton extends StatefulWidget {
  const HomeCameraButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<HomeCameraButton> createState() => _HomeCameraButtonState();
}

class _HomeCameraButtonState extends State<HomeCameraButton> {
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
            width: kHomeCameraSize,
            height: kHomeCameraSize,
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
