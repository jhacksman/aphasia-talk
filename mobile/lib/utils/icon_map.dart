import 'package:flutter/material.dart';

/// Maps the backend's Tabler icon names (used by the web client) to Material
/// icons so the same /words payload renders on both clients. Unknown names
/// fall back to a neutral chat icon rather than breaking the grid.
const Map<String, IconData> _tablerToMaterial = {
  // People
  'ti-user': Icons.person_outline,
  'ti-users': Icons.people_outline,
  'ti-user-heart': Icons.favorite_border,
  'ti-stethoscope': Icons.medical_services_outlined,
  'ti-nurse': Icons.health_and_safety_outlined,
  'ti-friends': Icons.handshake_outlined,
  // Needs
  'ti-droplet': Icons.water_drop_outlined,
  'ti-soup': Icons.restaurant_outlined,
  'ti-toilet-paper': Icons.wc_outlined,
  'ti-pill': Icons.medication_outlined,
  'ti-bed': Icons.bed_outlined,
  'ti-help': Icons.help_outline,
  'ti-flame': Icons.local_fire_department_outlined,
  // Feelings
  'ti-mood-smile': Icons.sentiment_satisfied_outlined,
  'ti-mood-sad': Icons.sentiment_dissatisfied_outlined,
  'ti-mood-confuzed': Icons.psychology_alt_outlined,
  'ti-mood-angry': Icons.sentiment_very_dissatisfied_outlined,
  'ti-mood-nervous': Icons.sentiment_neutral_outlined,
  'ti-heart': Icons.favorite_outline,
  // Actions
  'ti-hand-stop': Icons.front_hand_outlined,
  'ti-circle-check': Icons.check_circle_outline,
  'ti-circle-x': Icons.cancel_outlined,
  'ti-plus': Icons.add_circle_outline,
  'ti-phone-call': Icons.call_outlined,
  'ti-repeat': Icons.repeat,
  // Places
  'ti-home': Icons.home_outlined,
  'ti-building-hospital': Icons.local_hospital_outlined,
  'ti-car': Icons.directions_car_outlined,
  'ti-sun': Icons.wb_sunny_outlined,
  'ti-bath': Icons.bathtub_outlined,
  'ti-sofa': Icons.chair_outlined,
  // Time
  'ti-clock': Icons.access_time,
  'ti-moon': Icons.nightlight_outlined,
  'ti-calendar': Icons.calendar_today_outlined,
  'ti-arrow-back': Icons.arrow_back,
  'ti-arrow-forward': Icons.arrow_forward,
};

IconData iconFor(String tablerName) =>
    _tablerToMaterial[tablerName] ?? Icons.chat_bubble_outline;
