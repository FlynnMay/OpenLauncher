import 'package:flutter/material.dart';
import 'package:openlauncher/editor/controls/check_choices.dart';

/// Several of [choices] picked from a menu that stays open while ticking.
class MultiDropdown extends StatelessWidget {
  const MultiDropdown({
    super.key,
    required this.chosen,
    required this.choices,
    required this.onChanged,
    this.most,
    this.hint = 'None',
  });

  final Set<String> chosen;
  final Map<String, String> choices;
  final void Function(Set<String> chosen) onChanged;
  final int? most;
  final String hint;

  String get _summary => chosen.isEmpty
      ? hint
      : [
          for (final MapEntry(:key, value: label) in choices.entries)
            if (chosen.contains(key)) label,
        ].join(', ');

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      for (final MapEntry(:key, value: label) in choices.entries)
        CheckboxMenuButton(
          closeOnActivate: false,
          value: chosen.contains(key),
          onChanged: !chosen.contains(key) && choicesFull(chosen, most)
              ? null
              : (on) => onChanged(
                  toggledChoice(choices, chosen, key, on: on == true),
                ),
          child: Text(label),
        ),
    ],
    builder: (context, menu, _) => InkWell(
      onTap: () => menu.isOpen ? menu.close() : menu.open(),
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.fromLTRB(10, 8, 4, 8),
          suffixIcon: Icon(Icons.arrow_drop_down),
          suffixIconConstraints: BoxConstraints(minHeight: 24),
        ),
        child: Text(_summary, overflow: TextOverflow.ellipsis),
      ),
    ),
  );
}
