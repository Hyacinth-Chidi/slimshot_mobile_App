import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The step down a phone was given after a choppy live reaction (0 none, 1 at
/// most 720p, 2 made after recording), kept per build: a new build — maybe
/// faster — tries again from the top. With no build known nothing is kept,
/// so a phone is never stuck on a guess.
class ReactCaptureStore {
  static const key = 'react_capture_step';

  static Future<int> load(String? build) async {
    if (build == null) return 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return 0;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['build'] != build) return 0;
      final step = decoded['step'];
      return step is int ? step.clamp(0, 2).toInt() : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> save(int step, String? build) async {
    if (build == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode({'build': build, 'step': step.clamp(0, 2)}));
    } catch (_) {
      // Not remembered: the next reaction asks the phone again.
    }
  }
}
