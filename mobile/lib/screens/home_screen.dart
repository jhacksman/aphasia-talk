import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../state/app_state.dart';
import '../widgets/input_bar.dart';
import '../widgets/output_bar.dart';
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

  AppState get state => widget.state;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleDictation() async {
    if (_recording) {
      setState(() => _recording = false);
      final path = await _recorder.stop();
      if (path == null) return;
      final bytes = await _readFileBytes(path);
      if (bytes == null || !mounted) return;
      final text = await state.submitDictation(bytes);
      if (text == null && mounted) {
        _notice('I couldn\'t hear that. Please try again.');
      }
      return;
    }
    if (!await _recorder.hasPermission()) {
      _notice('Microphone permission is needed for dictation.');
      return;
    }
    final dir = await getTemporaryDirectory();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: '${dir.path}/dictation.wav',
    );
    if (mounted) setState(() => _recording = true);
  }

  Future<List<int>?> _readFileBytes(String path) async {
    try {
      final file = await XFile(path).readAsBytes();
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _takePhoto() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (image == null) return; // She backed out of the camera — fine.
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

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
