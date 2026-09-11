import 'package:flutter/material.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ToastUtils {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isWarning = false,
    String? title,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    var removed = false;

    // The animation's callback can fire more than once — and can fire after the
    // overlay has already gone, if the screen was popped while a toast was on
    // screen. `OverlayEntry.remove` asserts in both cases, which surfaces as a
    // crash from inside the animation library rather than from here.
    void dismiss() {
      if (removed) return;
      removed = true;
      if (entry.mounted) entry.remove();
    }

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: AwesomeSnackbarContent(
            title: title ?? (isError ? 'Error!' : (isWarning ? 'Warning!' : 'Success!')),
            message: message,
            contentType: isError ? ContentType.failure : (isWarning ? ContentType.warning : ContentType.success),
          )
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: -1.0, end: 0.0, curve: Curves.easeOutBack)
              .then(delay: 3000.ms)
              .fadeOut(duration: 500.ms)
              .slideY(begin: 0.0, end: -1.0)
              .callback(callback: (_) => dismiss()),
        ),
      ),
    );

    overlay.insert(entry);
  }
}
