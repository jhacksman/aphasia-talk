import 'package:flutter/material.dart';

import '../models/word.dart';

/// Maps tabler icon class names (ti-xxx) to Material icons.
IconData _iconFor(String tablerName) {
  const map = <String, IconData>{
    'ti-user': Icons.person_outline,
    'ti-users': Icons.people_outline,
    'ti-user-heart': Icons.family_restroom,
    'ti-stethoscope': Icons.medical_services_outlined,
    'ti-nurse': Icons.local_hospital_outlined,
    'ti-friends': Icons.handshake_outlined,
    'ti-droplet': Icons.water_drop_outlined,
    'ti-soup': Icons.restaurant_outlined,
    'ti-toilet-paper': Icons.bathroom_outlined,
    'ti-pill': Icons.medication_outlined,
    'ti-bed': Icons.bed_outlined,
    'ti-help': Icons.help_outline,
    'ti-mood-smile': Icons.sentiment_satisfied_outlined,
    'ti-mood-sad': Icons.sentiment_dissatisfied_outlined,
    'ti-mood-confuzed': Icons.psychology_outlined,
    'ti-mood-angry': Icons.mood_bad_outlined,
    'ti-mood-nervous': Icons.sentiment_very_dissatisfied_outlined,
    'ti-heart': Icons.favorite_outline,
    'ti-hand-stop': Icons.pan_tool_outlined,
    'ti-circle-check': Icons.check_circle_outline,
    'ti-circle-x': Icons.cancel_outlined,
    'ti-plus': Icons.add_circle_outline,
    'ti-phone-call': Icons.phone_outlined,
    'ti-repeat': Icons.replay_outlined,
    'ti-home': Icons.home_outlined,
    'ti-building-hospital': Icons.local_hospital_outlined,
    'ti-car': Icons.directions_car_outlined,
    'ti-sun': Icons.wb_sunny_outlined,
    'ti-bath': Icons.bathtub_outlined,
    'ti-sofa': Icons.weekend_outlined,
    'ti-clock': Icons.access_time_outlined,
    'ti-moon': Icons.nightlight_outlined,
    'ti-calendar': Icons.calendar_today_outlined,
    'ti-arrow-back': Icons.arrow_back_outlined,
    'ti-arrow-forward': Icons.arrow_forward_outlined,
    'ti-hand-wave': Icons.waving_hand_outlined,
    'ti-door-exit': Icons.exit_to_app_outlined,
    'ti-heart-handshake': Icons.volunteer_activism_outlined,
    'ti-mood-sorry': Icons.sentiment_neutral_outlined,
    'ti-hand-pointing': Icons.touch_app_outlined,
  };
  return map[tablerName] ?? Icons.label_outline;
}

class WordButton extends StatelessWidget {
  final Word word;
  final Color categoryColor;
  final bool selected;
  final VoidCallback onTap;

  const WordButton({
    super.key,
    required this.word,
    required this.categoryColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedBg = categoryColor.withValues(alpha: isDark ? 0.25 : 0.12);

    return Material(
      color: selected ? selectedBg : theme.scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? categoryColor
                  : theme.dividerColor.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          constraints: const BoxConstraints(minHeight: 80),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _iconFor(word.icon),
                size: 28,
                color: categoryColor,
              ),
              const SizedBox(height: 4),
              Text(
                word.text,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
