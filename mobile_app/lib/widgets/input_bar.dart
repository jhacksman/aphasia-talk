import 'package:flutter/material.dart';

class InputBar extends StatelessWidget {
  final bool micActive;
  final VoidCallback onDictate;
  final VoidCallback onPhoto;
  final VoidCallback onKeyboard;

  const InputBar({
    super.key,
    required this.micActive,
    required this.onDictate,
    required this.onPhoto,
    required this.onKeyboard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ActionButton(
            icon: Icons.mic,
            label: 'Dictate',
            active: micActive,
            activeColor: Colors.red,
            onTap: onDictate,
          ),
          const SizedBox(width: 10),
          _ActionButton(
            icon: Icons.camera_alt,
            label: 'Photo',
            activeColor: theme.colorScheme.tertiary,
            onTap: onPhoto,
          ),
          const SizedBox(width: 10),
          _ActionButton(
            icon: Icons.keyboard,
            label: 'Keyboard',
            activeColor: theme.colorScheme.primary,
            onTap: onKeyboard,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.active = false,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(maxWidth: 130),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.12)
              : theme.cardColor,
          border: Border.all(
            color: active
                ? activeColor
                : theme.dividerColor.withValues(alpha: 0.2),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 26,
              color: active ? activeColor : theme.hintColor,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? activeColor : theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
