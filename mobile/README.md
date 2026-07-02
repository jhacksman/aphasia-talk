# Aphasia Talk — Mobile App (Flutter)

The tablet app from [`../SPEC.md`](../SPEC.md): tap a word → the DGX Spark
generates sentences → tap one → the tablet speaks it. Android + iOS from one
codebase.

## Architecture

```
lib/
  main.dart              # Bootstrap: orientation, services, run app
  app.dart               # MaterialApp, light/dark theme
  models/models.dart     # Mirrors backend schemas exactly
  services/
    api_service.dart     # HTTP client for the FastAPI backend (injectable for tests)
    settings_service.dart# Backend URL + offline caches (words/sentences/bookmarks)
    tts_service.dart     # Offline system TTS
  state/app_state.dart   # Interaction flow + offline fallback + stale-response guard
  screens/               # Home (the only screen), settings + keyboard sheets
  widgets/               # Output bar, word grid, sentence list, input bar
  theme/, utils/         # Colors (Fitzgerald via backend), Tabler→Material icons
```

Design rules enforced in code (AAC research, see SPEC.md):

- **Buttons never move** — words render strictly by their stored `[row, col]`;
  column count derives from width only, never usage.
- **≥64dp touch targets** — verified by a widget test.
- **No time pressure** — nothing auto-dismisses; snackbars are informational only.
- **Offline resilience** — word grid, last sentences per word, and bookmarks are
  cached locally; the app stays useful when the Spark is off.
- **Stale-response guard** — if she taps a second word before the first
  generation returns, the older response is discarded (tested).

## Develop

```bash
cd mobile
flutter pub get
flutter analyze && flutter test   # must both be clean before any release
flutter run                        # device or emulator
```

Point the app at the backend in Settings (gear icon), e.g.
`http://192.168.1.50:8080`. For a GPU-less dev backend use
`MOCK_INFERENCE=true` (see `../backend/README.md`).

## Release — Android

1. Create a keystore (once):
   `keytool -genkey -v -keystore ~/aphasia-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias aphasia`
2. Create `android/key.properties`:
   ```
   storePassword=...
   keyPassword=...
   keyAlias=aphasia
   storeFile=/absolute/path/to/aphasia-release.jks
   ```
3. Build:
   - Direct family install: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`
   - Play Store: `flutter build appbundle --release`

Without `key.properties` the release build signs with debug keys — fine for
sideloading onto the family tablet, not for the Play Store.

## Release — iOS

Requires a Mac with Xcode and an Apple Developer account.

```bash
flutter build ipa --release
```

Then upload the `.ipa` from `build/ios/ipa/` via Apple Transporter, and
distribute to the family through TestFlight. Signing team is set in
`ios/Runner.xcodeproj` (open with Xcode once to select your team).

App Store review note: the app declares `NSAllowsLocalNetworking` (it talks
HTTP to a home-LAN server) plus microphone/camera usage strings — all in
`ios/Runner/Info.plist` with plain-language justifications.

## Permissions

| Permission | Platform | Why |
|---|---|---|
| Internet / local network | both | Reach the DGX Spark backend on the home LAN |
| Microphone | both | Dictate a word → `/transcribe` (whisper.cpp on the Spark) |
| Camera | both | Photograph an object → `/vision` |

No analytics, no third-party services, no data leaves the LAN.
