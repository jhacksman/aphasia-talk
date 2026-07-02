import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Top bar: the selected sentence (visual verification before speaking),
/// clear, speak-again, connection dot, and settings.
class OutputBar extends StatelessWidget {
  const OutputBar({super.key, required this.state, required this.onSettings});

  final AppState state;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = state.selectedSentence.isNotEmpty;

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasText ? state.selectedSentence : 'Tap a word, then a sentence below…',
              style: TextStyle(
                fontSize: 20,
                fontWeight: hasText ? FontWeight.w600 : FontWeight.w400,
                fontStyle: hasText ? FontStyle.normal : FontStyle.italic,
                color: hasText
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
          if (hasText) ...[
            IconButton(
              onPressed: state.clearSelected,
              icon: const Icon(Icons.close),
              tooltip: 'Clear',
              iconSize: 26,
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: state.speakSelected,
              icon: const Icon(Icons.volume_up),
              label: const Text('Speak', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.blue,
                minimumSize: const Size(110, 48),
              ),
            ),
          ],
          const SizedBox(width: 8),
          _ConnectionDot(status: state.connection),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            iconSize: 24,
          ),
        ],
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ConnectionStatus.online => AppTheme.green,
      ConnectionStatus.offline => AppTheme.red,
      ConnectionStatus.unknown => Colors.grey,
    };
    final label = switch (status) {
      ConnectionStatus.online => 'Connected to the speech computer',
      ConnectionStatus.offline => 'Not connected — using saved sentences',
      ConnectionStatus.unknown => 'Checking connection',
    };
    return Semantics(
      label: label,
      child: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
