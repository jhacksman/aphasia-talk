import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bottom action bar: Dictate, Photo, Keyboard, Ask. Large targets, always
/// in the same order and position (Ask was appended after the original
/// three — existing button positions are immutable).
class InputBar extends StatelessWidget {
  const InputBar({
    super.key,
    required this.recording,
    required this.onDictate,
    required this.onPhoto,
    required this.onKeyboard,
    required this.asking,
    required this.onAsk,
  });

  final bool recording;
  final VoidCallback onDictate;
  final VoidCallback onPhoto;
  final VoidCallback onKeyboard;

  /// True while the Ask button is recording a caregiver's question.
  final bool asking;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionButton(
          icon: recording ? Icons.stop_circle_outlined : Icons.mic_none,
          label: recording ? 'Listening…' : 'Dictate',
          color: AppTheme.red,
          highlighted: recording,
          onTap: onDictate,
          semantics: recording
              ? 'Stop listening'
              : 'Dictate — tap, speak a word, then tap again',
        ),
        const SizedBox(width: 10),
        _ActionButton(
          icon: Icons.photo_camera_outlined,
          label: 'Photo',
          color: AppTheme.amber,
          onTap: onPhoto,
          semantics: 'Take a photo of something to talk about',
        ),
        const SizedBox(width: 10),
        _ActionButton(
          icon: Icons.keyboard_alt_outlined,
          label: 'Keyboard',
          color: AppTheme.blue,
          onTap: onKeyboard,
          semantics: 'Type a word',
        ),
        const SizedBox(width: 10),
        _ActionButton(
          icon: asking ? Icons.stop_circle_outlined : Icons.contact_support_outlined,
          label: asking ? 'Listening…' : 'Ask',
          color: AppTheme.purple,
          highlighted: asking,
          onTap: onAsk,
          semantics: asking
              ? 'Stop listening to the question'
              : 'Ask — for the conversation partner: tap, ask your question aloud, tap again',
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.semantics,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String semantics;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: semantics,
      child: Material(
        color: highlighted ? color.withValues(alpha: 0.12) : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: highlighted ? color : theme.dividerColor),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: 130,
              minHeight: AppTheme.minTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: highlighted ? color : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: highlighted ? color : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
