import 'package:flutter/material.dart';

import '../models/sentence.dart';

class SentenceTile extends StatelessWidget {
  final Sentence sentence;
  final VoidCallback onTap;
  final VoidCallback onBookmark;

  const SentenceTile({
    super.key,
    required this.sentence,
    required this.onTap,
    required this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goldColor = theme.colorScheme.tertiary;
    final greenColor = theme.colorScheme.secondary;

    return Material(
      color: theme.scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(
              color: sentence.bookmarked
                  ? goldColor
                  : theme.dividerColor.withValues(alpha: 0.15),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.volume_up, size: 20, color: greenColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sentence.text,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onBookmark,
                child: Icon(
                  sentence.bookmarked ? Icons.star : Icons.star_border,
                  size: 22,
                  color: sentence.bookmarked ? goldColor : theme.hintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
