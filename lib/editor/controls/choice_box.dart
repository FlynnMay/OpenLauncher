import 'package:flutter/material.dart';

class ChoiceBox<T> extends StatelessWidget {
  const ChoiceBox({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.hint = 'Mixed',
  });

  final T? value;
  final Map<T, String> choices;

  /// Null disables it.
  final void Function(T value)? onChanged;

  /// Shown with no [value].
  final String hint;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: const InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.fromLTRB(10, 6, 4, 6),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        isExpanded: true,
        isDense: true,
        value: value,
        hint: Text(hint, overflow: TextOverflow.ellipsis),
        items: [
          for (final MapEntry(:key, value: label) in choices.entries)
            DropdownMenuItem(
              value: key,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged == null
            ? null
            : (next) {
                if (next != null && next != value) onChanged!(next);
              },
      ),
    ),
  );
}
