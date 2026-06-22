import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/category.dart' show Category;
import 'models/sentence.dart';
import 'services/api_service.dart';
import 'services/bookmark_service.dart';
import 'services/tts_service.dart';

enum ConnectionState { unknown, online, offline }

class AppState extends ChangeNotifier {
  final ApiService api = ApiService();
  late final BookmarkService bookmarks = BookmarkService(api);
  final TtsService tts = TtsService();

  List<Category> categories = [];
  String? currentCategoryName;
  String? currentWord;
  String? selectedSentence;
  List<Sentence> sentences = [];
  List<String> relatedWords = [];
  bool loading = false;
  ConnectionState connection = ConnectionState.unknown;

  // Sentence cache for offline resilience.
  final Map<String, Map<String, dynamic>> _sentenceCache = {};

  Category? get currentCategory {
    if (currentCategoryName == null) return null;
    for (final c in categories) {
      if (c.name == currentCategoryName) return c;
    }
    return null;
  }

  Future<void> init() async {
    await api.init();
    await _loadWordsCache();
    await loadWords();
    await bookmarks.load();
    notifyListeners();
  }

  Future<void> loadWords() async {
    try {
      categories = await api.getWords();
      connection = ConnectionState.online;
      if (currentCategoryName == null && categories.isNotEmpty) {
        currentCategoryName = categories.first.name;
      }
      await _saveWordsCache();
    } catch (_) {
      connection = ConnectionState.offline;
      if (categories.isEmpty) _useFallbackWords();
    }
    notifyListeners();
  }

  void selectCategory(String name) {
    currentCategoryName = name;
    notifyListeners();
  }

  Future<void> selectWord(String word, {String? category}) async {
    currentWord = word;
    loading = true;
    sentences = [];
    relatedWords = [];
    notifyListeners();

    try {
      final result = await api.generate(
        word: word,
        category: category ?? currentCategoryName,
      );
      sentences = result.sentences;
      relatedWords = result.relatedWords;
      connection = ConnectionState.online;
      _cacheSentences(word, result);
    } catch (_) {
      connection = ConnectionState.offline;
      final cached = _getCachedSentences(word);
      if (cached != null) {
        sentences = cached.sentences;
        relatedWords = cached.relatedWords;
      }
    }
    loading = false;
    notifyListeners();
  }

  Future<void> selectSentence(String text) async {
    selectedSentence = text;
    notifyListeners();
    await tts.speak(text);
    api.speakLog(text: text, word: currentWord ?? '');
  }

  void clearOutput() {
    selectedSentence = null;
    notifyListeners();
  }

  Future<void> speakAgain() async {
    if (selectedSentence != null) {
      await tts.speak(selectedSentence!);
    }
  }

  Future<bool> toggleBookmark(Sentence sentence) async {
    final word = currentWord;
    if (word == null) return false;

    final existing = bookmarks.findFor(sentence.text, word);
    if (existing != null) {
      final ok = await bookmarks.remove(existing.id);
      if (ok) sentence.bookmarked = false;
      notifyListeners();
      return ok;
    } else {
      final bm = await bookmarks.add(
        text: sentence.text,
        word: word,
        category: currentCategoryName,
      );
      if (bm != null) sentence.bookmarked = true;
      notifyListeners();
      return bm != null;
    }
  }

  Future<void> handleVision(File imageFile) async {
    loading = true;
    sentences = [];
    relatedWords = [];
    currentWord = null;
    notifyListeners();

    try {
      final result = await api.vision(imageFile);
      currentWord = result.identifiedObject;
      sentences = result.sentences;
      relatedWords = result.relatedWords;
      connection = ConnectionState.online;
    } catch (_) {
      connection = ConnectionState.offline;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> handleTranscription(File audioFile) async {
    loading = true;
    notifyListeners();

    try {
      final result = await api.transcribe(audioFile);
      connection = ConnectionState.online;
      if (result.text.isNotEmpty) {
        final word = result.text.split(RegExp(r'\s+')).first;
        await selectWord(word);
        return;
      }
    } catch (_) {
      connection = ConnectionState.offline;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> setBackendUrl(String url) async {
    await api.setBackendUrl(url);
    await loadWords();
    await bookmarks.load();
  }

  // ── Offline caching ──

  void _cacheSentences(String word, GenerateResult result) {
    _sentenceCache[word.toLowerCase()] = {
      'sentences': result.sentences.map((s) => {'text': s.text, 'bookmarked': s.bookmarked}).toList(),
      'related_words': result.relatedWords,
    };
    _persistSentenceCache();
  }

  GenerateResult? _getCachedSentences(String word) {
    final data = _sentenceCache[word.toLowerCase()];
    if (data == null) return null;
    return GenerateResult(
      sentences: (data['sentences'] as List)
          .map((s) => Sentence.fromJson(s as Map<String, dynamic>))
          .toList(),
      relatedWords: (data['related_words'] as List).cast<String>(),
    );
  }

  Future<void> _persistSentenceCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sentCache', jsonEncode(_sentenceCache));
  }

  Future<void> _loadSentenceCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('sentCache');
    if (raw == null) return;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _sentenceCache.clear();
    map.forEach((k, v) => _sentenceCache[k] = v as Map<String, dynamic>);
  }

  Future<void> _saveWordsCache() async {
    final prefs = await SharedPreferences.getInstance();
    final data = categories.map((c) => <String, dynamic>{
      'name': c.name,
      'color': c.color,
      'words': c.words.map((w) => <String, dynamic>{
        'text': w.text,
        'icon': w.icon,
        'position': w.position,
      }).toList(),
    }).toList();
    await prefs.setString('wordsCache', jsonEncode(data));
  }

  Future<void> _loadWordsCache() async {
    await _loadSentenceCache();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wordsCache');
    if (raw == null) return;
    final list = jsonDecode(raw) as List<dynamic>;
    categories = list
        .map((c) => Category.fromJson(c as Map<String, dynamic>))
        .toList();
    if (categories.isNotEmpty) {
      currentCategoryName = categories.first.name;
    }
  }

  void _useFallbackWords() {
    categories = [
      Category.fromJson({
        'name': 'Needs',
        'color': '#4CAF50',
        'words': [
          {'text': 'water', 'icon': 'ti-droplet', 'position': [0, 0]},
          {'text': 'food', 'icon': 'ti-soup', 'position': [0, 1]},
          {'text': 'bathroom', 'icon': 'ti-toilet-paper', 'position': [0, 2]},
          {'text': 'medicine', 'icon': 'ti-pill', 'position': [1, 0]},
          {'text': 'rest', 'icon': 'ti-bed', 'position': [1, 1]},
          {'text': 'help', 'icon': 'ti-help', 'position': [1, 2]},
        ],
      }),
    ];
    currentCategoryName = 'Needs';
  }
}
