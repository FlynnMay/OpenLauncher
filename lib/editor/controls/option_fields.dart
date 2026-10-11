import 'package:flutter/material.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/choice_box.dart';
import 'package:openlauncher/editor/controls/colour_picker.dart';
import 'package:openlauncher/editor/controls/commit_field.dart';
import 'package:openlauncher/editor/controls/corner_settings.dart';
import 'package:openlauncher/editor/controls/dialogs.dart';
import 'package:openlauncher/editor/controls/fill_field.dart';
import 'package:openlauncher/editor/controls/labelled_row.dart';
import 'package:openlauncher/editor/controls/number_field.dart';
import 'package:openlauncher/editor/controls/template_field.dart';
import 'package:openlauncher/editor/controls/tick_box.dart';
import 'package:openlauncher/features/home/tile_icons.dart';

/// Generated fields for [options] showing [values]. Reports the whole value
/// map; a value reset to its default is removed. [mixed] keys show as mixed.
List<Widget> optionFields({
  required List<ComponentOption> options,
  required Map<String, Object?> values,
  required void Function(Map<String, Object?> values) onChanged,
  double corner = 10,
  Set<String> mixed = const {},
}) {
  void set(ComponentOption option, Object? value) => onChanged(
    {...values, option.key: value == option.defaultValue ? null : value}
      ..removeWhere((_, value) => value == null),
  );
  Widget field(ComponentOption option) {
    final value = values[option.key] ?? option.defaultValue;
    switch (option.kind) {
      case OptionKind.template:
        return TemplateField(
          label: option.label,
          value: value is String ? value : '',
          onChanged: (text) => set(option, text.isEmpty ? null : text),
        );
      case OptionKind.text:
        return CommitField(
          label: option.label,
          value: value is String ? value : '',
          onChanged: (text) => set(option, text),
        );
      case OptionKind.value:
        return CommitField(
          label: option.label,
          value: value == null ? '' : '$value',
          onChanged: (text) => set(option, typedValue(text)),
        );
      case OptionKind.list:
        return ListField(
          option: option,
          records: [
            if (value case final List<Object?> several)
              for (final one in several)
                if (one is Map) one.cast(),
          ],
          onChanged: (records) => set(option, records),
        );
      case OptionKind.toggle:
        return TickBox(
          label: option.label,
          value: value == true,
          onChanged: (on) => set(option, on),
        );
      case OptionKind.number:
        final fallback = option.defaultValue;
        return NumberField(
          label: option.label,
          value: mixed.contains(option.key) || value is! num
              ? null
              : value.toDouble(),
          mixed: mixed.contains(option.key),
          min: option.min,
          max: option.max,
          step: option.step,
          decimal: option.decimal,
          placeholder: option.unset,
          start: fallback is num ? fallback.round() : null,
          onChanged: (number) => set(option, number),
          // One with a default is cleared back to it.
          onCleared:
              values[option.key] != null &&
                  (option.unset != null || fallback != null)
              ? () => set(option, null)
              : null,
        );
      case OptionKind.choice:
        return LabelledRow(
          option.label,
          ChoiceBox<String>(
            // One that may be left unmade has that among its choices.
            value: option.choices.containsKey(value)
                ? value as String
                : option.unset == null
                ? null
                : '',
            choices: {'': ?option.unset, ...option.choices},
            onChanged: (choice) => set(option, choice.isEmpty ? null : choice),
          ),
        );
      case OptionKind.icon:
        return LabelledRow(
          option.label,
          ChoiceBox<String>(
            value: tileIcons.containsKey(value) ? value as String : '',
            choices: {
              '': 'None',
              for (final name in tileIcons.keys) name: name,
            },
            onChanged: (name) => set(option, name.isEmpty ? null : name),
          ),
        );
      case OptionKind.colour:
        return LabelledRow(
          option.label,
          Align(
            alignment: Alignment.centerLeft,
            child: ColourChip(
              colour: BoxStyle.parseColor(value),
              onChanged: (next) =>
                  set(option, next == null ? null : BoxStyle.colorToCss(next)),
            ),
          ),
        );
      case OptionKind.fill:
        return FillField(
          label: option.label,
          value: value,
          onChanged: (fill) => set(option, fill),
        );
      case OptionKind.corners:
        return CornerSettings(
          label: option.label,
          corners: BoxStyle.of({option.key: value}).corners,
          defaultValue: corner,
          max: option.max * 1.0,
          // Collapsed to one value when all four match.
          onChanged: (corners) => set(
            option,
            corners?.toSet().length == 1 ? corners!.first : corners,
          ),
        );
    }
  }

  return [
    for (final option in options)
      if (option.when?.call(values) ?? true) field(option),
  ];
}

/// The same for a thing saved as [json]: reports one key and its new value,
/// null for the default.
List<Widget> ruleFields({
  required List<ComponentOption> options,
  required Map<String, Object?> json,
  required void Function(String key, Object? value) onChanged,
  double corner = 10,
  Set<String> mixed = const {},
}) => optionFields(
  options: options,
  values: json,
  corner: corner,
  mixed: mixed,
  onChanged: (next) {
    for (final option in options) {
      if (next[option.key] != json[option.key]) {
        onChanged(option.key, next[option.key]);
      }
    }
  },
);

/// A list option: each entry's fields, a remove button and an add button.
/// Reports the whole list.
class ListField extends StatelessWidget {
  const ListField({
    super.key,
    required this.option,
    required this.records,
    required this.onChanged,
    this.after,
  });

  final ComponentOption option;
  final List<Map<String, Object?>> records;
  final void Function(List<Map<String, Object?>> records) onChanged;

  /// Extra widgets under an entry.
  final List<Widget> Function(Map<String, Object?> one)? after;

  void _put(int index, Map<String, Object?>? changed) => onChanged([
    for (final (i, one) in records.indexed)
      if (i != index) one else ?changed,
  ]);

  Future<void> _add(BuildContext context) async {
    var one = option.blank;
    if (option.asks case final title?) {
      final heading = option.heading!;
      final name = await askName(
        context,
        '${one[heading] ?? ''}',
        title: title,
      );
      if (name == null || name.isEmpty) return;
      one = {...one, heading: name};
    }
    onChanged([...records, one]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = option.heading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (records.isEmpty && heading == null)
          Text('None', style: theme.textTheme.bodySmall),
        for (final (index, one) in records.indexed)
          ...() {
            final fields = optionFields(
              options: option.fields!(one),
              values: one,
              onChanged: (changed) => _put(index, changed),
            );
            // Without a heading field, the first field is the heading.
            final headed = heading != null || fields.isEmpty;
            return [
              Row(
                children: [
                  Expanded(
                    child: headed
                        ? Text(
                            '${one[heading] ?? ''}',
                            style: theme.textTheme.titleSmall,
                          )
                        : fields.first,
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _put(index, null),
                  ),
                ],
              ),
              ...fields.skip(headed ? 0 : 1),
              ...?after?.call(one),
              if (heading != null) const Divider(height: 24),
            ];
          }(),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: records.length >= option.max
                ? null
                : () => _add(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(option.label),
          ),
        ),
      ],
    );
  }
}
