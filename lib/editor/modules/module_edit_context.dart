import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';

/// The body of a module's section in the inspector.
typedef ModuleEditor = List<Widget> Function(ModuleEdit edit);

/// One module of the selected nodes, and how to change it.
class ModuleEdit {
  ModuleEdit({
    required this.type,
    required List<Node> nodes,
    required this.parents,
    required this.onChanged,
    this.onLayout,
    this.prefabs = const {},
    this.inPrefab = false,
    this.exposable = false,
    this.inDock = false,
    this.scope = const {},
  }) : on = [
         for (final node in nodes) !resolved(node, prefabs).isOff(type.name),
       ],
       nodes = [for (final node in nodes) _switchedOn(node, type)],
       drawn = [
         for (final node in nodes) _switchedOn(resolved(node, prefabs), type),
       ];

  final ModuleType type;

  /// As saved, and as drawn: an instance over its prefab. Shown with the
  /// module on, so one switched off still shows its values; changes go
  /// through [onChanged].
  final List<Node> nodes, drawn;

  /// Whether each has the module switched on.
  final List<bool> on;

  /// Their parents; none for a layer's root.
  final List<Node> parents;

  /// Called with a change to apply to each node.
  final void Function(Node Function(Node node) how) onChanged;

  /// For a change that moves other nodes too; null where there are none.
  final void Function(Layout Function(Layout layout) how)? onLayout;

  final Map<String, Prefab> prefabs;

  /// Edited in an open prefab.
  final bool inPrefab;

  /// A prefab's root, whose variables instances can show.
  final bool exposable;

  /// In a docked node.
  final bool inDock;

  /// What its triggers can read from the nodes around it.
  final Variables scope;

  Node get node => nodes.first;
  Node get shown => drawn.first;
  bool get single => nodes.length == 1;
  Set<String> get ids => {for (final node in nodes) node.id};

  /// The first node's values as drawn, without the switch.
  late final ModuleValues values = {...?shown.modules[type.name]}
    ..remove(enabledKey);

  /// Keys whose values differ between the nodes.
  late final Set<String> mixed = {
    for (final key in {
      for (final node in drawn) ...?node.modules[type.name]?.keys,
    })
      if ({for (final node in drawn) jsonEncode(node.modules[type.name]?[key])}
              .length >
          1)
        key,
  };

  /// Whether the single instance's prefab has this module.
  late final bool inherited =
      single &&
      node.isInstance &&
      !type.instanceOwned &&
      resolved(node.withModule(type.name, null), prefabs).added(type.name);

  /// Keys the single instance sets over its prefab's.
  late final Set<String> own = inherited
      ? ({...?node.modules[type.name]?.keys}..remove(enabledKey))
      : const {};

  /// Sets [key] on every node: an instance's over its prefab's.
  void set(String key, Object? value) => onChanged(
    (node) => node.isInstance && !type.instanceOwned
        ? withInstanceValue(node, type, key, value, prefabs)
        : withRule(node, type.name, key, value),
  );

  /// Takes the instance's own [key] away.
  void revert(String key) =>
      onChanged((node) => withInherited(node, type, key, prefabs));

  /// Generated fields for [fields], the module's own by default.
  List<Widget> fields([List<Field>? fields]) => ruleFields(
    options: fields ?? type.fields,
    json: values,
    mixed: mixed,
    marked: own,
    onRevert: revert,
    onChanged: set,
  );
}

Node _switchedOn(Node node, ModuleType type) =>
    node.isOff(type.name) ? node.withValue(type.name, enabledKey, null) : node;
