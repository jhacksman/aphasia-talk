import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark.dart';
import 'api_service.dart';

/// Manages bookmarks with local cache + remote sync.
class BookmarkService {
  static const _cacheKey = 'bookmarksCache';

  final ApiService _api;
  List<Bookmark> _bookmarks = [];

  BookmarkService(this._api);

  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);

  Bookmark? findFor(String text, String word) {
    for (final b in _bookmarks) {
      if (b.text == text && b.word == word) return b;
    }
    return null;
  }

  Set<String> textsForWord(String word) {
    return {for (final b in _bookmarks) if (b.word == word) b.text};
  }

  Future<void> load() async {
    try {
      _bookmarks = await _api.getBookmarks();
      await _saveCache();
    } catch (_) {
      await _loadCache();
    }
  }

  Future<Bookmark?> add({
    required String text,
    required String word,
    String? category,
  }) async {
    try {
      final bm = await _api.addBookmark(
        text: text,
        word: word,
        category: category,
      );
      _bookmarks.add(bm);
      await _saveCache();
      return bm;
    } catch (_) {
      return null;
    }
  }

  Future<bool> remove(int id) async {
    try {
      await _api.deleteBookmark(id);
      _bookmarks.removeWhere((b) => b.id == id);
      await _saveCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _bookmarks
        .map(
          (b) => {
            'id': b.id,
            'text': b.text,
            'word': b.word,
            'category': b.category,
            'created_at': b.createdAt,
          },
        )
        .toList();
    await prefs.setString(_cacheKey, jsonEncode(data));
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    final list = jsonDecode(raw) as List<dynamic>;
    _bookmarks =
        list.map((j) => Bookmark.fromJson(j as Map<String, dynamic>)).toList();
  }
}
