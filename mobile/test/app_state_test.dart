import 'dart:convert';

import 'package:aphasia_talk/models/models.dart';
import 'package:aphasia_talk/services/api_service.dart';
import 'package:aphasia_talk/services/settings_service.dart';
import 'package:aphasia_talk/services/tts_service.dart';
import 'package:aphasia_talk/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TTS that records instead of speaking (no platform channel in tests).
class _FakeTts extends TtsService {
  _FakeTts() : super(FlutterTts());
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}
}

Future<AppState> buildState(MockClient client) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsService.load();
  return AppState(
    api: ApiService(baseUrl: 'http://spark:8080', client: client),
    settings: settings,
    tts: _FakeTts(),
  );
}

MockClient healthyBackend({
  List<String> sentences = const ['I am thirsty.'],
  String? heardQuestion,
}) {
  return MockClient((request) async {
    switch (request.url.path) {
      case '/ask':
        return http.Response(
          jsonEncode({'text': 'Are you hungry?', 'turn_id': 1}),
          200,
        );
      case '/respond':
        return http.Response(
          jsonEncode({
            'sentences': [
              {'text': 'Yes, please.', 'bookmarked': false},
              {'text': 'No, thank you.', 'bookmarked': false},
            ],
            'related_words': ['yes', 'no'],
          }),
          200,
        );
      case '/conversation':
        return http.Response(
          jsonEncode({
            'turns': [
              if (heardQuestion != null)
                {'id': 1, 'role': 'heard', 'text': heardQuestion, 'created_at': 'x'},
            ],
          }),
          200,
        );
      case '/words':
        return http.Response(
          jsonEncode({
            'categories': [
              {
                'name': 'Needs',
                'color': '#4CAF50',
                'words': [
                  {'text': 'water', 'icon': 'ti-droplet', 'position': [0, 0]},
                ],
              },
            ],
          }),
          200,
        );
      case '/bookmarks':
        return http.Response(jsonEncode({'bookmarks': []}), 200);
      case '/generate':
        return http.Response(
          jsonEncode({
            'sentences': [
              for (final s in sentences) {'text': s, 'bookmarked': false},
            ],
            'related_words': ['drink'],
          }),
          200,
        );
      case '/speak-log':
        return http.Response('{}', 200);
      default:
        return http.Response('not found', 404);
    }
  });
}

