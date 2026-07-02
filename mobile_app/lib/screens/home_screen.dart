import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_state.dart' hide ConnectionState;
import '../app_state.dart' as app;
import '../services/audio_service.dart';
import '../widgets/input_bar.dart';
import '../widgets/sentence_list.dart';
import '../widgets/top_bar.dart';
import '../widgets/word_grid.dart';
import 'keyboard_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioService _audio = AudioService();
  final ImagePicker _picker = ImagePicker();
  bool _micActive = false;

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    final state = context.read<AppState>();

    if (_micActive) {
      setState(() => _micActive = false);
      final file = await _audio.stopRecording();
      if (file != null) {
        await state.handleTranscription(file);
      }
      return;
    }

    final hasPermission = await _audio.hasPermission();
    if (!hasPermission) return;

    setState(() => _micActive = true);
    await _audio.startRecording();
  }

  Future<void> _takePhoto() async {
    final state = context.read<AppState>();
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    await state.handleVision(File(picked.path));
  }

  void _openKeyboard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const KeyboardScreen(),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SettingsScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final isOnline = state.connection == app.ConnectionState.online;
        final isOffline = state.connection == app.ConnectionState.offline;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // App header
                _AppHeader(
                  isOnline: isOnline,
                  isOffline: isOffline,
                  onSettings: _openSettings,
                ),
                const SizedBox(height: 10),
                // Output bar (selected sentence)
                const TopBar(),
                const SizedBox(height: 10),
                // Main two-pane layout
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        // Left pane: Word grid
                        Expanded(
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: const WordGrid(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Right pane: Sentences
                        Expanded(
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: const SentenceList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Bottom input bar
                InputBar(
                  micActive: _micActive,
                  onDictate: _toggleMic,
                  onPhoto: _takePhoto,
                  onKeyboard: _openKeyboard,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppHeader extends StatelessWidget {
  final bool isOnline;
  final bool isOffline;
  final VoidCallback onSettings;

  const _AppHeader({
    required this.isOnline,
    required this.isOffline,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aphasia Talk', style: theme.textTheme.headlineSmall),
              Text(
                'Tap a word, then tap a sentence to speak',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ],
          ),
          const Spacer(),
          // Connection indicator
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline
                  ? Colors.green
                  : isOffline
                      ? Colors.red
                      : theme.hintColor,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings),
            color: theme.hintColor,
          ),
        ],
      ),
    );
  }
}
