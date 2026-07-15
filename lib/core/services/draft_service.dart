import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/draft_project.dart';

class DraftService {
  static const _storageKey = 'video_drafts';
  static const _maxItems = 20;
  static const _maxAgeDays = 20;

  static Future<List<DraftProject>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final rawItems = prefs.getStringList(_storageKey) ?? const [];

    final items = <DraftProject>[];
    for (final raw in rawItems) {
      try {
        items.add(DraftProject.fromJson(json.decode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Ignore malformed draft records from older app versions.
      }
    }

    final now = DateTime.now();
    bool needToUpdateStorage = false;

    // Filter out old drafts (> 20 days)
    final validItems = <DraftProject>[];
    for (final item in items) {
      if (now.difference(item.updatedAt).inDays > _maxAgeDays) {
        needToUpdateStorage = true;
        _deleteThumbnail(item.thumbnailPath);
      } else {
        validItems.add(item);
      }
    }

    validItems.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (needToUpdateStorage) {
      await _saveAll(validItems, prefs);
    }

    return validItems;
  }

  static Future<List<DraftProject>> getRecentDrafts(int count) async {
    final drafts = await getDrafts();
    return drafts.take(count).toList();
  }

  static Future<DraftProject?> getDraftById(String id) async {
    final drafts = await getDrafts();
    try {
      return drafts.firstWhere((draft) => draft.id == id);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDraft(DraftProject item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getDrafts();
    
    // Remove the old version of this draft if it exists
    final previousDraftIndex = items.indexWhere((existing) => existing.id == item.id);
    if (previousDraftIndex != -1) {
       final oldDraft = items.removeAt(previousDraftIndex);
       if (oldDraft.thumbnailPath != null && oldDraft.thumbnailPath != item.thumbnailPath) {
          _deleteThumbnail(oldDraft.thumbnailPath);
       }
    }

    final deduped = [
      item,
      ...items,
    ];

    // Enforce max limit
    while (deduped.length > _maxItems) {
      final removed = deduped.removeLast();
      _deleteThumbnail(removed.thumbnailPath);
    }

    await _saveAll(deduped, prefs);
  }

  static Future<void> deleteDraft(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getDrafts();
    
    final itemToRemove = items.firstWhere((item) => item.id == id, orElse: () => throw Exception('Draft not found'));
    _deleteThumbnail(itemToRemove.thumbnailPath);

    items.removeWhere((item) => item.id == id);
    await _saveAll(items, prefs);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getDrafts();
    for (final item in items) {
       _deleteThumbnail(item.thumbnailPath);
    }
    await prefs.remove(_storageKey);
  }

  static Future<void> _saveAll(List<DraftProject> items, SharedPreferences prefs) async {
    await prefs.setStringList(
      _storageKey,
      items.map((item) => json.encode(item.toJson())).toList(),
    );
  }

  static void _deleteThumbnail(String? path) {
    if (path == null) return;
    final file = File(path);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {
        // Ignore deletion errors
      }
    }
  }
}
