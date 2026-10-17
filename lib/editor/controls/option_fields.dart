import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/editor/controls/choice_box.dart';
import 'package:openlauncher/editor/controls/colour_picker.dart';
import 'package:openlauncher/editor/controls/commit_field.dart';
import 'package:openlauncher/editor/controls/corner_settings.dart';
import 'package:openlauncher/editor/controls/dialogs.dart';
import 'package:openlauncher/editor/controls/fill_field.dart';
import 'package:openlauncher/editor/controls/icon_field.dart';
import 'package:openlauncher/editor/controls/labelled_row.dart';
import 'package:openlauncher/editor/controls/number_field.dart';
import 'package:openlauncher/editor/controls/template_field.dart';
import 'package:openlauncher/editor/controls/tick_box.dart';

/// Generated fields for [options] showing [values]. Reports the whole value
/// map; a value reset to its default is removed. [mixed] keys show as mixed;
/// [marked] keys as set over what they inherit, with [onRevert] to undo that.
List<Widget> optionFields({
  required List<Field> options,
  required Map<String, Object?> values,
  required void Function(Map<String, Object?> values) onChanged,
  double corner = 10,
  Set<String> mixed = const {},
  Set<String> marked = const {},
  void Function(String key)? onRevert,
}) {
  void set(Field option, Object? value) => onChanged(
    {...values, option.key: value == option.defaultValue ? null : value}
      ..removeWhere((_, value) => value == null),
  );
  Widget field(Field option) {
    final value = values[option.key] ?? option.defaultValue;
    switch (option.kind) {
      case FieldKind.template:
        return TemplateField(
          label: option.label,
          value: value is String ? value : '',
          onChanged: (text) => set(option, text.isEmpty ? null : text),
        );
      case FieldKind.text:
        return CommitField(
          label: option.label,
          value: value is String ? value : '',
          onChanged: (text) => set(option, text),
        );
      case FieldKind.value:
        return CommitField(
          label: option.label,
          value: value == null ? '' : '$value',
          onChanged: (text) => set(option, typedValue(text)),
        );
      case FieldKind.list:
        return ListField(
          option: option,
          records: [
            if (value case final List<Object?> several)
              for (final one in several)
                if (one is Map) one.cast(),
          ],
          onChanged: (records) => set(option, records),
        );
      case FieldKind.toggle:
        return TickBox(
          label: option.label,
          value: value == true,
          onChanged: (on) => set(option, on),
        );
      case FieldKind.number:
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
      case FieldKind.choice:
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
      case FieldKind.icon:
        return IconField(
          label: option.label,
          value: value is String ? value : '',
          onChanged: (name) => set(option, name.isEmpty ? null : name),
        );
      case FieldKind.colour:
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
      case FieldKind.fill:
        return FillField(
          label: option.label,
          value: value,
          onChanged: (fill) => set(option, fill),
        );
      case FieldKind.corners:
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
      if (option.when?.call(values) ?? true)
        marked.contains(option.key)
            ? Overridden(
                onRevert: onRevert == null ? null : () => onRevert(option.key),
                child: field(option),
              )
            : field(option),
  ];
}

/// A field set over what it inherits: a bar beside it and a revert.
class Overridden extends StatelessWidget {
  const Overridden({super.key, required this.child, this.onRevert});

  final Widget child;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colour, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Row(
          children: [
            Expanded(child: child),
            if (onRevert != null)
              IconButton(
                tooltip: 'Revert to prefab',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.undo, size: 18),
                onPressed: onRevert,
              ),
          ],
        ),
      ),
    );
  }
}

/// The same for a thing saved as [json]: reports one key and its new value,
/// null for the default.
List<Widget> ruleFields({
  required List<Field> options,
  required Map<String, Object?> json,
  required void Function(String key, Object? value) onChanged,
  double corner = 10,
  Set<String> mixed = const {},
  Set<String> marked = const {},
  void Function(String key)? onRevert,
}) => optionFields(
  options: options,
  values: json,
  corner: corner,
  mixed: mixed,
  marked: marked,
  onRevert: onRevert,
  onChanged: (next) {
    for (final option in options) {
      // Two options may share a key, each applying at a different time.
      if ((option.when?.call(json) ?? true) &&
          next[option.key] != json[option.key]) {
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

  final Field option;
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
