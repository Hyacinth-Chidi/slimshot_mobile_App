import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../app_version.dart';
import '../models/update_info.dart';

/// Whether [info] names a newer release than the one installed: a higher
/// version, or a higher build of the same one.
bool updateIsAvailable(
  UpdateInfo info, {
  String version = kAppVersion,
  int build = kAppBuildNumber,
}) {
  final remote = info.latestVersion.split('.').map(int.parse).toList();
  final local = version.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    final r = i < remote.length ? remote[i] : 0;
    final l = i < local.length ? local[i] : 0;
    if (r != l) return r > l;
  }
  return info.latestBuildNumber > build;
}

class UpdateService {
  static const String _apiUrl =
      'https://slimshot-ai-update-api.vercel.app/api/update';

  static const String _lastCheckKey = 'update_last_check';
  static const String _cachedDataKey = 'update_cached_data';

  static const int _checkIntervalDays = 7;

  /// Check for updates. Returns [UpdateInfo] if an update is available,
  /// or `null` if the app is up to date or check failed.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      UpdateInfo? info;
      if (_shouldFetchFromApi(prefs)) {
        info = await _fetchFromApi(prefs);
      } else {
        info = _getCachedUpdate(prefs);
      }

      if (info == null) return null;

      return updateIsAvailable(info) ? info : null;
    } catch (e) {
      debugPrint('⚠️ Update check failed: $e');
      return null;
    }
  }

  /// Check if we should fetch fresh data from the API.
  static bool _shouldFetchFromApi(SharedPreferences prefs) {
    final lastCheck = prefs.getInt(_lastCheckKey);
    if (lastCheck == null) return true; // Never checked before

    final lastCheckTime = DateTime.fromMillisecondsSinceEpoch(lastCheck);
    final daysSinceCheck = DateTime.now().difference(lastCheckTime).inDays;

    return daysSinceCheck >= _checkIntervalDays;
  }

  /// Fetch update info from the API and cache it.
  static Future<UpdateInfo?> _fetchFromApi(SharedPreferences prefs) async {
    try {
      debugPrint('🌐 Fetching update info from API...');
      final response = await http
          .get(Uri.parse(_apiUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        await prefs.setString(_cachedDataKey, response.body);
        await prefs.setInt(
          _lastCheckKey,
          DateTime.now().millisecondsSinceEpoch,
        );

        debugPrint('✅ Update info fetched and cached.');
        return UpdateInfo.fromJson(data);
      } else {
        debugPrint('⚠️ API returned status ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('⚠️ API fetch failed: $e');
      return null; // Fail silently — don't block the app
    }
  }

  /// Get cached update info from SharedPreferences.
  static UpdateInfo? _getCachedUpdate(SharedPreferences prefs) {
    final cached = prefs.getString(_cachedDataKey);
    if (cached == null) return null;

    try {
      return UpdateInfo.fromJson(json.decode(cached));
    } catch (e) {
      debugPrint('⚠️ Failed to parse cached update: $e');
      return null;
    }
  }
}
