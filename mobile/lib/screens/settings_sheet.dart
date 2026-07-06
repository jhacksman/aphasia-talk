import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';

/// Caregiver settings: backend address + the "Their voice" linguistic profile
/// (name, birth year, region, pronouns) that steers generation on the backend.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _urlController;
  final _nameController = TextEditingController();
  final _yearController = TextEditingController();
  String? _region;
  String? _pronouns;
  String? _status;
  bool _busy = false;

  /// Whether the current server profile was successfully loaded into the
  /// form. If it wasn't (backend unreachable when Settings opened), saving
  /// must NOT send the blank fields — that would wipe the stored profile.
  bool _profileLoaded = false;

  /// A free-text region set via the API/web client that isn't one of the
  /// dropdown presets. Preserved as its own menu entry so a mobile save
  /// round-trips it instead of nulling it out.
  String? _customRegion;

  // Speaking-voice section.
  late String _voiceMode; // 'fast' | 'cloned'
  VoiceStatus? _voiceStatus;
  bool _uploadingVoice = false;
  String? _voiceMessage;

  // In-app voice-sample recording (alternative to file upload).
  final AudioRecorder _voiceRecorder = AudioRecorder();
  bool _recordingVoice = false;

  static const _regions = <String, String>{
    'us-south': 'US — South',
    'us-northeast': 'US — Northeast',
    'us-midwest': 'US — Midwest',
    'us-west': 'US — West',
    'uk': 'United Kingdom',
  };

  static const _pronounOptions = <String>['she/her', 'he/him', 'they/them'];

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.state.settings.backendUrl);
    _voiceMode = widget.state.settings.voiceMode;
    _loadProfile();
    _loadVoiceStatus();
  }

  Future<void> _loadVoiceStatus() async {
    try {
      final status = await widget.state.api.voiceStatus();
      if (mounted) setState(() => _voiceStatus = status);
    } on ApiException {
      // Unreachable; section still shows and upload can be retried.
    }
  }

  Future<void> _setVoiceMode(String mode) async {
    await widget.state.settings.setVoiceMode(mode);
    if (mounted) setState(() => _voiceMode = mode);
  }

  Future<void> _uploadVoiceRecording() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null || file.bytes == null) return; // Backed out — fine.
    if (file.size > 50 * 1024 * 1024) {
      // Fail before buffering/uploading a huge file just to be rejected.
      setState(() => _voiceMessage =
          'That file is too large — use a clip under ~5 minutes.');
      return;
    }

    await _sendReference(file.bytes!, file.name);
  }

  /// Shared tail of both capture paths (picked file / in-app recording).
  Future<void> _sendReference(List<int> bytes, String filename) async {
    setState(() {
      _uploadingVoice = true;
      _voiceMessage = null;
    });
    try {
      final status = await widget.state.api.uploadVoiceReference(
        bytes,
        filename: filename,
      );
      if (!mounted) return;
      setState(() {
        _voiceStatus = status;
        _voiceMessage = 'Voice ready — heard: "${_shorten(status.transcript)}"';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // Server answers carry a specific, caregiver-facing message from the
        // backend ("too short", "use .wav or .mp3", …) — show that, not a
        // generic guess that sends them fixing the wrong thing.
        _voiceMessage = e.isServerResponse
            ? e.message
            : 'Couldn\'t reach the speech computer to upload.';
      });
    } finally {
      if (mounted) setState(() => _uploadingVoice = false);
    }
  }

  String _shorten(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.length <= 60 ? text : '${text.substring(0, 57)}…';
  }

  @override
  void dispose() {
    _voiceRecorder.dispose();
    _urlController.dispose();
    _nameController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  /// Record a voice sample right here — no file wrangling needed. Tap to
  /// start, tap again to stop; the recording is uploaded like any file.
  Future<void> _toggleVoiceRecording() async {
    if (_recordingVoice) {
      setState(() => _recordingVoice = false);
      final path = await _voiceRecorder.stop();
      if (path == null) return;
      List<int>? bytes;
      try {
        bytes = await File(path).readAsBytes();
      } catch (_) {
        bytes = null;
      }
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _voiceMessage = 'Nothing was recorded — please try again.');
        return;
      }
      await _sendReference(bytes, 'recorded-in-app.wav');
      return;
    }

    if (!await _voiceRecorder.hasPermission()) {
      if (mounted) {
        setState(() =>
            _voiceMessage = 'Microphone permission is needed to record.');
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    try {
      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: '${dir.path}/voice_sample.wav',
      );
    } catch (_) {
      if (mounted) {
        setState(() => _voiceMessage = 'The microphone isn\'t available right now.');
      }
      return;
    }
    if (mounted) {
      setState(() {
        _recordingVoice = true;
        _voiceMessage =
            'Recording… read a few sentences naturally, then tap Stop.';
      });
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.state.api.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profileLoaded = true;
        _nameController.text = profile.name ?? '';
        _yearController.text = profile.birthYear?.toString() ?? '';
        final region = profile.region;
        if (region != null && !_regions.containsKey(region)) {
          _customRegion = region;
        }
        _region = region;
        _pronouns = profile.pronouns;
      });
    } on ApiException {
      // Backend unreachable; the voice profile stays un-editable this visit
      // (saving blanks would wipe the stored profile).
    }
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !(url.startsWith('http://') || url.startsWith('https://'))) {
      setState(() => _status = 'Enter the address like http://192.168.1.50:8080');
      return;
    }

    int? year;
    final yearText = _yearController.text.trim();
    if (yearText.isNotEmpty) {
      year = int.tryParse(yearText);
      if (year == null || year < 1900 || year > 2030) {
        setState(() => _status = 'Birth year should be between 1900 and 2030.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _status = null;
    });

    // Probes with a short timeout and skips the full reload when unreachable,
    // so a mistyped address reports failure in seconds.
    final online = await widget.state.updateBackendUrl(url);

    // If the profile never loaded, retry the load now that we're connected —
    // never overwrite the server profile with blank fields.
    if (online && !_profileLoaded) {
      await _loadProfile();
    }

    var profileSaved = false;
    if (online && _profileLoaded) {
      try {
        await widget.state.api.updateProfile(Profile(
          name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
          birthYear: year,
          region: _region,
          pronouns: _pronouns,
        ));
        profileSaved = true;
      } on ApiException {
        profileSaved = false;
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = !online
          ? 'Saved the address, but the speech computer didn\'t answer.'
          : profileSaved
              ? 'Connected — everything saved.'
              : 'Connected. Voice profile loaded — check it and save again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Speech computer address', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: const TextStyle(fontSize: 17),
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.50:8080',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Their voice', style: theme.textTheme.labelLarge),
            Text(
              'Helps the AI phrase things the way they would.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _nameController,
                    style: const TextStyle(fontSize: 17),
                    decoration: const InputDecoration(
                      labelText: 'Name (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 17),
                    decoration: const InputDecoration(
                      labelText: 'Birth year',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              // Key forces the field to pick up the async-loaded value.
              key: ValueKey('region-$_region-$_customRegion'),
              initialValue: _region,
              decoration: const InputDecoration(
                labelText: 'Region (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('—')),
                for (final entry in _regions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                // A free-text region set via the web client round-trips
                // instead of being silently erased by a mobile save.
                if (_customRegion != null)
                  DropdownMenuItem(value: _customRegion, child: Text(_customRegion!)),
              ],
              onChanged: (value) => setState(() => _region = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('pronouns-$_pronouns'),
              initialValue: _pronouns,
              decoration: const InputDecoration(
                labelText: 'Pronouns (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('—')),
                for (final p in _pronounOptions)
                  DropdownMenuItem(value: p, child: Text(p)),
                // Free-text pronouns set via the API round-trip instead of
                // being silently erased by a mobile save.
                if (_pronouns != null && !_pronounOptions.contains(_pronouns))
                  DropdownMenuItem(value: _pronouns, child: Text(_pronouns!)),
              ],
              onChanged: (value) => setState(() => _pronouns = value),
            ),
            const SizedBox(height: 20),
            Text('Speaking voice', style: theme.textTheme.labelLarge),
            Text(
              'The voice the tablet speaks with.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _voiceMode,
              onChanged: (mode) {
                if (mode != null) _setVoiceMode(mode);
              },
              child: Column(
                children: [
                  const RadioListTile<String>(
                    value: 'fast',
                    title: Text('Fast (built-in voice)', style: TextStyle(fontSize: 16)),
                    subtitle: Text('Instant; works even when the speech computer is off.'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: 'cloned',
                    title: const Text('My voice (cloned)', style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                      _voiceStatus?.clonedAvailable == true
                          ? 'Ready — from "${_voiceStatus?.originalFilename ?? 'recording'}". '
                              'Falls back to the built-in voice if offline.'
                          : 'Record or upload a voice sample to set this up.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _uploadingVoice ? null : _toggleVoiceRecording,
                  icon: Icon(
                    _recordingVoice ? Icons.stop_circle_outlined : Icons.mic_none,
                    color: _recordingVoice ? Colors.red : null,
                  ),
                  label: Text(
                    _recordingVoice ? 'Stop recording' : 'Record voice sample',
                    style: const TextStyle(fontSize: 15),
                  ),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
                OutlinedButton.icon(
                  onPressed:
                      (_uploadingVoice || _recordingVoice) ? null : _uploadVoiceRecording,
                  icon: _uploadingVoice
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(
                    _uploadingVoice
                        ? 'Uploading…'
                        : _voiceStatus?.clonedAvailable == true
                            ? 'Replace (.wav or .mp3)'
                            : 'Upload file (.wav or .mp3)',
                    style: const TextStyle(fontSize: 15),
                  ),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
              ],
            ),
            if (_voiceMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _voiceMessage!,
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.primary),
                ),
              ),
            const SizedBox(height: 16),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _status!,
                  style: TextStyle(fontSize: 15, color: theme.colorScheme.primary),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                    child: Text(
                      _busy ? 'Saving…' : 'Save & test connection',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(90, 52)),
                  child: const Text('Close', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
