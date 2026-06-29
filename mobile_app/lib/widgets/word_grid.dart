import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/fitzgerald_colors.dart';
import 'word_button.dart';

class WordGrid extends StatelessWidget {
  const WordGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final cat = state.currentCategory;
        final catColor = cat != null
            ? FitzgeraldColors.fromHex(cat.color)
            : FitzgeraldColors.needs;

        return Column(
          children: [
            // Panel header
            _PanelHeader(title: 'WORDS'),
            // Category tabs
            _CategoryTabs(
              categories: state.categories,
              selected: state.currentCategoryName,
              onSelect: state.selectCategory,
            ),
            // Word tiles grid
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  if (cat != null)
                    _WordTileGrid(
                      words: cat.words,
                      catColor: catColor,
                      selectedWord: state.currentWord,
                      onTap: (word) => state.selectWord(
                        word,
                        category: cat.name,
                      ),
                    ),
                  // Related words
                  if (state.relatedWords.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _RelatedChips(
                      words: state.relatedWords,
                      onTap: (word) => state.selectWord(word),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  const _PanelHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.grid_view, size: 16, color: theme.hintColor),
          const SizedBox(width: 7),
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.hintColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  final List categories;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _CategoryTabs({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final cat in categories) ...[
              _TabChip(
                label: cat.name,
                active: cat.name == selected,
                onTap: () => onSelect(cat.name),
              ),
              const SizedBox(width: 5),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? theme.colorScheme.primary
                : theme.dividerColor.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: active ? Colors.white : theme.hintColor,
          ),
        ),
      ),
    );
  }
}

class _WordTileGrid extends StatelessWidget {
  final List words;
  final Color catColor;
  final String? selectedWord;
  final ValueChanged<String> onTap;

  const _WordTileGrid({
    required this.words,
    required this.catColor,
    required this.selectedWord,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Sort by stable [row, col] position so buttons never move.
    final sorted = [...words]..sort((a, b) {
        final cmp = a.position[0].compareTo(b.position[0]);
        return cmp != 0 ? cmp : a.position[1].compareTo(b.position[1]);
      });

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 7,
      crossAxisSpacing: 7,
      childAspectRatio: 1.1,
      children: [
        for (final w in sorted)
          WordButton(
            word: w,
            categoryColor: catColor,
            selected: w.text == selectedWord,
            onTap: () => onTap(w.text),
          ),
      ],
    );
  }
}

class _RelatedChips extends StatelessWidget {
  final List<String> words;
  final ValueChanged<String> onTap;

  const _RelatedChips({required this.words, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            'RELATED WORDS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.hintColor,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final w in words)
              GestureDetector(
                onTap: () => onTap(w),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.2),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Text(
                    w,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
