import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

class AphasiaTalkApp extends StatefulWidget {
  const AphasiaTalkApp({super.key, required this.state});

  final AppState state;

  @override
  State<AphasiaTalkApp> createState() => _AphasiaTalkAppState();
}

class _AphasiaTalkAppState extends State<AphasiaTalkApp> {
  @override
  void initState() {
    super.initState();
    widget.state.init();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aphasia Talk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: HomeScreen(state: widget.state),
    );
  }
}
