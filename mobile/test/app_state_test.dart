import 'dart:convert';

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

MockClient healthyBackend({List<String> sentences = const ['I am thirsty.']}) {
  return MockClient((request) async {
    switch (request.url.path) {
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
