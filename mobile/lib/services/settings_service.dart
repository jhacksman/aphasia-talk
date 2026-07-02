import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Local persistence: backend address, cached word grid, cached sentences per
/// word, and a bookmarks mirror — so the app opens to something useful even
/// when the Spark is unreachable (SPEC.md: offline resilience).
class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static const _kBackendUrl = 'backendUrl';
  static const _kWordsCache = 'wordsCache';
  static const _kSentenceCache = 'sentenceCache';
  static const _kBookmarksCache = 'bookmarksCache';

  static Future<SettingsService> load() async =>
      SettingsService(await SharedPreferences.getInstance());

  String get backendUrl => _prefs.getString(_kBackendUrl) ?? '';
  Future<void> setBackendUrl(String url) => _prefs.setString(_kBackendUrl, url.trim());

  // ── Word grid cache ──

  List<WordCategory>? cachedWords() {
    final raw = _prefs.getString(_kWordsCache);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((c) => WordCategory.fromJson(c as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheWords(List<WordCategory> categories) => _prefs.setString(
      _kWordsCache, jsonEncode(categories.map((c) => c.toJson()).toList()));

  // ── Per-word sentence cache (last generation wins) ──

  GenerateResult? cachedSentences(String word) {
    final raw = _prefs.getString(_kSentenceCache);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final entry = map[word.toLowerCase()];
      if (entry == null) return null;
      return GenerateResult.fromJson(entry as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Most-recently-used words kept in the offline sentence cache. Bounds
  /// disk/memory growth on a device used daily for years; 200 words is far
  /// more than the full seeded grid plus related-word taps.
  static const int maxCachedWords = 200;

  Future<void> cacheSentences(String word, GenerateResult result) async {
    Map<String, dynamic> map;
    try {
      map = jsonDecode(_prefs.getString(_kSentenceCache) ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      map = {};
    }
    // Re-insert to move the word to the end (Dart maps preserve insertion
    // order), then evict from the front — oldest first.
    map.remove(word.toLowerCase());
    map[word.toLowerCase()] = result.toJson();
    while (map.length > maxCachedWords) {
      map.remove(map.keys.first);
    }
    await _prefs.setString(_kSentenceCache, jsonEncode(map));
  }

  // ── Bookmarks mirror ──

  List<Bookmark> cachedBookmarks() {
    final raw = _prefs.getString(_kBookmarksCache);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((b) => Bookmark.fromJson(b as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> cacheBookmarks(List<Bookmark> bookmarks) => _prefs.setString(
      _kBookmarksCache, jsonEncode(bookmarks.map((b) => b.toJson()).toList()));
}
