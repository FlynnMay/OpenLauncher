import 'package:flutter/material.dart';
import 'package:openlauncher/editor/controls/busy.dart';
import 'package:openlauncher/editor/controls/dialogs.dart';
import 'package:openlauncher_domain/nodes/field.dart';

/// Any field kept apart and never shown again. It only says whether it is
/// set: a hidden box for text and numbers, or its own control for anything
/// else ([inner], given the value being chosen and how to change it). A new
/// value is sent with Replace; a cross clears it once the user agrees.
class SecretField extends StatefulWidget {
  const SecretField({
    super.key,
    required this.label,
    required this.secret,
    required this.kind,
    required this.inner,
  });

  final String label;
  final FieldSecret secret;
  final FieldKind kind;
  final Widget Function(Object? chosen, void Function(Object? next) change)
  inner;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> with Busy<SecretField> {
  final _text = TextEditingController();
  Object? _chosen;

  /// Text and numbers are typed into a hidden box.
  bool get _typed =>
      widget.kind == FieldKind.text || widget.kind == FieldKind.number;

  /// What would be saved, or null while there is nothing to save.
  Object? get _value => switch (widget.kind) {
    _ when !_typed => _chosen,
    _ when _text.text.isEmpty => null,
    FieldKind.number => num.tryParse(_text.text.trim()),
    _ => _text.text,
  };

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Replaces the secret with the new value; never with nothing.
  Future<void> _replace() => whileBusy(() async {
    await widget.secret.replace(_value!);
    if (!mounted) return;
    _text.clear();
    setState(() => _chosen = null);
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
    final canReplace = !busy && _value != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _typed ? _hiddenBox(isSet) : _chosenBox(isSet)),
          FilledButton.tonal(
            onPressed: canReplace ? _replace : null,
            child: Text(isSet ? 'Replace' : 'Save'),
          ),
        ],
      ),
    );
  }

  Widget _clearButton() => IconButton(
    tooltip: 'Clear',
    onPressed: busy ? null : _clear,
    icon: const Icon(Icons.close),
  );

  Widget _hiddenBox(bool isSet) => TextField(
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
      suffixIcon: isSet ? _clearButton() : null,
    ),
    onChanged: (_) => setState(() {}),
    onSubmitted: _value == null || busy ? null : (_) => _replace(),
  );

  Widget _chosenBox(bool isSet) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      widget.inner(_chosen, (next) => setState(() => _chosen = next)),
      if (isSet)
        Row(
          children: [
            const Expanded(
              child: Text('••••••••  Saved on the TV. Choose to replace it.'),
            ),
            _clearButton(),
          ],
        ),
    ],
  );
}
