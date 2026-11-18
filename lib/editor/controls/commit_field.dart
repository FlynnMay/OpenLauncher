import 'package:flutter/material.dart';

/// A text field committed on Enter or blur.
class CommitField extends StatefulWidget {
  const CommitField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.help = '',
    this.multiline = false,
    this.fits,
  });

  final String label, value;
  final void Function(String value) onChanged;

  /// Shown while empty, and under the field.
  final String hint, help;

  /// Whether it takes several lines; Enter is then a new line and only
  /// leaving the field commits.
  final bool multiline;

  /// Whether a text is acceptable; one that is not is marked and not kept.
  final bool Function(String text)? fits;

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
    if (value != widget.value && _fine(value)) widget.onChanged(value);
  }

  bool _fine(String text) => widget.fits?.call(text) ?? true;

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
        hintText: widget.hint.isEmpty ? null : widget.hint,
        helperText: widget.help.isEmpty ? null : widget.help,
        errorText: _fine(_text.text.trim()) ? null : 'Not a valid value',
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      minLines: widget.multiline ? 3 : 1,
      maxLines: widget.multiline ? 8 : 1,
      onChanged: widget.fits == null ? null : (_) => setState(() {}),
      onSubmitted: widget.multiline ? null : (_) => _take(),
    ),
  );
}
