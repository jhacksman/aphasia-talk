import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/api_service.dart';
import 'services/settings_service.dart';
import 'services/tts_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape is the primary orientation for the two-pane layout (SPEC.md),
  // but portrait remains allowed — the layout adapts rather than locking her out.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  final settings = await SettingsService.load();
  final state = AppState(
    api: ApiService(baseUrl: settings.backendUrl),
    settings: settings,
    tts: TtsService(),
  );
  runApp(AphasiaTalkApp(state: state));
}
