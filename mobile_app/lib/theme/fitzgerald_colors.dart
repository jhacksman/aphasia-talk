import 'package:flutter/material.dart';

/// Fitzgerald Key color coding for AAC word categories.
class FitzgeraldColors {
  static const people = Color(0xFFF5D63D);     // yellow
  static const needs = Color(0xFF4CAF50);       // green
  static const feelings = Color(0xFF2196F3);    // blue
  static const actions = Color(0xFF4CAF50);     // green (verbs)
  static const places = Color(0xFF9C27B0);      // purple
  static const time = Color(0xFFFF9800);        // orange
  static const social = Color(0xFFE91E63);      // pink

  static const _map = <String, Color>{
    'People': people,
    'Needs': needs,
    'Feelings': feelings,
    'Actions': actions,
    'Places': places,
    'Time': time,
    'Social': social,
  };

  static Color forCategory(String name) => _map[name] ?? needs;

  /// Parse a hex color string like "#F5D63D" from the backend.
  static Color fromHex(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    if (h.length == 8) return Color(int.parse(h, radix: 16));
    return needs;
  }
}
