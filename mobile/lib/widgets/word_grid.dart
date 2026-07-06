import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/icon_map.dart';

/// Left pane: category tabs + the motor-stable word grid + related-word chips.
///
/// Words render strictly in their stored [row, col] order and the grid never
/// reflows based on usage — position stability is what lets the user build muscle
/// memory (SPEC.md: buttons never move).
class WordsPane extends StatelessWidget {
  const WordsPane({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = state.activeCategory;

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
          _paneHeader(theme, Icons.grid_view, 'WORDS'),
          if (state.categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in state.categories)
                    _CategoryTab(
                      category: c,
                      active: c.name == state.activeCategory?.name,
                      onTap: () => state.selectCategory(c.name),
                    ),
                ],
              ),
            ),
          Expanded(
            child: category == null
                ? _emptyGrid(theme)
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WordGrid(
                          category: category,
                          selectedWord: state.currentWord,
                          onTap: (w) => state.selectWord(w.text, category: category.name),
                        ),
                        if (state.relatedWords.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                            child: Text(
                              'RELATED WORDS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final w in state.relatedWords)
                                ActionChip(
                                  label: Text(w, style: const TextStyle(fontSize: 16)),
                                  onPressed: () => state.selectWord(w),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyGrid(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Connect to the speech computer in Settings to load the words.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      );

  Widget _paneHeader(ThemeData theme, IconData icon, String title) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({required this.category, required this.active, required this.onTap});

  final WordCategory category;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: active ? AppTheme.blue : theme.colorScheme.surface,
      shape: StadiumBorder(
        side: BorderSide(color: active ? AppTheme.blue : theme.dividerColor),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            category.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _WordGrid extends StatelessWidget {
  const _WordGrid({required this.category, required this.selectedWord, required this.onTap});

  final WordCategory category;
  final String? selectedWord;
  final void Function(Word) onTap;

  @override
  Widget build(BuildContext context) {
    final catColor = AppTheme.hex(category.colorHex);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 3 columns when there's room, 2 when narrow — computed from width,
        // never from usage, so positions stay put.
        final columns = constraints.maxWidth >= 340 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 84,
          ),
          itemCount: category.words.length,
          itemBuilder: (context, i) {
            final word = category.words[i];
            return _WordTile(
              word: word,
              color: catColor,
              selected: word.text == selectedWord,
              onTap: () => onTap(word),
            );
          },
        );
      },
    );
  }
}

class _WordTile extends StatelessWidget {
  const _WordTile({
    required this.word,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Word word;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Word: ${word.text}',
      child: Material(
        color: selected
            ? AppTheme.blue.withValues(alpha: 0.12)
            : theme.scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? AppTheme.blue : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconFor(word.icon), size: 28, color: color),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  word.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
