import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

/// Offline text-to-speech via system voices (SPEC.md: a communication aid
/// must speak without any network). Speech rate is slightly slower than
/// default so listeners have time to process.
class TtsService {
  TtsService([FlutterTts? tts, AudioPlayer? player])
      : _tts = tts ?? FlutterTts(),
        _playerOverride = player;

  final FlutterTts _tts;
  final AudioPlayer? _playerOverride;
  // Lazy: AudioPlayer touches platform channels at construction, so it is
  // only created when cloned-voice playback is actually used.
  AudioPlayer? _lazyPlayer;
  bool _configured = false;

  AudioPlayer get _player => _playerOverride ?? (_lazyPlayer ??= AudioPlayer());

  Future<void> _configure() async {
    if (_configured) return;
    if (!kIsWeb && Platform.isIOS) {
      // Without this, iOS uses the soloAmbient session category, which the
      // ring/silent switch mutes — the app would go silent exactly when the
      // family's iPad has the mute switch on. Playback + spokenAudio keeps
      // speech audible regardless of the switch, and re-asserting it also
      // recovers the session after the dictation recorder changes it.
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.spokenAudio,
      );
    }
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _configured = true;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _configure();
    await stop(); // Replace anything mid-utterance; latest tap wins.
    await _tts.speak(text);
  }

  /// Play cloned-voice WAV audio from the backend. Same latest-tap-wins
  /// rule as [speak].
  Future<void> playWav(Uint8List wavBytes) async {
    await _configure(); // Audio session must allow playback in silent mode.
    await stop();
    await _player.play(BytesSource(wavBytes, mimeType: 'audio/wav'));
  }

  Future<void> stop() async {
    await _tts.stop();
    // Only stop the player if it was ever created — never construct it here.
    final player = _playerOverride ?? _lazyPlayer;
    if (player != null) await player.stop();
  }
}
