import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';

/// How it arranges its children, and whether new apps go in it.
List<Widget> layoutEditor(ModuleEdit edit) => [
  ...edit.fields(),
  // Not an instance or in a prefab, nor docked or in something docked.
  if (edit.onLayout case final onLayout?
      when edit.single &&
          !edit.node.isInstance &&
          !edit.inPrefab &&
          !edit.inDock &&
          !edit.shown.offCells &&
          edit.parents.isNotEmpty)
    Consumer(
      builder: (context, ref, _) => TickBox(
        label: 'New apps go here',
        value: ref.watch(inboxProvider) == edit.node.id,
        onChanged: (here) {
          if (here) onLayout((layout) => withInbox(layout, edit.node.id));
        },
      ),
    ),
];
