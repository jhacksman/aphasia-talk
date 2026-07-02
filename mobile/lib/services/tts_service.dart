import 'package:flutter_tts/flutter_tts.dart';

/// Offline text-to-speech via system voices (SPEC.md: a communication aid
/// must speak without any network). Speech rate is slightly slower than
/// default so listeners have time to process.
class TtsService {
  TtsService([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _configured = true;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _configure();
    await _tts.stop(); // Replace anything mid-utterance; latest tap wins.
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
