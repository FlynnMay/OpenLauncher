import 'package:flutter/material.dart';

/// A text field committed on Enter or blur.
class CommitField extends StatefulWidget {
  const CommitField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label, value;
  final void Function(String value) onChanged;

  @override
  State<CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<CommitField> {
  late final _text = TextEditingController(text: widget.value);
  late final FocusNode _focus = FocusNode()
    ..addListener(() {
      if (!_focus.hasFocus) _take();
    });

  void _take() {
    final value = _text.text.trim();
    if (value != widget.value) widget.onChanged(value);
  }

  @override
  void didUpdateWidget(CommitField old) {
    super.didUpdateWidget(old);
    // Updated from outside while not focused.
    if (widget.value != old.value && !_focus.hasFocus) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: _text,
      focusNode: _focus,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _take(),
    ),
  );
}
