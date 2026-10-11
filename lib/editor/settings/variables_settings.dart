import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/variables/variable.dart';
import 'package:openlauncher/editor/controls/controls.dart';

/// A component's variables, generated from [variableOptions].
class VariablesSettings extends ConsumerStatefulWidget {
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
  ConsumerState<VariablesSettings> createState() => _VariablesSettingsState();
}

class _VariablesSettingsState extends ConsumerState<VariablesSettings> {
  /// Variables whose value is being written as a template. Not saved: a
  /// value that is one says so itself.
  var _expressions = <Object?>{};

  static bool _written(Object? value) =>
      value is String && value.contains('{{');

  void _take(List<Map<String, Object?>> form) {
    setState(
      () => _expressions = {
        for (final one in form)
          if (one['expression'] == true) one['name'],
      },
    );
    widget.onChanged(
      variablesFromForm([
        for (final one in form)
          // Switched back to its own control, a template is dropped.
          hasTypedValue(one) &&
                  one['expression'] != true &&
                  _written(one['value'])
              ? ({...one}..remove('value'))
              : one,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    return Section('Variables', open: false, [
      if (widget.note case final note?)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(note, style: Theme.of(context).textTheme.bodySmall),
        ),
      ListField(
        option: variableOptions(
          entities: {for (final entity in entities) entity.id: entity.label},
        ),
        records: [
          for (final one in variablesToForm(widget.variables))
            _expressions.contains(one['name'])
                ? {
                    ...one,
                    'expression': true,
                    if (one['value'] case final value?) 'value': '$value',
                  }
                : one,
        ],
        onChanged: _take,
      ),
    ]);
  }
}
