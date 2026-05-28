import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_colors.dart';

class BeforeAfterSlider extends StatefulWidget {
  final File beforeImage;
  final File afterImage;
  final double height;
  final double width;

  const BeforeAfterSlider({
    super.key,
    required this.beforeImage,
    required this.afterImage,
    required this.height,
    required this.width,
  });

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _sliderPosition = 0.5; // 0.0 to 1.0

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _sliderPosition += details.delta.dx / widget.width;
          _sliderPosition = _sliderPosition.clamp(0.0, 1.0);
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.file(widget.afterImage, fit: BoxFit.cover),
              ),
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),

              Positioned.fill(
                child: Image.file(widget.afterImage, fit: BoxFit.contain),
              ),

              Positioned.fill(
                child: ClipRect(
                  clipper: _BeforeClipper(_sliderPosition),
                  child: Image.file(widget.beforeImage, fit: BoxFit.contain),
                ),
              ),

              if (_sliderPosition > 0.2)
                Positioned(
                  left: 16,
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Before',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),

              if (_sliderPosition < 0.8)
                Positioned(
                  right: 16,
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryStart.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'After',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),

              Positioned(
                left: widget.width * _sliderPosition - 16, // Center thumb
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 4,
                        color: Colors.white,
                        height: double.infinity,
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          LucideIcons.code, // Looks somewhat like < > arrows
                          color: AppColors.background,
                          size: 16,
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
    );
  }
}

class _BeforeClipper extends CustomClipper<Rect> {
  final double fraction;

  _BeforeClipper(this.fraction);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, size.width * fraction, size.height);
  }

  @override
  bool shouldReclip(_BeforeClipper oldClipper) {
    return oldClipper.fraction != fraction;
  }
}
