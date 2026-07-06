import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// The Ask-mode question strip: shows the latest question someone asked the user,
/// tappable to get candidate replies.
///
/// The strip's space is ALWAYS reserved (empty state is a quiet placeholder)
/// so the grid and buttons below never shift — motor-planning stability.
/// Nothing here auto-dismisses; a new question replaces the old, and the
/// dismiss button only hides the card.
class QuestionStrip extends StatelessWidget {
  const QuestionStrip({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = state.currentQuestion;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: question == null
          ? Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'When someone asks a question, it will appear here.',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Show ways to reply to: $question',
                    child: Material(
                      color: AppTheme.purple.withValues(alpha: 0.10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppTheme.purple, width: 1.5),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: state.respondToQuestion,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.help_outline, color: AppTheme.purple, size: 24),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  question,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'tap to reply',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.purple,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: state.dismissQuestion,
                  icon: const Icon(Icons.close),
                  tooltip: 'Dismiss question',
                ),
              ],
            ),
    );
  }
}
