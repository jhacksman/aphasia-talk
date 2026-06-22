import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark.dart';
import '../models/category.dart';
import '../models/sentence.dart';

class GenerateResult {
  final List<Sentence> sentences;
  final List<String> relatedWords;

  const GenerateResult({required this.sentences, required this.relatedWords});
}

class VisionResult {
  final String identifiedObject;
  final double confidence;
  final List<Sentence> sentences;
  final List<String> relatedWords;

  const VisionResult({
    required this.identifiedObject,
    required this.confidence,
    required this.sentences,
    required this.relatedWords,
  });
}

class TranscribeResult {
  final String text;
  final double confidence;

  const TranscribeResult({required this.text, required this.confidence});
}

class ApiService {
  static const _backendKey = 'backendUrl';
  static const _defaultUrl = 'http://localhost:8080';

  String _baseUrl = _defaultUrl;

  String get baseUrl => _baseUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_backendKey) ?? _defaultUrl;
  }

  Future<void> setBackendUrl(String url) async {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendKey, _baseUrl);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<bool> healthCheck() async {
    try {
      final resp = await http.get(_uri('/health')).timeout(
        const Duration(seconds: 5),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Category>> getWords() async {
    final resp = await http.get(_uri('/words')).timeout(
      const Duration(seconds: 10),
    );
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['categories'] as List<dynamic>)
        .map((c) => Category.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<GenerateResult> generate({
    required String word,
    String? category,
    List<String> bookmarkedSentences = const [],
    List<String> historyContext = const [],
  }) async {
    final resp = await http
        .post(
          _uri('/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'word': word,
            if (category != null) 'category': category, // ignore: use_null_aware_elements
            'bookmarked_sentences': bookmarkedSentences,
            'history_context': historyContext,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return GenerateResult(
      sentences: (data['sentences'] as List<dynamic>)
          .map((s) => Sentence.fromJson(s as Map<String, dynamic>))
          .toList(),
      relatedWords: (data['related_words'] as List<dynamic>).cast<String>(),
    );
  }

  Future<VisionResult> vision(File imageFile) async {
    final request = http.MultipartRequest('POST', _uri('/vision'));
    request.files.add(
      await http.MultipartFile.fromPath('image', imageFile.path),
    );
    final streamed =
        await request.send().timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return VisionResult(
      identifiedObject: data['identified_object'] as String,
      confidence: (data['confidence'] as num).toDouble(),
      sentences: (data['sentences'] as List<dynamic>)
          .map((s) => Sentence.fromJson(s as Map<String, dynamic>))
          .toList(),
      relatedWords: (data['related_words'] as List<dynamic>).cast<String>(),
    );
  }

  Future<TranscribeResult> transcribe(File audioFile, {String format = 'wav'}) async {
    final request = http.MultipartRequest('POST', _uri('/transcribe'));
    request.files.add(
      await http.MultipartFile.fromPath('audio', audioFile.path),
    );
    request.fields['format'] = format;
    final streamed =
        await request.send().timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return TranscribeResult(
      text: data['text'] as String,
      confidence: (data['confidence'] as num).toDouble(),
    );
  }

  Future<List<Bookmark>> getBookmarks() async {
    final resp = await http.get(_uri('/bookmarks')).timeout(
      const Duration(seconds: 10),
    );
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['bookmarks'] as List<dynamic>)
        .map((b) => Bookmark.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  Future<Bookmark> addBookmark({
    required String text,
    required String word,
    String? category,
  }) async {
    final resp = await http
        .post(
          _uri('/bookmarks'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'text': text,
            'word': word,
            if (category != null) 'category': category, // ignore: use_null_aware_elements
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
    return Bookmark.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> deleteBookmark(int id) async {
    final resp = await http.delete(_uri('/bookmarks/$id')).timeout(
      const Duration(seconds: 10),
    );
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
  }

  Future<void> speakLog({required String text, required String word}) async {
    try {
      await http
          .post(
            _uri('/speak-log'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text, 'word': word}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort; ignore failures.
    }
  }
}
