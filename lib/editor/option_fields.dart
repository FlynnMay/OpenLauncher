import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widget_option.dart';
import 'package:openlauncher/editor/colour_picker.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/template_field.dart';
import 'package:openlauncher/features/home/tile_icons.dart';

/// The settings [options] describes, each drawn by the kind it is, showing
/// what [values] has for it. A change is told as the whole of the values
/// as they are to be; one set back to its usual is no longer among them.
List<Widget> optionFields({
  required List<WidgetOption> options,
  required Map<String, Object?> values,
  required void Function(Map<String, Object?> values) onChanged,
}) {
  void set(WidgetOption option, Object? value) => onChanged(
    {...values, option.key: value == option.usual ? null : value}
      ..removeWhere((_, value) => value == null),
  );
  Widget field(WidgetOption option) {
    final value = values[option.key] ?? option.usual;
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
      case OptionKind.toggle:
        return TickBox(
          label: option.label,
          value: value == true,
          onChanged: (on) => set(option, on),
        );
      case OptionKind.number:
        return NumberStepper(
          label: option.label,
          // Unset, it is below the least there is, which reads as that.
          value: value is num
              ? value.toDouble()
              : (option.min - option.step) * 1.0,
          min: option.min,
          max: option.max,
          step: option.step,
          usual: option.unset,
          onChanged: (number) =>
              set(option, number < option.min ? null : number),
        );
      case OptionKind.choice:
        return LabelledRow(
          option.label,
          ChoiceBox<String>(
            value: option.choices.containsKey(value) ? value as String : null,
            choices: option.choices,
            onChanged: (choice) => set(option, choice),
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
            // White until another colour is chosen.
            child: ColourChip(
              colour: BoxStyle.parseColor(value) ?? 0xFFFFFFFF,
              onChanged: (next) =>
                  set(option, next == null ? null : BoxStyle.colorToCss(next)),
            ),
          ),
        );
    }
  }

  return [
    for (final option in options)
      if (option.when?.call(values) ?? true) field(option),
  ];
}

/// The same for a thing that is saved as [json], such as a pane with its
/// rules: each setting shows what the thing has under its name, and a
/// change is told as that name and what it is to be, null for the usual.
List<Widget> ruleFields({
  required List<WidgetOption> options,
  required Map<String, Object?> json,
  required void Function(String key, Object? value) onChanged,
}) => optionFields(
  options: options,
  values: json,
  onChanged: (next) {
    for (final option in options) {
      if (next[option.key] != json[option.key]) {
        onChanged(option.key, next[option.key]);
      }
    }
  },
);