MockClient deadBackend() =>
    MockClient((request) async => http.Response('unreachable', 503));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('init loads words and goes online', () async {
    final state = await buildState(healthyBackend());
    await state.init();
    expect(state.connection, ConnectionStatus.online);
    expect(state.categories.single.name, 'Needs');
    expect(state.currentCategory, 'Needs');
  });

  test('selectWord populates sentences and related words', () async {
    final state = await buildState(healthyBackend());
    await state.init();
    await state.selectWord('water');
    expect(state.sentencesStatus, SentencesStatus.ready);
    expect(state.sentences.single.text, 'I am thirsty.');
    expect(state.relatedWords, ['drink']);
  });

  test('offline backend falls back to cached sentences from a previous run', () async {
    // First run online: caches words + sentences.
    final online = await buildState(healthyBackend());
    await online.init();
    await online.selectWord('water');

    // Second run offline, sharing the same mock preferences store.
    final offline = AppState(
      api: ApiService(baseUrl: 'http://spark:8080', client: deadBackend()),
      settings: online.settings,
      tts: _FakeTts(),
    );
    await offline.init();
    expect(offline.connection, ConnectionStatus.offline);
    expect(offline.categories, isNotEmpty, reason: 'word grid served from cache');

    await offline.selectWord('water');
    expect(offline.sentencesStatus, SentencesStatus.ready,
        reason: 'sentences served from cache');
    expect(offline.sentences.single.text, 'I am thirsty.');
  });

  test('offline with no cache shows the offline state, never throws', () async {
    final state = await buildState(deadBackend());
    await state.init();
    await state.selectWord('water');
    expect(state.sentencesStatus, SentencesStatus.offline);
  });

  test('speaking a sentence updates the output bar and speaks once', () async {
    final state = await buildState(healthyBackend());
    await state.init();
    await state.speakSentence('I am thirsty.');
    expect(state.selectedSentence, 'I am thirsty.');
    expect((state.tts as _FakeTts).spoken, ['I am thirsty.']);
  });

  test('server-pinned star with empty local list deletes instead of re-adding', () async {
    // Fresh install: /generate returns bookmarked=true but the local
    // bookmarks list is empty. Tapping the star must DELETE, not POST.
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      switch ('${request.method} ${request.url.path}') {
        case 'POST /generate':
          return http.Response(
            jsonEncode({
              'sentences': [
                {'text': 'Please get me water.', 'bookmarked': true},
              ],
              'related_words': <String>[],
            }),
            200,
          );
        case 'GET /bookmarks':
          return http.Response(
            jsonEncode({
              'bookmarks': [
                {'id': 3, 'text': 'Please get me water.', 'word': 'water'},
              ],
            }),
            200,
          );
        case 'DELETE /bookmarks/3':
          return http.Response(jsonEncode({'deleted': 3}), 200);
        default:
          return http.Response('{}', 200);
      }
    });

    final state = await buildState(client);
    await state.selectWord('water');
    expect(state.isStarred(state.sentences.single), isTrue);

    await state.toggleBookmark(state.sentences.single);

    expect(calls, contains('DELETE /bookmarks/3'));
    expect(calls.where((c) => c == 'POST /bookmarks'), isEmpty,
        reason: 'must not re-add an already-bookmarked sentence');
    expect(state.isStarred(state.sentences.single), isFalse);
  });

  test('DELETE 404 counts as removed and does not flip the app offline', () async {
    final client = MockClient((request) async {
      if (request.method == 'DELETE') {
        return http.Response('{"detail": "Bookmark not found"}', 404);
      }
      return http.Response(jsonEncode({'bookmarks': [], 'categories': []}), 200);
    });

    final state = await buildState(client);
    await state.init();
    state.bookmarks = [
      const Bookmark(id: 9, text: 'I am tired.', word: 'rest'),
    ];

    await state.toggleBookmark(const Sentence(text: 'I am tired.'));

    expect(state.bookmarks, isEmpty, reason: 'stale bookmark cleared locally');
    expect(state.connection, ConnectionStatus.online,
        reason: 'a 404 answer proves the backend is reachable');
  });

  test('double-tapping the star fires a single add request', () async {
    var posts = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/bookmarks') {
        posts += 1;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response(
          jsonEncode({
            'id': posts,
            'text': 'I am thirsty.',
            'word': 'water',
            'created_at': 'x',
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'bookmarks': [], 'categories': []}), 200);
    });

    final state = await buildState(client);
    await state.init();
    state.currentWord = 'water';
    const sentence = Sentence(text: 'I am thirsty.');

    await Future.wait([
      state.toggleBookmark(sentence),
      state.toggleBookmark(sentence),
    ]);

    expect(posts, 1, reason: 'second tap during flight must be ignored');
    expect(state.bookmarks, hasLength(1));
  });

  test('stale dictation result never clobbers a newer word tap', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/transcribe') {
        // Slow transcription: lands after the user has tapped a grid word.
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return http.Response(
            jsonEncode({'text': 'garden', 'confidence': 0.9}), 200);
      }
      if (request.url.path == '/generate') {
        final word = (jsonDecode(request.body) as Map)['word'] as String;
        return http.Response(
          jsonEncode({
            'sentences': [
              {'text': 'About $word', 'bookmarked': false},
            ],
            'related_words': <String>[],
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'bookmarks': [], 'categories': []}), 200);
    });

    final state = await buildState(client);
    final dictation = state.submitDictation([1, 2, 3]);
    await state.selectWord('help'); // The user gave up waiting and tapped a word.
    final dictated = await dictation;

    expect(dictated, isNull, reason: 'superseded dictation is discarded');
    expect(state.currentWord, 'help');
    expect(state.sentences.single.text, 'About help');
  });

  test('submitAsk stores the question for the strip', () async {
    final state = await buildState(healthyBackend());
    await state.init();
    final text = await state.submitAsk([1, 2, 3]);
    expect(text, 'Are you hungry?');
    expect(state.currentQuestion, 'Are you hungry?');
  });

  test('respondToQuestion fills the sentence pane with replies', () async {
    final state = await buildState(healthyBackend());
    await state.init();
    await state.submitAsk([1, 2, 3]);
    await state.respondToQuestion();
    expect(state.sentencesStatus, SentencesStatus.ready);
    expect(state.sentences.map((s) => s.text), contains('Yes, please.'));
    expect(state.currentWord, 'reply');
    expect(state.relatedWords, ['yes', 'no']);
  });

  test('init restores the latest heard question into the strip', () async {
    final state =
        await buildState(healthyBackend(heardQuestion: 'Do you want tea?'));
    await state.init();
    expect(state.currentQuestion, 'Do you want tea?');
  });

  test('dismissQuestion hides the card without touching sentences', () async {
    final state = await buildState(healthyBackend());
    await state.init();
    await state.submitAsk([1, 2, 3]);
    state.dismissQuestion();
    expect(state.currentQuestion, isNull);
  });

  test('failed ask goes offline and leaves no question', () async {
    final state = await buildState(deadBackend());
    expect(await state.submitAsk([1, 2, 3]), isNull);
    expect(state.currentQuestion, isNull);
    expect(state.connection, ConnectionStatus.offline);
  });

  test('updateBackendUrl fails fast on an unreachable address', () async {
    final state = await buildState(deadBackend());
    final ok = await state.updateBackendUrl('http://10.0.0.99:8080');
    expect(ok, isFalse);
    expect(state.connection, ConnectionStatus.offline);
  });

  test('a slower earlier request never overwrites a newer tap', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      if (request.url.path != '/generate') {
        return http.Response(jsonEncode({'bookmarks': [], 'categories': []}), 200);
      }
      callCount += 1;
      final word = (jsonDecode(request.body) as Map)['word'] as String;
      if (callCount == 1) {
        // First request is slow and lands after the second.
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      return http.Response(
        jsonEncode({
          'sentences': [
            {'text': 'About $word', 'bookmarked': false},
          ],
          'related_words': <String>[],
        }),
        200,
      );
    });

    final state = await buildState(client);
    final first = state.selectWord('water');
    final second = state.selectWord('help');
    await Future.wait([first, second]);

    expect(state.currentWord, 'help');
    expect(state.sentences.single.text, 'About help',
        reason: 'stale response for "water" must be discarded');
  });
}
