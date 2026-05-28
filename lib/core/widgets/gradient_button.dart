import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_colors.dart';

class GradientButton extends StatefulWidget {
  final String? title;
  final VoidCallback? onPress;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;

  const GradientButton({
    super.key,
    this.title,
    this.onPress,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 56,
    this.gradient,
    this.borderRadius = 20,
  });

  final Gradient? gradient;
  final double borderRadius;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPress != null && !widget.isLoading) {
      setState(() => _isPressed = true);
      HapticFeedback.lightImpact();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onPress != null && !widget.isLoading) {
      setState(() => _isPressed = false);
      widget.onPress!();
    }
  }

  void _handleTapCancel() {
    if (widget.onPress != null && !widget.isLoading) {
      setState(() => _isPressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: 100.ms,
        child: Container(
          height: widget.height,
          width: widget.width ?? double.infinity,
          decoration: BoxDecoration(
            gradient: widget.onPress != null
                ? (widget.gradient ??
                      const LinearGradient(
                        colors: [
                          AppColors.primaryStart,
                          AppColors.primaryEnd,
                        ], // Indigo -> Violet
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ))
                : const LinearGradient(
                    colors: [AppColors.surfaceLight, AppColors.surfaceLight],
                  ),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: widget.onPress != null && !_isPressed
                ? [
                    BoxShadow(
                      color: AppColors.primaryStart.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      if (widget.title != null)
                        Text(
                          widget.title!,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
