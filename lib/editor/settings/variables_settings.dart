import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/variables/variable.dart';
import 'package:openlauncher/editor/controls/controls.dart';

/// A component's variables, generated from [variableOptions].
class VariablesSettings extends ConsumerStatefulWidget {
  const VariablesSettings({
    super.key,
    required this.variables,
    required this.onChanged,
    this.note,
    this.exposable = false,
  });

  final Variables variables;
  final void Function(Variables variables) onChanged;

  /// They are a prefab's own, each with a tick for showing on its instances.
  final bool exposable;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.note case final note?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(note, style: Theme.of(context).textTheme.bodySmall),
          ),
        ListField(
          option: variableOptions(
            entities: {for (final entity in entities) entity.id: entity.label},
            exposable: widget.exposable,
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
      ],
    );
  }
}

/// An instance's values for its prefab's exposed variables, each in a field
/// of its type. One left alone follows the prefab.
class InstanceVariables extends ConsumerWidget {
  const InstanceVariables({
    super.key,
    required this.declared,
    required this.own,
    required this.onChanged,
  });

  /// The prefab's variables, and the instance's.
  final Variables declared, own;
  final void Function(Variables own) onChanged;

  /// The names of [declared] that get a field.
  static Set<String> shown(Variables declared, Variables own) => {
    for (final MapEntry(key: name, value: variable) in declared.entries)
      if (variable.exposed &&
          variable.type != VarType.nodes &&
          !variable.isConditional &&
          !(own[name]?.isConditional ?? false))
        name,
  };

  Field _option(String name, Variable variable, Map<String, String> entities) {
    final value = variable.value;
    return switch (variable.type) {
      VarType.number => Field(
        name,
        name,
        FieldKind.number,
        min: -1000000,
        max: 1000000,
        decimal: true,
        defaultValue: value is num ? value : null,
      ),
      VarType.bool => Field(
        name,
        name,
        FieldKind.toggle,
        defaultValue: value == true,
      ),
      VarType.colour => Field(
        name,
        name,
        FieldKind.colour,
        defaultValue: value,
      ),
      VarType.entity => Field(
        name,
        name,
        FieldKind.choice,
        unset: 'None',
        defaultValue: value,
        choices: {
          // Keeps a saved one that is not there now.
          for (final saved in [value, own[name]?.value])
            if (saved is String && saved.isNotEmpty) saved: saved,
          ...entities,
        },
      ),
      _ => Field(
        name,
        name,
        FieldKind.template,
        defaultValue: value?.toString(),
      ),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = shown(declared, own);
    if (names.isEmpty) return const SizedBox.shrink();
    final entities = {
      for (final entity
          in ref.watch(entitiesProvider).value ?? const <Entity>[])
        entity.id: entity.label,
    };
    Variables without(String name) => {...own}..remove(name);
    final fields = optionFields(
      options: [
        for (final name in names) _option(name, declared[name]!, entities),
      ],
      values: {for (final name in names) name: ?own[name]?.value},
      // A value put back to the prefab's is not stored.
      onChanged: (next) => onChanged({
        for (final MapEntry(key: name, value: variable) in own.entries)
          if (!names.contains(name)) name: variable,
        for (final name in names)
          if (next[name] case final value?)
            // Typed as declared, so an entity it holds is known as one.
            name: Variable(
              value,
              type: declared[name]!.type,
              access: declared[name]!.access,
            ),
      }),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, name) in names.indexed)
          Row(
            children: [
              Expanded(child: fields[index]),
              if (own.containsKey(name))
                IconButton(
                  tooltip: 'Revert to prefab',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.undo, size: 18),
                  onPressed: () => onChanged(without(name)),
                ),
            ],
          ),
      ],
    );
  }
}
