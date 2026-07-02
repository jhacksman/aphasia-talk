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
    await _speak(text);
    await api.logSpoken(text, currentWord);
  }

  Future<void> speakSelected() async {
    if (selectedSentence.isNotEmpty) await _speak(selectedSentence);
  }

  /// Route to the configured voice. The cloned voice needs the Spark; any
  /// failure falls back to the on-device voice so she is never left silent.
  Future<void> _speak(String text) async {
    if (settings.voiceMode == 'cloned') {
      try {
        final wav = await api.ttsAudio(text);
        await tts.playWav(Uint8List.fromList(wav));
        _setConnection(ConnectionStatus.online);
        return;
      } catch (_) {
        // Fall through to the system voice — speech must never fail.
      }
    }
    await tts.speak(text);
  }

  void clearSelected() {
    selectedSentence = '';
    notifyListeners();
  }

  bool isBookmarked(String text) => bookmarks.any((b) => b.text == text);

  /// Single source of truth for the star UI: the server flag on the sentence
  /// OR a local bookmark record. toggleBookmark uses the same predicate, so
  /// display and action can never disagree.
  bool isStarred(Sentence sentence) =>
      sentence.bookmarked || isBookmarked(sentence.text);

  /// Sentences currently being toggled — blocks double-taps (likely with
  /// impaired motor control) from firing duplicate add/delete requests.
  final Set<String> _togglesInFlight = {};

  Future<void> toggleBookmark(Sentence sentence) async {
    if (!_togglesInFlight.add(sentence.text)) return;
    try {
      if (isStarred(sentence)) {
        await _removeBookmark(sentence);
      } else {
        await _addBookmark(sentence);
      }
      await settings.cacheBookmarks(bookmarks);
      _setConnection(ConnectionStatus.online);
    } on ApiException catch (e) {
      // Only a network-level failure means offline; a 4xx answer means the
      // backend is reachable and simply rejected this request.
      if (!e.isServerResponse) _setConnection(ConnectionStatus.offline);
    } finally {
      _togglesInFlight.remove(sentence.text);
      notifyListeners();
    }
  }

  Future<void> _addBookmark(Sentence sentence) async {
    final word = (currentWord ?? '').trim().isEmpty ? 'this' : currentWord!;
    final created =
        await api.addBookmark(sentence.text, word, category: currentCategory);
    bookmarks = [...bookmarks, created];
    _setSentenceFlag(sentence.text, true);
  }

  Future<void> _removeBookmark(Sentence sentence) async {
    var matches = bookmarks.where((b) => b.text == sentence.text).toList();
    if (matches.isEmpty) {
      // Starred via the server flag but missing locally (fresh install or a
      // stale cache) — refresh the list to find the record to delete.
      bookmarks = await api.fetchBookmarks();
      matches = bookmarks.where((b) => b.text == sentence.text).toList();
    }
    for (final match in matches) {
      try {
        await api.deleteBookmark(match.id);
      } on ApiException catch (e) {
        // 404 = already gone (deleted from another device) — that's success.
        if (e.statusCode != 404) rethrow;
      }
    }
    final removedIds = matches.map((b) => b.id).toSet();
    bookmarks = bookmarks.where((b) => !removedIds.contains(b.id)).toList();
    _setSentenceFlag(sentence.text, false);
  }

  void _setSentenceFlag(String text, bool bookmarked) {
    sentences = [
      for (final s in sentences)
        s.text == text ? s.copyWith(bookmarked: bookmarked) : s,
    ];
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
    // Participate in the same ordering as word taps: if she taps a grid word
    // while transcription is in flight, the dictation result is stale and
    // must not clobber the newer selection.
    final seq = _requestSeq;
    try {
      final result = await api.transcribe(audioBytes, format: format);
      _setConnection(ConnectionStatus.online);
      if (seq != _requestSeq) return null; // Superseded by a newer tap.
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

  /// Returns true if the new backend answered a quick health probe. On an
  /// unreachable address we still save the URL but skip the full reload, so
  /// a typo fails in ~6s instead of stacking 30s request timeouts.
  Future<bool> updateBackendUrl(String url) async {
    await settings.setBackendUrl(url);
    api.baseUrl = url;
    connection = ConnectionStatus.unknown;
    notifyListeners();
    final reachable = await api.health();
    if (!reachable) {
      _setConnection(ConnectionStatus.offline);
      return false;
    }
    await init();
    return true;
  }

  void _setConnection(ConnectionStatus status) {
    if (connection != status) {
      connection = status;
      // The dot must update even on paths that don't otherwise notify
      // (e.g. a failed dictation never reaches selectWord's notify).
      notifyListeners();
    }
  }
}
