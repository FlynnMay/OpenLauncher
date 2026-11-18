import 'package:flutter/material.dart';

/// One of [choices] in a column of radio buttons.
class RadioChoices extends StatelessWidget {
  const RadioChoices({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String? value;
  final Map<String, String> choices;
  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final MapEntry(:key, value: label) in choices.entries)
        InkWell(
          onTap: () => onChanged(key),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  key == value
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: key == value
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                Expanded(child: Text(label)),
              ],
            ),
          ),
        ),
    ],
  );
}

/// One of [choices] as a row of joined buttons.
class SegmentedChoice extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String? value;
  final Map<String, String> choices;
  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    emptySelectionAllowed: true,
    showSelectedIcon: false,
    selected: {?value},
    segments: [
      for (final MapEntry(:key, value: label) in choices.entries)
        ButtonSegment(value: key, label: Text(label)),
    ],
    onSelectionChanged: (next) {
      if (next.isNotEmpty) onChanged(next.first);
    },
  );
}
