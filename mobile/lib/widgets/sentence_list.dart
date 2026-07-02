import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Right pane: generated sentences. Tap the sentence to speak it; tap the
/// star to save it. Bookmarked sentences arrive pinned to the top from the
/// backend and are marked with a gold star.
class SentencesPane extends StatelessWidget {
  const SentencesPane({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(
                  'SENTENCES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                if (state.currentWord != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      state.currentWord!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.blue,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    switch (state.sentencesStatus) {
      case SentencesStatus.loading:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Finding the words…', style: TextStyle(fontSize: 16)),
            ],
          ),
        );
      case SentencesStatus.welcome:
        return _message(theme, Icons.chat_bubble_outline,
            'Tap a word on the left and sentences will appear here.');
      case SentencesStatus.empty:
        return _message(theme, Icons.refresh,
            'No sentences came back. Please tap the word again.');
      case SentencesStatus.offline:
        return _message(theme, Icons.cloud_off_outlined,
            'Can\'t reach the speech computer. Check that it\'s on, or open Settings.');
      case SentencesStatus.ready:
        return ListView.separated(
          padding: const EdgeInsets.all(8),
          itemCount: state.sentences.length,
          separatorBuilder: (context, index) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final sentence = state.sentences[i];
            return _SentenceTile(
              text: sentence.text,
              bookmarked: sentence.bookmarked || state.isBookmarked(sentence.text),
              onSpeak: () => state.speakSentence(sentence.text),
              onToggleBookmark: () => state.toggleBookmark(sentence),
            );
          },
        );
    }
  }

  Widget _message(ThemeData theme, IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      );
}

class _SentenceTile extends StatelessWidget {
  const _SentenceTile({
    required this.text,
    required this.bookmarked,
    required this.onSpeak,
    required this.onToggleBookmark,
  });

  final String text;
  final bool bookmarked;
  final VoidCallback onSpeak;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: bookmarked ? AppTheme.gold : theme.dividerColor,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onSpeak,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              const Icon(Icons.volume_up_outlined, size: 22, color: AppTheme.green),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Say: $text',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      text,
                      style: const TextStyle(fontSize: 17, height: 1.35),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onToggleBookmark,
                iconSize: 24,
                tooltip: bookmarked ? 'Remove from saved' : 'Save this sentence',
                icon: Icon(
                  bookmarked ? Icons.star : Icons.star_border,
                  color: bookmarked
                      ? AppTheme.gold
                      : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
