import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/models.dart';

/// Thrown for any failure reaching or parsing the backend; the UI shows a
/// friendly offline state and falls back to cached data.
///
/// [statusCode] is set when the server answered with a non-2xx status —
/// meaning the backend is reachable and the request itself was rejected.
/// It is null for network-level failures (timeout, refused, DNS), which are
/// the only ones that should flip the app to "offline".
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  /// True when the backend answered (so the network is fine).
  bool get isServerResponse => statusCode != null;

  @override
  String toString() => 'ApiException: $message';
}

/// HTTP client for the FastAPI backend on the DGX Spark.
///
/// Takes an injectable [http.Client] so tests can run against canned
/// responses with no network.
class ApiService {
  ApiService({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// e.g. "http://192.168.1.50:8080" — trailing slash tolerated.
  String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  Uri _uri(String path) {
    final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<Map<String, dynamic>> _decode(http.Response resp) async {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // Surface the backend's caregiver-facing `detail` message (e.g. "That
      // clip is too short…") instead of an opaque HTTP code.
      throw ApiException(
        _detailFrom(resp) ?? 'HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw const ApiException('Bad response from server');
    }
  }

  String? _detailFrom(http.Response resp) {
    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      final detail = (body as Map<String, dynamic>)['detail'];
      return detail is String && detail.isNotEmpty ? detail : null;
    } catch (_) {
      return null;
    }
  }

  /// Shared multipart POST used by vision, transcribe, and voice upload.
  Future<Map<String, dynamic>> _multipart(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    MediaType? contentType,
    Map<String, String> fields = const {},
    Duration? timeout,
  }) {
    final request = http.MultipartRequest('POST', _uri(path))
      ..files.add(http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: filename,
        contentType: contentType,
      ))
      ..fields.addAll(fields);
    return _guard(() async {
      final streamed = await _client.send(request).timeout(timeout ?? _timeout);
      return _decode(await http.Response.fromStream(streamed));
    });
  }

