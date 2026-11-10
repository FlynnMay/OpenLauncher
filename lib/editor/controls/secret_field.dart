import 'package:flutter/material.dart';
import 'package:openlauncher/editor/controls/busy.dart';
import 'package:openlauncher/editor/controls/dialogs.dart';
import 'package:openlauncher_domain/nodes/field.dart';

/// A value that is kept apart and never shown again: dots when it is set, a
/// button to replace it, and a cross that clears it once the user agrees.
class SecretField extends StatefulWidget {
  const SecretField({super.key, required this.label, required this.secret});

  final String label;
  final FieldSecret secret;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> with Busy<SecretField> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Replaces the secret with what was typed; never with nothing.
  Future<void> _replace() => whileBusy(() async {
    await widget.secret.replace(_text.text);
    _text.clear();
  });

  Future<void> _clear() async {
    final sure = await confirm(
      context,
      'Clear ${widget.label}?',
      'It is forgotten on the TV. Whatever uses it cannot sign in until a '
          'new one is saved.',
      'Clear',
    );
    if (!sure || !mounted) return;
    await whileBusy(widget.secret.clear);
  }

  @override
  Widget build(BuildContext context) {
    final isSet = widget.secret.isSet;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: TextField(
              controller: _text,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: widget.label,
                // A kept secret shows as dots and stays until cleared.
                hintText: isSet ? '••••••••••••••••' : 'Not set',
                helperText: isSet
                    ? 'Saved on the TV. Type a new one to replace it.'
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: isSet
                    ? IconButton(
                        tooltip: 'Clear',
                        onPressed: busy ? null : _clear,
                        icon: const Icon(Icons.close),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: busy || _text.text.isEmpty
                  ? null
                  : (_) => _replace(),
            ),
          ),
          FilledButton.tonal(
            onPressed: busy || _text.text.isEmpty ? null : _replace,
            child: Text(isSet ? 'Replace' : 'Save'),
          ),
        ],
      ),
    );
  }
}
