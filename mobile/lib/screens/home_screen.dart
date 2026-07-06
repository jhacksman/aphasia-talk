import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../state/app_state.dart';
import '../widgets/input_bar.dart';
import '../widgets/output_bar.dart';
import '../widgets/question_strip.dart';
import '../widgets/sentence_list.dart';
import '../widgets/word_grid.dart';
import 'keyboard_sheet.dart';
import 'settings_sheet.dart';

/// The single main screen: output bar on top, two stable panes (words |
/// sentences), input actions below. No navigation, no mode switches —
/// overlays only (SPEC.md design rules).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final ImagePicker _picker = ImagePicker();
  bool _recording = false;

  /// Set synchronously on entry to _toggleDictation so a double-tap (likely
  /// with impaired motor control) can't start the recorder twice or stop a
  /// recorder that is still starting.
  bool _dictationBusy = false;

  /// Ask mode (caregiver question capture) shares the one recorder, so the
  /// two flows are mutually exclusive; same double-tap guard as dictation.
  bool _askRecording = false;
  bool _askBusy = false;

  AppState get state => widget.state;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleDictation() async {
    if (_dictationBusy || _askRecording || _askBusy) return;
    _dictationBusy = true;
    try {
      if (_recording) {
        await _stopDictation();
      } else {
        await _startDictation();
      }
    } finally {
      _dictationBusy = false;
    }
  }

  Future<void> _startDictation() async {
    if (!await _recorder.hasPermission()) {
      _notice('Microphone permission is needed for dictation.');
      return;
    }
    final dir = await getTemporaryDirectory();
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: '${dir.path}/dictation.wav',
      );
    } catch (_) {
      _notice('The microphone isn\'t available right now.');
      return;
    }
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _stopDictation() async {
    setState(() => _recording = false);
    final path = await _recorder.stop();
    List<int>? bytes;
    if (path != null) {
      try {
        bytes = await File(path).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      // Never leave the user at a silent dead-end: say what to do next.
      _notice('I couldn\'t hear that. Please try again.');
      return;
    }
    final text = await state.submitDictation(bytes);
    if (text == null && mounted) {
      _notice('I couldn\'t hear that. Please try again.');
    }
  }

  Future<void> _toggleAsk() async {
    if (_askBusy || _recording || _dictationBusy) return;
    _askBusy = true;
    try {
      if (_askRecording) {
        await _stopAsk();
      } else {
        await _startAsk();
      }
    } finally {
      _askBusy = false;
    }
  }

  Future<void> _startAsk() async {
    if (!await _recorder.hasPermission()) {
      _notice('Microphone permission is needed to capture a question.');
      return;
    }
    final dir = await getTemporaryDirectory();
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: '${dir.path}/question.wav',
      );
    } catch (_) {
      _notice('The microphone isn\'t available right now.');
      return;
    }
    if (mounted) setState(() => _askRecording = true);
  }

  Future<void> _stopAsk() async {
    setState(() => _askRecording = false);
    final path = await _recorder.stop();
    List<int>? bytes;
    if (path != null) {
      try {
        bytes = await File(path).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      _notice('I didn\'t catch the question. Please tap Ask and try again.');
      return;
    }
    final text = await state.submitAsk(bytes);
    if (text == null && mounted) {
      _notice('I didn\'t catch the question. Please tap Ask and try again.');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (image == null) return; // They backed out of the camera — fine.
      final bytes = await image.readAsBytes();
      await state.submitPhoto(bytes);
    } catch (_) {
      _notice('The camera isn\'t available right now.');
    }
  }

  void _openKeyboard() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => KeyboardSheet(onSubmit: (word) => state.selectWord(word)),
    );
  }

  Future<void> _openSettings() async {
    // Release the microphone before Settings opens: its voice-sample
    // recorder must never contend with a live dictation/Ask recording
    // (the sheet would cover the only buttons that could stop them).
    if (_recording || _askRecording) {
      await _recorder.cancel();
      if (mounted) {
        setState(() {
          _recording = false;
          _askRecording = false;
        });
      }
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Explicit Close button only: no drag/tap-away dismissal, so a
      // voice-sample recording can't be silently abandoned mid-take.
      isDismissible: false,
      enableDrag: false,
      builder: (_) => SettingsSheet(state: state),
    );
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontSize: 16))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: OutputBar(state: state, onSettings: _openSettings),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: QuestionStrip(state: state),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: WordsPane(state: state)),
                      const SizedBox(width: 10),
                      Expanded(child: SentencesPane(state: state)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: InputBar(
                  recording: _recording,
                  onDictate: _toggleDictation,
                  onPhoto: _takePhoto,
                  onKeyboard: _openKeyboard,
                  asking: _askRecording,
                  onAsk: _toggleAsk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
