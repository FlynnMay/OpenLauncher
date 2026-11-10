import 'package:flutter/material.dart';

/// [chosen] with [key] on or off, in the order of [choices].
Set<String> toggledChoice(
  Map<String, String> choices,
  Set<String> chosen,
  String key, {
  required bool on,
}) => {
  for (final one in choices.keys)
    if (one == key ? on : chosen.contains(one)) one,
};

/// Whether [chosen] has reached [most], so no other may be added.
bool choicesFull(Set<String> chosen, int? most) =>
    most != null && chosen.length >= most;

/// Several of [choices], each a checkbox. With [most] chosen the rest are
/// off until one is unticked.
class CheckChoices extends StatelessWidget {
  const CheckChoices({
    super.key,
    required this.chosen,
    required this.choices,
    required this.onChanged,
    this.most,
  });

  final Set<String> chosen;
  final Map<String, String> choices;
  final void Function(Set<String> chosen) onChanged;
  final int? most;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final MapEntry(:key, value: label) in choices.entries)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(label),
          value: chosen.contains(key),
          onChanged: !chosen.contains(key) && choicesFull(chosen, most)
              ? null
              : (on) => onChanged(
                  toggledChoice(choices, chosen, key, on: on == true),
                ),
        ),
    ],
  );
}

/// The same as chips that light up when chosen.
class ChipChoices extends StatelessWidget {
  const ChipChoices({
    super.key,
    required this.chosen,
    required this.choices,
    required this.onChanged,
    this.most,
  });

  final Set<String> chosen;
  final Map<String, String> choices;
  final void Function(Set<String> chosen) onChanged;
  final int? most;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final MapEntry(:key, value: label) in choices.entries)
        FilterChip(
          label: Text(label),
          selected: chosen.contains(key),
          onSelected: !chosen.contains(key) && choicesFull(chosen, most)
              ? null
              : (on) => onChanged(toggledChoice(choices, chosen, key, on: on)),
        ),
    ],
  );
}
