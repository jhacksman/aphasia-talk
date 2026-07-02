import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';

enum ConnectionStatus { unknown, online, offline }

enum SentencesStatus { welcome, loading, ready, empty, offline }

/// Application state and interaction flow (SPEC.md):
/// tap word -> generate sentences -> tap sentence -> speak.
///
/// Everything degrades gracefully: if the Spark is unreachable we fall back
/// to cached grids/sentences and show a calm offline indicator — never an
/// error dialog in front of the primary user.
class AppState extends ChangeNotifier {
  AppState({
    required this.api,
    required this.settings,
    required this.tts,
  });

  final ApiService api;
  final SettingsService settings;
  final TtsService tts;

  ConnectionStatus connection = ConnectionStatus.unknown;
  SentencesStatus sentencesStatus = SentencesStatus.welcome;

  List<WordCategory> categories = const [];
  String? currentCategory;
  String? currentWord;
  List<Sentence> sentences = const [];
  List<String> relatedWords = const [];
  List<Bookmark> bookmarks = const [];
  String selectedSentence = '';

  /// Monotonic token so a stale generation response never overwrites a newer
  /// tap (she may tap a second word before the first request returns).
  int _requestSeq = 0;

  WordCategory? get activeCategory {
    for (final c in categories) {
      if (c.name == currentCategory) return c;
    }
    return categories.isEmpty ? null : categories.first;
  }

  Future<void> init() async {
    await Future.wait([_loadWords(), _loadBookmarks()]);
  }

  Future<void> _loadWords() async {
    try {
      categories = await api.fetchWords();
      _setConnection(ConnectionStatus.online);
      await settings.cacheWords(categories);
    } on ApiException {
      categories = settings.cachedWords() ?? const [];
      _setConnection(ConnectionStatus.offline);
    }
    currentCategory ??= categories.isEmpty ? null : categories.first.name;
    notifyListeners();
  }

  Future<void> _loadBookmarks() async {
    try {
      bookmarks = await api.fetchBookmarks();
      await settings.cacheBookmarks(bookmarks);
    } on ApiException {
      bookmarks = settings.cachedBookmarks();
    }
    notifyListeners();
  }

  void selectCategory(String name) {
    currentCategory = name;
    notifyListeners();
  }

  /// Core flow: tap a word, populate the sentences pane.
  Future<void> selectWord(String word, {String? category}) async {
    final seq = ++_requestSeq;
    currentWord = word;
    sentencesStatus = SentencesStatus.loading;
    sentences = const [];
    relatedWords = const [];
    notifyListeners();

    try {
      final result = await api.generate(word, category: category ?? currentCategory);
      if (seq != _requestSeq) return; // A newer tap superseded this request.
      sentences = result.sentences;
      relatedWords = result.relatedWords;
      sentencesStatus = sentences.isEmpty ? SentencesStatus.empty : SentencesStatus.ready;
      _setConnection(ConnectionStatus.online);
      await settings.cacheSentences(word, result);
    } on ApiException {
      if (seq != _requestSeq) return;
      final cached = settings.cachedSentences(word);
      if (cached != null && cached.sentences.isNotEmpty) {
        sentences = cached.sentences;
        relatedWords = cached.relatedWords;
        sentencesStatus = SentencesStatus.ready;
      } else {
        sentencesStatus = SentencesStatus.offline;
      }
      _setConnection(ConnectionStatus.offline);
    }
    notifyListeners();
  }

  /// Tap a sentence: show it in the output bar and speak it immediately.
  Future<void> speakSentence(String text) async {
    selectedSentence = text;
    notifyListeners();
    await tts.speak(text);
    await api.logSpoken(text, currentWord);
  }

  Future<void> speakSelected() async {
    if (selectedSentence.isNotEmpty) await tts.speak(selectedSentence);
  }

  void clearSelected() {
    selectedSentence = '';
    notifyListeners();
  }

  bool isBookmarked(String text) => bookmarks.any((b) => b.text == text);

  Future<void> toggleBookmark(Sentence sentence) async {
    final existing = bookmarks.where((b) => b.text == sentence.text).toList();
    try {
      if (existing.isNotEmpty) {
        await api.deleteBookmark(existing.first.id);
        bookmarks = bookmarks.where((b) => b.id != existing.first.id).toList();
      } else {
        final created = await api.addBookmark(
          sentence.text,
          currentWord ?? '',
          category: currentCategory,
        );
        bookmarks = [...bookmarks, created];
      }
      sentences = [
        for (final s in sentences)
          s.text == sentence.text ? s.copyWith(bookmarked: existing.isEmpty) : s,
      ];
      await settings.cacheBookmarks(bookmarks);
      _setConnection(ConnectionStatus.online);
    } on ApiException {
      _setConnection(ConnectionStatus.offline);
    }
    notifyListeners();
  }

  /// Photo flow: send image bytes, treat the identified object as the word.
  Future<void> submitPhoto(List<int> imageBytes) async {
    final seq = ++_requestSeq;
    currentWord = null;
    sentencesStatus = SentencesStatus.loading;
    sentences = const [];
    relatedWords = const [];
    notifyListeners();

    try {
      final result = await api.vision(imageBytes);
      if (seq != _requestSeq) return;
      currentWord = result.identifiedObject;
      sentences = result.sentences;
      relatedWords = result.relatedWords;
      sentencesStatus = sentences.isEmpty ? SentencesStatus.empty : SentencesStatus.ready;
      _setConnection(ConnectionStatus.online);
    } on ApiException {
      if (seq != _requestSeq) return;
      sentencesStatus = SentencesStatus.offline;
      _setConnection(ConnectionStatus.offline);
    }
    notifyListeners();
  }

  /// Dictation flow: transcribe recorded audio, then run the word flow.
  Future<String?> submitDictation(List<int> audioBytes, {String format = 'wav'}) async {
    try {
      final result = await api.transcribe(audioBytes, format: format);
      _setConnection(ConnectionStatus.online);
      final text = result.text.trim();
      if (text.isEmpty) return null;
      // Use the first word she said as the generation seed.
      final word = text.split(RegExp(r'\s+')).first;
      await selectWord(word);
      return text;
    } on ApiException {
      _setConnection(ConnectionStatus.offline);
      return null;
    }
  }

  Future<void> updateBackendUrl(String url) async {
    await settings.setBackendUrl(url);
    api.baseUrl = url;
    connection = ConnectionStatus.unknown;
    notifyListeners();
    await init();
  }

  void _setConnection(ConnectionStatus status) {
    if (connection != status) {
      connection = status;
    }
  }
}
