import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium compression loader overlay.
///
/// Wraps any child (video/image preview) with:
/// 1. A rounded-rect progress ring border that fills clockwise from the top
/// 2. A large centered percentage counter on top of the media
/// 3. AI-like typewriter status messages below
class CompressionLoaderOverlay extends StatefulWidget {
  final double progress; // 0.0 – 100.0
  final Widget child;
  final bool isVideo;
  final String? batchStatus; // e.g. "Processing 1 of 5"

  const CompressionLoaderOverlay({
    super.key,
    required this.progress,
    required this.child,
    this.isVideo = true,
    this.batchStatus,
  });

  @override
  State<CompressionLoaderOverlay> createState() =>
      _CompressionLoaderOverlayState();
}

class _CompressionLoaderOverlayState extends State<CompressionLoaderOverlay>
    with TickerProviderStateMixin {
  static const _videoMessages = [
    'Analyzing video frames…',
    'Compressing your video…',
    'Optimizing bitrate…',
    'Encoding output stream…',
    'Reducing file size…',
    'Applying smart compression…',
    'Almost there…',
  ];

  static const _imageMessages = [
    'Analyzing image data…',
    'Compressing your photo…',
    'Optimizing quality…',
    'Reducing file size…',
    'Applying smart algorithms…',
    'Encoding final output…',
    'Almost there…',
  ];

  int _currentMessageIndex = 0;
  String _displayedText = '';
  int _charIndex = 0;
  Timer? _typewriterTimer;
  Timer? _messageRotateTimer;

  late AnimationController _glowController;

  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  double _previousProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _progressAnimation =
        Tween<double>(begin: 0, end: widget.progress.clamp(0.0, 100.0)).animate(
          CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
        );
    _previousProgress = widget.progress.clamp(0.0, 100.0);
    _progressController.forward();

    _startTypewriter();
    _startMessageRotation();
  }

  @override
  void didUpdateWidget(CompressionLoaderOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newTarget = widget.progress.clamp(0.0, 100.0);
    if ((newTarget - _previousProgress).abs() > 0.5) {
      _progressAnimation =
          Tween<double>(
            begin: _progressAnimation.value,
            end: newTarget,
          ).animate(
            CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
          );
      _previousProgress = newTarget;
      _progressController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _messageRotateTimer?.cancel();
    _glowController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  List<String> get _messages =>
      widget.isVideo ? _videoMessages : _imageMessages;

  void _startTypewriter() {
    _charIndex = 0;
    _displayedText = '';
    _typewriterTimer?.cancel();
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 40), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final currentMessage = _messages[_currentMessageIndex];
      if (_charIndex < currentMessage.length) {
        setState(() {
          _charIndex++;
          _displayedText = currentMessage.substring(0, _charIndex);
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _startMessageRotation() {
    _messageRotateTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _currentMessageIndex = (_currentMessageIndex + 1) % _messages.length;
      });
      _startTypewriter();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, _) {
        final smoothProgress = _progressAnimation.value;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${smoothProgress.toInt()}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  '%',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF8B5CF6),
                    height: 1.0,
                  ),
                ),
              ],
            ),

            if (widget.batchStatus != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                ),
                child: Text(
                  widget.batchStatus!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFC4B5FD), // Violet 300
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                final glowOpacity = 0.15 + (_glowController.value * 0.15);
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFF8B5CF6,
                        ).withValues(alpha: glowOpacity),
                        blurRadius: 32,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: _RoundedRectProgressPainter(
                      progress: smoothProgress / 100.0,
                      borderRadius: 24,
                      strokeWidth: 5.0,
                      trackColor: const Color(0xFF334155),
                      progressColor: const Color(0xFF8B5CF6),
                      glowColor: const Color(0xFF8B5CF6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(5.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(19),
                        child: widget.child,
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF8B5CF6),
                          shape: BoxShape.circle,
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat())
                      .scaleXY(
                        begin: 0.8,
                        end: 1.2,
                        duration: 800.ms,
                        curve: Curves.easeInOut,
                      )
                      .then()
                      .scaleXY(
                        begin: 1.2,
                        end: 0.8,
                        duration: 800.ms,
                        curve: Curves.easeInOut,
                      ),
                  const SizedBox(width: 10),
                  Text(
                    _displayedText,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// CustomPainter that draws a rounded-rect progress ring.
/// Progress fills clockwise starting from top-center.
class _RoundedRectProgressPainter extends CustomPainter {
  final double progress; // 0.0 – 1.0
  final double borderRadius;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;
  final Color glowColor;

  _RoundedRectProgressPainter({
    required this.progress,
    required this.borderRadius,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawRRect(rrect, trackPaint);

    if (progress <= 0) return;

    final path = _createRoundedRectPath(size, borderRadius);
    final metrics = path.computeMetrics().first;
    final totalLength = metrics.length;

    final topStraight = size.width - 2 * borderRadius;
    final startOffset = topStraight / 2;

    final progressLength = totalLength * progress.clamp(0.0, 1.0);

    final extractedPath = _extractPathFromOffset(
      metrics,
      totalLength,
      startOffset,
      progressLength,
    );

    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawPath(extractedPath, glowPaint);

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(extractedPath, progressPaint);
  }

  Path _createRoundedRectPath(Size size, double r) {
    final w = size.width;
    final h = size.height;
    final path = Path();

    path.moveTo(r, 0);
    path.lineTo(w - r, 0);
    path.arcToPoint(Offset(w, r), radius: Radius.circular(r), clockwise: true);
    path.lineTo(w, h - r);
    path.arcToPoint(
      Offset(w - r, h),
      radius: Radius.circular(r),
      clockwise: true,
    );
    path.lineTo(r, h);
    path.arcToPoint(
      Offset(0, h - r),
      radius: Radius.circular(r),
      clockwise: true,
    );
    path.lineTo(0, r);
    path.arcToPoint(Offset(r, 0), radius: Radius.circular(r), clockwise: true);

    return path;
  }

  Path _extractPathFromOffset(
    PathMetric metrics,
    double totalLength,
    double startOffset,
    double extractLength,
  ) {
    final path = Path();
    final start = startOffset % totalLength;
    final end = start + extractLength;

    if (end <= totalLength) {
      final extracted = metrics.extractPath(start, end);
      path.addPath(extracted, Offset.zero);
    } else {
      final firstPart = metrics.extractPath(start, totalLength);
      final secondPart = metrics.extractPath(0, end - totalLength);
      path.addPath(firstPart, Offset.zero);
      path.addPath(secondPart, Offset.zero);
    }

    return path;
  }

  @override
  bool shouldRepaint(covariant _RoundedRectProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
