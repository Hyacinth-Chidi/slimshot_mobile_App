import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_colors.dart';

class PermissionDialog {
  static Future<void> showGalleryAccessRequired({
    required BuildContext context,
    required String message,
    required VoidCallback onCancel,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Permission Required',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFFCBD5E1)),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onCancel();
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(
                color: AppColors.primaryStart,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
