import 'dart:convert';
import 'dart:typed_data';

import 'package:aphasia_talk/services/api_service.dart';
import 'package:aphasia_talk/services/settings_service.dart';
import 'package:aphasia_talk/services/tts_service.dart';
import 'package:aphasia_talk/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records which voice path was used instead of touching platform channels.
class _RecordingTts extends TtsService {
  _RecordingTts() : super(FlutterTts());
  final systemSpoken = <String>[];
  final wavPlayed = <Uint8List>[];

  @override
  Future<void> speak(String text) async => systemSpoken.add(text);

  @override
  Future<void> playWav(Uint8List wavBytes) async => wavPlayed.add(wavBytes);

  @override
  Future<void> stop() async {}
}

Future<AppState> buildState(MockClient client, {String voiceMode = 'fast'}) async {
  SharedPreferences.setMockInitialValues({'voiceMode': voiceMode});
  final settings = await SettingsService.load();
  return AppState(
    api: ApiService(baseUrl: 'http://spark:8080', client: client),
    settings: settings,
    tts: _RecordingTts(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fakeWav = [0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4]; // "RIFF"...

  MockClient backendWithTts({bool ttsWorks = true}) => MockClient((request) async {
        if (request.url.path == '/tts') {
          return ttsWorks
              ? http.Response.bytes(fakeWav, 200, headers: {'content-type': 'audio/wav'})
              : http.Response('down', 503);
        }
        if (request.url.path == '/speak-log') return http.Response('{}', 200);
        return http.Response(jsonEncode({'bookmarks': [], 'categories': []}), 200);
      });

  test('fast mode uses the system voice, never the network', () async {
    var ttsCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/tts') ttsCalls++;
      return http.Response('{}', 200);
    });
    final state = await buildState(client, voiceMode: 'fast');
    await state.speakSentence('I am thirsty.');
    final tts = state.tts as _RecordingTts;
    expect(tts.systemSpoken, ['I am thirsty.']);
    expect(tts.wavPlayed, isEmpty);
    expect(ttsCalls, 0);
  });

  test('cloned mode fetches WAV from the backend and plays it', () async {
    final state = await buildState(backendWithTts(), voiceMode: 'cloned');
    await state.speakSentence('I am thirsty.');
    final tts = state.tts as _RecordingTts;
    expect(tts.wavPlayed, hasLength(1));
    expect(tts.wavPlayed.single.sublist(0, 4), [0x52, 0x49, 0x46, 0x46]);
    expect(tts.systemSpoken, isEmpty);
  });

  test('cloned mode falls back to the system voice when the Spark fails', () async {
    final state = await buildState(backendWithTts(ttsWorks: false), voiceMode: 'cloned');
    await state.speakSentence('I am thirsty.');
    final tts = state.tts as _RecordingTts;
    expect(tts.wavPlayed, isEmpty);
    expect(tts.systemSpoken, ['I am thirsty.'],
        reason: 'speech must never fail silently');
  });

  test('voice mode persists in settings', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.load();
    expect(settings.voiceMode, 'fast', reason: 'fast is the safe default');
    await settings.setVoiceMode('cloned');
    expect(settings.voiceMode, 'cloned');
  });
}
