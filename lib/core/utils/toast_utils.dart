import 'package:flutter/material.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ToastUtils {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: AwesomeSnackbarContent(
            title: isError ? 'Error!' : 'Success!',
            message: message,
            contentType: isError ? ContentType.failure : ContentType.success,
          )
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: -1.0, end: 0.0, curve: Curves.easeOutBack)
              .then(delay: 3000.ms)
              .fadeOut(duration: 500.ms)
              .slideY(begin: 0.0, end: -1.0)
              .callback(callback: (_) => entry.remove()),
        ),
      ),
    );

    overlay.insert(entry);
  }
}
