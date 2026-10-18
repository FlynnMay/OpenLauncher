import 'package:flutter/material.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';
import 'package:openlauncher/editor/settings/settings.dart';

/// Its action chains, one node at a time. Show and hide are for what docks.
List<Widget> triggersEditor(ModuleEdit edit) {
  if (!edit.single) {
    return const [Text('Select one to change what it does.')];
  }
  final node = edit.node;
  return [
    TriggerSettings(
      set: node.on,
      defaults: {...?edit.prefabs[node.prefab]?.on},
      // Its own variables over what the nodes around it hand down.
      scope: {...edit.scope, ...variablesOf(node, edit.prefabs)},
      triggers: [
        Trigger.press,
        Trigger.hold,
        Trigger.focus,
        Trigger.blur,
        if (edit.shown.offCells) ...[Trigger.reveal, Trigger.hide],
      ],
      onChanged: (on) => edit.onChanged((node) => withPressable(node, on)),
    ),
  ];
}
