import 'dart:math';

import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';

/// Cells or share in the parents' Layouts: only what applies in all of them.
List<Widget> sizingEditor(ModuleEdit edit) {
  final parents = edit.parents;
  if (parents.isEmpty ||
      !parents.every((parent) => parent.has(layoutModule.name)) ||
      edit.drawn.any((node) => node.offCells)) {
    return const [Text('Only a child of a node with a Layout is sized by it.')];
  }
  final nodes = edit.nodes;
  final now = {
    'w': [for (final node in nodes) node.w],
    'h': [for (final node in nodes) node.h],
    'x': [for (final node in nodes) node.x],
    'y': [for (final node in nodes) node.y],
    'flex': [for (final node in nodes) node.flex],
    'aspect': [for (final node in nodes) node.aspect],
  };
  void set(String key, Object? value) {
    final number = (value as num?)?.toDouble();
    if (edit.onLayout case final onLayout?) {
      onLayout((layout) => transformItems(layout, edit.ids, key, number));
    } else {
      edit.onChanged((node) => node.withValue(sizingModule.name, key, number));
    }
  }

  return [
    ...ruleFields(
      options: SizingModule.fieldsIn(
        parents,
        parents.map((parent) => parent.reach).reduce(min),
      ),
      json: {
        for (final MapEntry(:key, :value) in now.entries)
          key: ?shared<double?>(value),
      },
      mixed: {
        for (final MapEntry(:key, :value) in now.entries)
          if (value.toSet().length > 1) key,
      },
      onChanged: set,
    ),
    if (parents.every((parent) => parent.mode != LayoutMode.free))
      TickBox(
        label: 'Keep space when hidden',
        value: shared(nodes.map((node) => node.keep)) ?? false,
        onChanged: (keep) => edit.onChanged(
          (node) =>
              node.withValue(sizingModule.name, 'keep', keep ? true : null),
        ),
      ),
  ];
}
