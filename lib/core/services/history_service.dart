import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_item.dart';

class HistoryService {
  static const _storageKey = 'optimization_history';
  static const _maxItems = 50;

  static Future<List<HistoryItem>> getItems() async {
    final prefs = await SharedPreferences.getInstance();
    final rawItems = prefs.getStringList(_storageKey) ?? const [];

    final items = <HistoryItem>[];
    for (final raw in rawItems) {
      try {
        items.add(HistoryItem.fromJson(json.decode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Ignore malformed history records from older app versions.
      }
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  static Future<void> addItem(HistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getItems();
    final deduped = [
      item,
      ...items.where((existing) => existing.id != item.id),
    ].take(_maxItems).toList();

    await prefs.setStringList(
      _storageKey,
      deduped.map((historyItem) => json.encode(historyItem.toJson())).toList(),
    );
  }

  static Future<void> removeItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getItems();
    await prefs.setStringList(
      _storageKey,
      items
          .where((item) => item.id != id)
          .map((item) => json.encode(item.toJson()))
          .toList(),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
