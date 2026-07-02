import 'package:flutter/material.dart';

/// Simple typing overlay (mainly for caregivers): type a word, generate.
class KeyboardSheet extends StatefulWidget {
  const KeyboardSheet({super.key, required this.onSubmit});

  final void Function(String word) onSubmit;

  @override
  State<KeyboardSheet> createState() => _KeyboardSheetState();
}

class _KeyboardSheetState extends State<KeyboardSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onSubmit(value);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Type a word…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(minimumSize: const Size(80, 56)),
            child: const Text('Go', style: TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
  }
}
