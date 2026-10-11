import 'package:flutter/material.dart';
import 'package:openlauncher/core/variables/variable.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/option_fields.dart';

/// The variables of one component: each named, with what it is, who may
/// read it, and, for one that is conditional, what it looks at and what it
/// is for each case. The form is made from [variableOptions]. Knows nothing
/// of what the component is.
class VariablesSettings extends StatelessWidget {
  const VariablesSettings({
    super.key,
    required this.variables,
    required this.onChanged,
    this.note,
  });

  final Variables variables;
  final void Function(Variables variables) onChanged;

  /// Said above them, where there is something to say of whose they are.
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
