import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/lucide_icons.dart';

/// A compact pill at the top of the screen — never a banner.
///
/// Device-reported: the old toast was a full-width `AwesomeSnackbarContent`
/// card pinned flush to the top, so deleting a draft raised a "Success!"
/// banner over the drafts screen's own action buttons and the user waited
/// ~4 seconds for their UI back. The position stays top — the user's choice,
/// at the screen title's row like an Apple notification — but the pill is
/// compact, so it never reaches the edge action buttons, and everything
/// around it stays tappable because the overlay hit-tests only the pill.
///
/// The generic titles went with the card. "Success!" above "Draft deleted" is
/// the same fact twice — the echo rule that already removed sheet titles and
/// the apply-to-all subtitle — so severity is carried by the icon and its
/// colour instead. The four call sites that passed a real `title` were all
/// 'No Internet Connection' over a message that already said to check the
/// connection.
///
/// **The pill drives its own lifecycle** — an [AnimationController] for
/// enter/exit and one hold [Timer] cancelled in `dispose` — instead of a
/// `flutter_animate` chain. `Animate` starts through
/// `Future.delayed(delay, ...)`, a timer nothing can cancel (`.ignore()`
/// drops the future, not the timer), which `flutter_test` reports as
/// "A Timer is still pending" in every test that shows a toast.
class ToastUtils {
  /// Dismisses the toast currently showing, if any. One toast at a time:
  /// stacked toasts drew over each other, and a queue would show stale news.
  static VoidCallback? _dismissCurrent;

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isWarning = false,
  }) {
    final overlay = Overlay.of(context);

    // Replace, never stack.
    _dismissCurrent?.call();

    late OverlayEntry entry;
    var removed = false;

    // Dismissal can be asked for twice — the exit animation completing while
    // a tap lands, or a replacement arriving after the screen was popped.
    // `OverlayEntry.remove` asserts in both cases.
    void dismiss() {
      if (removed) return;
      removed = true;
      if (_dismissCurrent == dismiss) _dismissCurrent = null;
      if (entry.mounted) entry.remove();
    }

    entry = OverlayEntry(
      builder: (context) => SafeArea(
        // `Align` hit-tests only its child, so every tap outside the pill
        // falls straight through to the screen below — the whole point.
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            // At the screen title's row, Apple-notification style — the
            // user's position, after a pass below the app bar read as
            // floating "inside the screen". Compactness and tap-through are
            // what keep the edge action buttons usable, not distance: the
            // old banner's offence was being full-width and unhittable-under,
            // not being at the top.
            padding: const EdgeInsets.only(top: 8),
            child: ToastPill(
              message: message,
              isError: isError,
              isWarning: isWarning,
              onDismiss: dismiss,
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    _dismissCurrent = dismiss;
  }
}

/// The pill itself. Public so tests can find and measure it.
class ToastPill extends StatefulWidget {
  const ToastPill({
    super.key,
    required this.message,
    required this.isError,
    required this.isWarning,
    required this.onDismiss,
  });

  final String message;
  final bool isError;
  final bool isWarning;

  /// Removes the overlay entry. Idempotent — see `dismiss` above.
  final VoidCallback onDismiss;

  @override
  State<ToastPill> createState() => _ToastPillState();
}

class _ToastPillState extends State<ToastPill>
    with SingleTickerProviderStateMixin {
  /// Quicker than the sheets' [AppMotion.enter]: a toast is a glance, not an
  /// arriving surface. The curves stay AppMotion's so the feel matches.
  static const Duration _enter = Duration(milliseconds: 200);
  static const Duration _exit = Duration(milliseconds: 160);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _enter,
    reverseDuration: _exit,
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enterCurve,
    reverseCurve: AppMotion.exitCurve,
  );

  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
    _controller.forward();

    // An error or warning earns a longer read: those messages ("Transition
    // lane unavailable on this device") are sentences, not confirmations.
    final hold = (widget.isError || widget.isWarning)
        ? const Duration(milliseconds: 3500)
        : const Duration(milliseconds: 2200);
    _holdTimer = Timer(_enter + hold, _leave);
  }

  void _leave() {
    if (!mounted) return;
    _controller.reverse();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) widget.onDismiss();
  }

  /// A tap dismisses through the same exit the hold uses — 160ms of slide
  /// and fade reads as response, not as a wait, and a pop beside every other
  /// smooth edge would be the one abrupt thing on screen.
  void _dismissNow() {
    _holdTimer?.cancel();
    _controller.reverse();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isError
        ? AppColors.error
        : (widget.isWarning ? AppColors.warning : AppColors.success);
    final icon = widget.isError
        ? LucideIcons.alertCircle
        : (widget.isWarning ? LucideIcons.alertTriangle : LucideIcons.checkCircle);

    return FadeTransition(
      opacity: _curve,
      // A top toast arrives from its edge: it slides down a little of its
      // own height on entry and back up on exit (the reversed controller),
      // on AppMotion's emphasized curves.
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.6),
          end: Offset.zero,
        ).animate(_curve),
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _dismissNow,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  // Black is the one honest shadow colour on a dark theme.
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
