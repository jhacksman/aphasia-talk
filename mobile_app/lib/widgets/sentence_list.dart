import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'sentence_tile.dart';

class SentenceList extends StatelessWidget {
  const SentenceList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final theme = Theme.of(context);

        return Column(
          children: [
            // Panel header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.chat_bubble_outline, size: 16, color: theme.hintColor),
                  const SizedBox(width: 7),
                  Text(
                    'SENTENCES',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                  if (state.currentWord != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      state.currentWord!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Content
            Expanded(child: _buildContent(context, state)),
          ],
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, AppState state) {
    final theme = Theme.of(context);

    if (state.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Finding the words\u2026',
              style: TextStyle(color: theme.hintColor),
            ),
          ],
        ),
      );
    }

    if (state.sentences.isEmpty && state.currentWord == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 40,
              color: theme.hintColor,
            ),
            const SizedBox(height: 10),
            Text(
              'Tap a word on the left and\nsentences will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.hintColor,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    if (state.sentences.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: theme.hintColor),
            const SizedBox(height: 10),
            Text(
              'Can\'t reach the speech computer.\nCheck settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.hintColor,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: state.sentences.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final sentence = state.sentences[index];
        return SentenceTile(
          sentence: sentence,
          onTap: () => state.selectSentence(sentence.text),
          onBookmark: () => state.toggleBookmark(sentence),
        );
      },
    );
  }
}
