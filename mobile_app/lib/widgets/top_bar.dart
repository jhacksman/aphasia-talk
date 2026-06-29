import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final theme = Theme.of(context);
        final hasSentence = state.selectedSentence != null;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.2),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: hasSentence
                    ? Text(
                        state.selectedSentence!,
                        style: theme.textTheme.bodyLarge,
                      )
                    : Text(
                        'Tap a word, then a sentence below\u2026',
                        style: TextStyle(
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          color: theme.hintColor,
                        ),
                      ),
              ),
              if (hasSentence) ...[
                IconButton(
                  onPressed: state.clearOutput,
                  icon: const Icon(Icons.close),
                  color: theme.hintColor,
                  tooltip: 'Clear',
                ),
                FilledButton.icon(
                  onPressed: state.speakAgain,
                  icon: const Icon(Icons.volume_up, size: 17),
                  label: const Text('Speak'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
