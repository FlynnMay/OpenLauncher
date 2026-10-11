import 'package:flutter/material.dart';
import 'package:openlauncher/core/variables/variable.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/option_fields.dart';

/// A component's variables, generated from [variableOptions].
class VariablesSettings extends StatelessWidget {
  const VariablesSettings({
    super.key,
    required this.variables,
    required this.onChanged,
    this.note,
  });

  final Variables variables;
  final void Function(Variables variables) onChanged;

  /// A note shown above them.
  final String? note;

  @override
  Widget build(BuildContext context) => Section('Variables', open: false, [
    if (note case final note?)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(note, style: Theme.of(context).textTheme.bodySmall),
      ),
    ListField(
      option: variableOptions,
      records: variablesToForm(variables),
      onChanged: (form) => onChanged(variablesFromForm(form)),
    ),
  ]);
}
