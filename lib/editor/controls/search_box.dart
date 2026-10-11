import 'package:flutter/material.dart';

/// A dropdown that filters as you type, with its choices under headings.
class SearchBox extends StatefulWidget {
  const SearchBox({
    super.key,
    required this.value,
    required this.groups,
    required this.onChanged,
    this.hint = '',
  });

  final String? value;

  /// Choices with their labels, by heading; an empty heading shows none.
  final Map<String, Map<String, String>> groups;
  final void Function(String value) onChanged;
  final String hint;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _text = TextEditingController();

  String get _label {
    for (final choices in widget.groups.values) {
      if (choices[widget.value] case final label?) return label;
    }
    return '';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      // What was typed and not picked is dropped.
      onFocusChange: (focused) {
        if (!focused && _text.text != _label) _text.text = _label;
      },
      child: DropdownMenu<String>(
        controller: _text,
        initialSelection: widget.value,
        expandedInsets: EdgeInsets.zero,
        enableFilter: true,
        requestFocusOnTap: true,
        menuHeight: 320,
        hintText: widget.hint,
        textStyle: theme.textTheme.bodyMedium,
        inputDecorationTheme: const InputDecorationTheme(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.fromLTRB(10, 6, 0, 6),
          constraints: BoxConstraints(maxHeight: 36),
        ),
        dropdownMenuEntries: [
          for (final MapEntry(key: heading, value: choices)
              in widget.groups.entries) ...[
            if (heading.isNotEmpty && choices.isNotEmpty)
              DropdownMenuEntry(
                value: '\u0000$heading',
                label: heading,
                enabled: false,
                labelWidget: Text(heading, style: theme.textTheme.labelSmall),
              ),
            for (final MapEntry(key: id, value: label) in choices.entries)
              DropdownMenuEntry(value: id, label: label),
          ],
        ],
        onSelected: (next) {
          if (next != null && next != widget.value) widget.onChanged(next);
        },
      ),
    );
  }
}