  /// Quick reachability probe. Uses a short timeout by default so callers
  /// (e.g. saving a mistyped address in Settings) fail fast instead of
  /// stacking 30s timeouts.
  Future<bool> health({Duration timeout = const Duration(seconds: 6)}) async {
    try {
      final body =
          await _decode(await _client.get(_uri('/health')).timeout(timeout));
      return body['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<List<WordCategory>> fetchWords() async {
    final body = await _guard(() async =>
        _decode(await _client.get(_uri('/words')).timeout(_timeout)));
    return ((body['categories'] as List?) ?? const [])
        .map((c) => WordCategory.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<GenerateResult> generate(String word, {String? category}) async {
    final body = await _guard(() async => _decode(await _client
        .post(
          _uri('/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'word': word, 'category': category}),
        )
        .timeout(_timeout)));
    return GenerateResult.fromJson(body);
  }

  Future<VisionResult> vision(List<int> imageBytes, {String filename = 'photo.jpg'}) async {
    final body = await _multipart(
      '/vision',
      field: 'image',
      bytes: imageBytes,
      filename: filename,
      // Without this the part defaults to application/octet-stream, which
      // flows into the vision model's data URL and real vLLM rejects it.
      contentType: MediaType('image', 'jpeg'),
    );
    return VisionResult.fromJson(body);
  }

  Future<TranscribeResult> transcribe(List<int> audioBytes, {String format = 'wav'}) async {
    final body = await _multipart(
      '/transcribe?format=$format',
      field: 'audio',
      bytes: audioBytes,
      filename: 'audio.$format',
    );
    return TranscribeResult.fromJson(body);
  }

  /// Ask mode: a caregiver's spoken question to the user — transcribed and logged
  /// as a conversation turn on the backend.
  Future<AskResult> ask(List<int> audioBytes, {String format = 'wav'}) async {
    final request = http.MultipartRequest('POST', _uri('/ask?format=$format'))
      ..files.add(http.MultipartFile.fromBytes('audio', audioBytes, filename: 'question.$format'));
    final body = await _guard(() async {
      final streamed = await _client.send(request).timeout(_timeout);
      return _decode(await http.Response.fromStream(streamed));
    });
    return AskResult.fromJson(body);
  }

  /// Candidate replies to a question someone asked the user.
  Future<GenerateResult> respond(String question) async {
    final body = await _guard(() async => _decode(await _client
        .post(
          _uri('/respond'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'question': question}),
        )
        .timeout(_timeout)));
    return GenerateResult.fromJson(body);
  }

  /// Newest question someone asked the user, if any (restores the question strip
  /// after an app restart).
  Future<String?> latestHeardQuestion() async {
    final body = await _guard(() async =>
        _decode(await _client.get(_uri('/conversation?limit=10')).timeout(_timeout)));
    for (final turn in (body['turns'] as List?) ?? const []) {
      final t = turn as Map<String, dynamic>;
      if (t['role'] == 'heard') return t['text'] as String?;
    }
    return null;
  }

  Future<List<Bookmark>> fetchBookmarks() async {
    final body = await _guard(() async =>
        _decode(await _client.get(_uri('/bookmarks')).timeout(_timeout)));
    return ((body['bookmarks'] as List?) ?? const [])
        .map((b) => Bookmark.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  Future<Bookmark> addBookmark(String text, String word, {String? category}) async {
    final body = await _guard(() async => _decode(await _client
        .post(
          _uri('/bookmarks'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text, 'word': word, 'category': category}),
        )
        .timeout(_timeout)));
    return Bookmark.fromJson(body);
  }

  Future<void> deleteBookmark(int id) async {
    await _guard(() async =>
        _decode(await _client.delete(_uri('/bookmarks/$id')).timeout(_timeout)));
  }

  Future<Profile> fetchProfile() async {
    final body = await _guard(() async =>
        _decode(await _client.get(_uri('/profile')).timeout(_timeout)));
    return Profile.fromJson(body);
  }

  Future<Profile> updateProfile(Profile profile) async {
    final body = await _guard(() async => _decode(await _client
        .put(
          _uri('/profile'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(profile.toUpdateJson()),
        )
        .timeout(_timeout)));
    return Profile.fromJson(body);
  }

  // ── Cloned voice ──

  Future<VoiceStatus> voiceStatus() async {
    final body = await _guard(() async =>
        _decode(await _client.get(_uri('/voice')).timeout(_timeout)));
    return VoiceStatus.fromJson(body);
  }

  /// Upload her voice recording (wav/mp3). Backend normalizes and
  /// auto-transcribes it via whisper when no transcript is provided.
  Future<VoiceStatus> uploadVoiceReference(
    List<int> audioBytes, {
    required String filename,
    String? transcript,
  }) async {
    final body = await _multipart(
      '/voice/reference',
      field: 'audio',
      bytes: audioBytes,
      filename: filename,
      fields: {
        if (transcript != null && transcript.trim().isNotEmpty)
          'transcript': transcript.trim(),
      },
      // Reference processing includes a whisper pass — allow extra time.
      timeout: const Duration(seconds: 120),
    );
    return VoiceStatus.fromJson(body);
  }

  /// Speak `text` in the cloned voice; returns WAV bytes to play.
  ///
  /// Short timeout on purpose: warm synthesis of a sentence takes ~1-2s.
  /// If it's slower than this, silence-then-fallback is worse than falling
  /// back immediately — speech must feel dependable, not eventual.
  Future<List<int>> ttsAudio(
    String text, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    return _guard(() async {
      final resp = await _client
          .post(
            _uri('/tts'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw ApiException('HTTP ${resp.statusCode}', statusCode: resp.statusCode);
      }
      return resp.bodyBytes;
    });
  }

  /// Best-effort usage logging; never surfaces errors to the UI.
  Future<void> logSpoken(String text, String? word) async {
    try {
      await _client
          .post(
            _uri('/speak-log'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text, 'word': word}),
          )
          .timeout(_timeout);
    } catch (_) {/* ignore */}
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(e.toString());
    }
  }
}
