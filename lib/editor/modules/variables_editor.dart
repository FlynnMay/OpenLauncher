import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';
import 'package:openlauncher/editor/settings/settings.dart';

/// Its variables, one node at a time. An instance first shows a field for
/// each its prefab exposes, then its own.
List<Widget> variablesEditor(ModuleEdit edit) {
  if (!edit.single) {
    return const [Text('Select one to change its variables.')];
  }
  final node = edit.node;
  final declared =
      edit.prefabs[node.prefab]?.root.vars ?? const <String, Variable>{};
  final fielded = node.isInstance
      ? InstanceVariables.shown(declared, node.vars)
      : const <String>{};
  // Kept when it has none, so the module stays.
  Node withVariables(Node node, Variables vars) =>
      node.withModule(variablesModule.name, variablesToJson(vars));
  return [
    if (node.isInstance && declared.isNotEmpty)
      InstanceVariables(
        declared: declared,
        own: node.vars,
        onChanged: (vars) =>
            edit.onChanged((node) => withVariables(node, vars)),
      ),
    VariablesSettings(
      variables: {
        for (final MapEntry(key: name, :value) in node.vars.entries)
          if (!fielded.contains(name)) name: value,
      },
      note: node.isInstance
          ? 'Its own, besides the prefab\'s. One named as a prefab variable '
                'overrides it.'
          : null,
      exposable: edit.exposable,
      onChanged: (vars) => edit.onChanged(
        (node) => withVariables(node, {
          for (final MapEntry(key: name, :value) in node.vars.entries)
            if (fielded.contains(name)) name: value,
          ...vars,
        }),
      ),
    ),
  ];
}
